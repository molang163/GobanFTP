use v5.34;
use strict;
use warnings;

use Cwd qw(abs_path);
use FindBin;
use File::Basename qw(dirname);
use File::Spec;
use JSON::PP qw(decode_json encode_json);
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::Auth::KeyID qw(parse_public_key_record);
use GobanFTP::Auth::TrustReport qw(trust_report_summary);
use GobanFTP::Witness qw(witness_for_listing);

my $repo_root   = File::Spec->rel2abs("$FindBin::Bin/..");
my $vector_path = "$FindBin::Bin/fixtures/vectors/v1-signed-hmac-witness.jsonl";
my $schema_path = "$FindBin::Bin/../docs/DIAGNOSTICS.md";

my %trusted_hmac_keys = (
    'fixture-key-1' => 'gobanftp signed hmac fixture key 1',
);
my $public_trust_bridge_key_id = 'k1.jk4bs0r77srdlpds260hka9fpp49clpg';
my %public_trust_bridge_expect = (
    'signed-hmac-public-trust-bridge-k1-rejected' => {
        trusted_hmac_key_ids => [$public_trust_bridge_key_id],
        trusted_hmac_key_statuses => { $public_trust_bridge_key_id => 'trusted' },
    },
    'signed-hmac-public-trust-bridge-hmac-trusted' => {
        trusted_hmac_key_ids => ['fixture-key-1'],
        trusted_hmac_key_statuses => { 'fixture-key-1' => 'trusted' },
    },
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
    rejected_diagnostics
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
    replay_diagnostics
    board_hash
    sgf_hash
    variations_sgf_hash
    projection_text
);

my @vectors = _read_jsonl($vector_path);
ok @vectors, 'loaded signed-HMAC witness golden vectors';

