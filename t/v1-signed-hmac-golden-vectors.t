use v5.34;
use strict;
use warnings;

use FindBin;
use File::Basename qw(dirname);
use File::Spec;
use JSON::PP qw(decode_json);
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::Witness qw(witness_for_listing);

my $repo_root   = File::Spec->rel2abs("$FindBin::Bin/..");
my $vector_path = "$FindBin::Bin/fixtures/vectors/v1-signed-hmac-witness.jsonl";
my $schema_path = "$FindBin::Bin/../docs/DIAGNOSTICS.md";

my %trusted_hmac_keys = (
    'fixture-key-1' => 'gobanftp signed hmac fixture key 1',
);

my @witness_fields = qw(
    profile_id
    profile_consensus_version
    adapter_id
    game_descriptor
    ruleset_id
    ruleset_semver
    ruleset_seal_version
    ruleset_fixture_digest
    ruleset_seal
    raw_count
    normalized_count
    normalized_events
    accepted_count
    accepted_events
    rejected_count
    rejected_codes
    rejected_classes
    event_set_root
    replay_status
    canonical_tip
    canonical_ids
    legal_ids
    diagnostic_codes
    diagnostic_classes
    diagnostic_count
    board_hash
    sgf_hash
    variations_sgf_hash
);

my @vectors = _read_jsonl($vector_path);
ok @vectors, 'loaded signed-HMAC witness golden vectors';

my %seen_id;
for my $vector (@vectors) {
    my $id = $vector->{id} // '<missing id>';
    subtest $id => sub {
        ok !$seen_id{$id}++, 'vector id is unique';

        for my $field (qw(id input_fixture attestation_fixture attestation_count trusted_hmac_key_ids), @witness_fields) {
            ok exists $vector->{$field}, "vector has $field";
        }

        like $vector->{input_fixture},
            qr{\At/fixtures/v1/signed-hmac/[^/]+/signed-hmac-goftp1/listing\.names\z},
            'input fixture points at a signed-HMAC listing';
        like $vector->{attestation_fixture},
            qr{\At/fixtures/v1/signed-hmac/[^/]+/signed-hmac-goftp1/attestations\.jsonl\z},
            'attestation fixture points at signed-HMAC attestations';
        is_deeply $vector->{trusted_hmac_key_ids}, ['fixture-key-1'],
            'vector records the public trust selector';

        my $listing_path = File::Spec->rel2abs($vector->{input_fixture}, $repo_root);
        my $case_dir     = dirname(dirname($listing_path));
        my $game_path    = File::Spec->catfile($case_dir, 'game.name');

        my $game = _read_single($game_path);
        is $game, $vector->{game_descriptor}, 'vector game descriptor matches fixture';

        my @raw = _read_names($listing_path);
        my @attestations = _read_jsonl(
            File::Spec->rel2abs($vector->{attestation_fixture}, $repo_root),
        );
        is scalar(@attestations), $vector->{attestation_count},
            'attestation count matches fixture';

        my $witness = witness_for_listing(
            profile_id              => $vector->{profile_id},
            game_descriptor         => $game,
            raw_names               => \@raw,
            diagnostics_schema_path => $schema_path,
            hmac_attestations       => \@attestations,
            trusted_hmac_keys       => \%trusted_hmac_keys,
        );

        for my $field (@witness_fields) {
            my $got  = $witness->{$field};
            my $want = $vector->{$field};
            if (ref $want) {
                is_deeply $got, $want, "$field matches golden vector";
            }
            else {
                is $got, $want, "$field matches golden vector";
            }
        }
    };
}

for my $case (qw(valid missing-signature wrong-signature payload-mismatch untrusted-key-id malformed-signature)) {
    ok $seen_id{"signed-hmac-$case"}, "$case signed-HMAC vector is present";
}

done_testing;

sub _read_jsonl {
    my ($path) = @_;

    open my $fh, '<:encoding(UTF-8)', $path or die "open $path: $!";

    my @rows;
    while (my $line = <$fh>) {
        chomp $line;
        next if $line =~ /\A\s*\z/;
        push @rows, decode_json($line);
    }

    close $fh or die "close $path: $!";

    return @rows;
}

sub _read_single {
    my ($path) = @_;

    my @names = _read_names($path);
    die "$path must contain exactly one nonblank line" if @names != 1;
    return $names[0];
}

sub _read_names {
    my ($path) = @_;

    open my $fh, '<:encoding(UTF-8)', $path or die "open $path: $!";
    my @names;
    while (my $line = <$fh>) {
        chomp $line;
        next if $line =~ /\A\s*\z/;
        push @names, $line;
    }
    close $fh or die "close $path: $!";

    return @names;
}
