use v5.34;
use strict;
use warnings;

use FindBin;
use File::Basename qw(basename);
use File::Spec;
use Digest::SHA qw(sha256_hex);
use JSON::PP qw(decode_json);
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::RulesetSeal qw(
    ruleset_fixture_digest
    ruleset_fixture_digests
    ruleset_fixture_manifest
    ruleset_seal
    ruleset_seal_preimage
    ruleset_seal_record
);

my $repo_root   = File::Spec->rel2abs("$FindBin::Bin/..");
my $vector_path = "$FindBin::Bin/fixtures/vectors/ruleset-seal.jsonl";
my $vector      = _read_single_jsonl($vector_path);

subtest 'chinese-area-v1 seal matches golden vector' => sub {
    my $record = ruleset_seal_record('chinese-area-v1');

    is $record->{ruleset_id}, 'chinese-area-v1', 'records ruleset id';
    is $record->{ruleset_semver}, '1.0.0', 'records semantic version';
    is $record->{ruleset_seal_version}, 'GOFTP-RULESET-SEAL/1',
        'records seal version';
    like $record->{ruleset_fixture_digest}, qr/\A[0-9a-f]{64}\z/,
        'fixture digest is lowercase SHA-256 hex';
    like $record->{ruleset_seal}, qr/\A[0-9a-f]{64}\z/,
        'ruleset seal is lowercase SHA-256 hex';

    for my $field (qw(
        ruleset_id
        ruleset_semver
        ruleset_seal_version
        ruleset_fixture_digest
        ruleset_seal
    )) {
        is $record->{$field}, $vector->{$field}, "$field matches vector";
    }

    is ruleset_fixture_digest('chinese-area-v1'), $vector->{ruleset_fixture_digest},
        'fixture digest helper matches vector';
    is ruleset_seal('chinese-area-v1'), $vector->{ruleset_seal},
        'seal helper matches vector';
    is unpack('H*', ruleset_fixture_manifest('chinese-area-v1')), $vector->{fixture_manifest_hex},
        'fixture manifest bytes match vector';
    is unpack('H*', ruleset_seal_preimage('chinese-area-v1')), $vector->{preimage_hex},
        'seal preimage bytes match vector';
};

subtest 'fixture manifest pins the current rules fixtures' => sub {
    my %digests = ruleset_fixture_digests('chinese-area-v1');
    is_deeply \%digests, $vector->{fixture_digests}, 'manifest digests match vector';

    my @actual = map {
        't/fixtures/rules/' . basename($_)
    } sort glob(File::Spec->catfile($repo_root, 't', 'fixtures', 'rules', '*'));

    is_deeply [sort keys %digests], \@actual, 'manifest includes every current rules fixture';

    for my $path (@actual) {
        my $bytes = _slurp_bytes(File::Spec->catfile($repo_root, $path));
        is sha256_hex($bytes), $digests{$path}, "$path byte digest matches manifest";
    }
};

subtest 'seal is independent of rule engine environment' => sub {
    my $expected = $vector->{ruleset_seal};
    for my $engine (qw(perl auto c shadow)) {
        local $ENV{GOBANFTP_RULES_ENGINE} = $engine;
        is ruleset_seal('chinese-area-v1'), $expected, "$engine engine env does not change seal";
    }
};

subtest 'unsupported rulesets fail explicitly' => sub {
    my $error = '';
    eval { ruleset_seal_record('made-up'); 1 } or $error = $@;
    like $error, qr/unsupported ruleset: made-up/, 'unsupported ruleset is rejected';
};

done_testing;

sub _read_single_jsonl {
    my ($path) = @_;

    open my $fh, '<:encoding(UTF-8)', $path or die "open $path: $!";
    my @rows;
    while (my $line = <$fh>) {
        chomp $line;
        next if $line =~ /\A\s*\z/;
        push @rows, decode_json($line);
    }
    close $fh or die "close $path: $!";

    die "$path must contain exactly one JSON row" if @rows != 1;
    return $rows[0];
}

sub _slurp_bytes {
    my ($path) = @_;

    open my $fh, '<:raw', $path or die "open $path: $!";
    local $/;
    my $bytes = <$fh>;
    close $fh or die "close $path: $!";

    return $bytes;
}