my %seen_id;
for my $vector (@vectors) {
    my $id = $vector->{id} // '<missing id>';
    subtest $id => sub {
        ok !$seen_id{$id}++, 'vector id is unique';

        for my $field (qw(id input_fixture input_names attestation_fixture attestation_count trusted_hmac_key_ids trusted_hmac_key_statuses), @witness_fields) {
            ok exists $vector->{$field}, "vector has $field";
        }

        like $vector->{input_fixture},
            qr{\At/fixtures/v1/signed-hmac/[^/]+/signed-hmac-goftp1/listing\.names\z},
            'input fixture points at a signed-HMAC listing';
        like $vector->{attestation_fixture},
            qr{\At/fixtures/v1/signed-hmac/[^/]+/signed-hmac-goftp1/(?:k1-)?attestations\.jsonl\z},
            'attestation fixture points at signed-HMAC attestations';
        ok ref($vector->{trusted_hmac_key_ids}) eq 'ARRAY',
            'vector records trusted HMAC key selectors';
        ok @{ $vector->{trusted_hmac_key_ids} },
            'vector has at least one trusted HMAC key selector';
        is_deeply [sort keys %{ $vector->{trusted_hmac_key_statuses} }],
            [sort @{ $vector->{trusted_hmac_key_ids} }],
            'vector records lifecycle status for every trusted selector';
        for my $key_id (@{ $vector->{trusted_hmac_key_ids} }) {
            like $key_id, qr/\A(?:fixture-key-1|k1[.][0-9a-v]{32})\z/,
                'trusted selector is fixture HMAC id or public k1 namespace';
            like $vector->{trusted_hmac_key_statuses}{$key_id},
                qr/\A(?:trusted|rotated|revoked|expired)\z/,
                'vector records a supported lifecycle status';
        }
        if (my $expected = $public_trust_bridge_expect{$id}) {
            is_deeply $vector->{trusted_hmac_key_ids}, $expected->{trusted_hmac_key_ids},
                'public-trust bridge vector pins trusted selector ids';
            is_deeply $vector->{trusted_hmac_key_statuses},
                $expected->{trusted_hmac_key_statuses},
                'public-trust bridge vector pins selector lifecycle status';
        }

        my $listing_path = File::Spec->rel2abs($vector->{input_fixture}, $repo_root);
        my $case_dir     = dirname(dirname($listing_path));
        my $game_path    = File::Spec->catfile($case_dir, 'game.name');

        my $game = _read_single($game_path);
        is $game, $vector->{game_descriptor}, 'vector game descriptor matches fixture';

        my @fixture_names = _read_names($listing_path);
        is_deeply $vector->{input_names}, \@fixture_names,
            'self-contained input names match listing fixture';
        is scalar(@{ $vector->{input_names} }), $vector->{raw_count},
            'self-contained input names match raw count';
        unlike encode_json($vector), qr/\Qgobanftp signed hmac fixture key 1\E/,
            'vector keeps HMAC secret out of public evidence';

        my @raw = @{ $vector->{input_names} };
        my @attestations = _read_jsonl(
            File::Spec->rel2abs($vector->{attestation_fixture}, $repo_root),
        );
        is scalar(@attestations), $vector->{attestation_count},
            'attestation count matches fixture';
        _assert_public_trust_artifacts($vector, $repo_root);

        my %public_trusted = map { $_ => 1 }
            @{ $vector->{public_trust_summary}{trusted_key_ids} // [] };
        my %trusted_keys;
        for my $key_id (@{ $vector->{trusted_hmac_key_ids} }) {
            if (exists $trusted_hmac_keys{$key_id}) {
                $trusted_keys{$key_id} = $trusted_hmac_keys{$key_id};
                next;
            }

            ok $public_trusted{$key_id},
                'public k1 selector is bound by public trust summary';
            $trusted_keys{$key_id} = $trusted_hmac_keys{'fixture-key-1'};
        }

        my $witness = witness_for_listing(
            profile_id              => $vector->{profile_id},
            game_descriptor         => $game,
            raw_names               => \@raw,
            diagnostics_schema_path => $schema_path,
            hmac_attestations       => \@attestations,
            trusted_hmac_keys       => \%trusted_keys,
            trusted_hmac_key_statuses => $vector->{trusted_hmac_key_statuses},
            include_projection_text => 1,
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

for my $case (qw(valid injected-event missing-signature wrong-signature payload-mismatch game-descriptor-mismatch untrusted-key-id malformed-signature)) {
    ok $seen_id{"signed-hmac-$case"}, "$case signed-HMAC vector is present";
}

for my $status (qw(trusted rotated revoked expired)) {
    ok $seen_id{"signed-hmac-lifecycle-$status"}, "$status signed-HMAC lifecycle vector is present";
}

for my $case (qw(public-trust-bridge-k1-rejected public-trust-bridge-hmac-trusted)) {
    ok $seen_id{"signed-hmac-$case"}, "$case signed-HMAC public-trust bridge vector is present";
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

sub _read_text {
    my ($path) = @_;

    open my $fh, '<:encoding(UTF-8)', $path or die "open $path: $!";
    local $/;
    my $text = <$fh>;
    close $fh or die "close $path: $!";

    return $text // '';
}

sub _assert_public_trust_artifacts {
    my ($vector, $repo_root) = @_;

    return if !exists $vector->{public_trust_artifacts};

    ok exists($vector->{public_trust_summary}), 'vector has public trust summary';

    my $artifacts = $vector->{public_trust_artifacts};
    ok ref($artifacts) eq 'ARRAY', 'public trust artifacts are an array';
    return if ref($artifacts) ne 'ARRAY';
    ok @$artifacts, 'public trust artifacts has rows';

    my $fixture_root = abs_path(File::Spec->rel2abs('t/fixtures/v1/signed-hmac', $repo_root));
    ok defined($fixture_root) && -d $fixture_root, 'signed-HMAC fixture root exists';

    my (@public_keys, $trust_tsv);
    for my $artifact (@$artifacts) {
        ok ref($artifact) eq 'HASH', 'public trust artifact is an object';
        next if ref($artifact) ne 'HASH';

        for my $field (qw(input_fixture input_text)) {
            ok exists($artifact->{$field}), "public trust artifact has $field";
        }

        my $path = $artifact->{input_fixture} // '';
        ok $path ne '', 'public trust artifact path is nonempty';
        ok !File::Spec->file_name_is_absolute($path),
            'public trust artifact path is relative';
        unlike $path, qr{(?:\A|/)\.\.(?:/|\z)},
            'public trust artifact path does not escape upward';
        like $path, qr{\At/fixtures/v1/signed-hmac/},
            'public trust artifact path stays in signed-HMAC fixtures';

        my $abs = File::Spec->rel2abs($path, $repo_root);
        my $real = -e $abs ? abs_path($abs) : undef;
        ok defined($real) && -f $real, "public trust artifact exists: $path";
        if (defined $real && defined $fixture_root) {
            ok index($real, "$fixture_root/") == 0,
                'public trust artifact resolves under signed-HMAC fixtures';
        }
        next if !defined($real) || !-f $real;

        my $actual_text = _read_text($real);
        is $artifact->{input_text}, $actual_text,
            "public trust artifact embeds exact fixture text: $path";

        if ($path =~ m{/keys/[^/]+[.]pub\z}) {
            push @public_keys, parse_public_key_record($artifact->{input_text});
        }
        elsif ($path =~ m{/trust[.]tsv\z}) {
            $trust_tsv = $artifact->{input_text};
        }
    }

    ok @public_keys, 'public trust artifacts include public key records';
    ok defined($trust_tsv), 'public trust artifacts include trust TSV';

    my $summary = trust_report_summary(
        public_keys => \@public_keys,
        trust_tsv   => $trust_tsv,
    );
    is_deeply $vector->{public_trust_summary}, $summary,
        'public trust summary matches public trust artifacts';
}
