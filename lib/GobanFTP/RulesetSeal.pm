package GobanFTP::RulesetSeal;

use v5.34;
use strict;
use warnings;

use Carp qw(croak);
use Digest::SHA qw(sha256_hex);
use Exporter qw(import);

our @EXPORT_OK = qw(
    ruleset_fixture_digest
    ruleset_fixture_digests
    ruleset_fixture_manifest
    ruleset_seal
    ruleset_seal_preimage
    ruleset_seal_record
);

my $RULESET_ID             = 'chinese-area-v1';
my $RULESET_SEMVER         = '1.0.0';
my $RULESET_SEAL_VERSION   = 'GOFTP-RULESET-SEAL/1';
my $FIXTURE_DIGEST_VERSION = 'GOFTP-RULESET-FIXTURES/1';

my @RULESET_FACTS = (
    'ruleset_id=chinese-area-v1',
    'ruleset_semver=1.0.0',
    'board_size_domain=game_descriptor.size',
    'coordinate_grammar=sgf-aa-to-zz-row-major',
    'move_actions=play-<point>,pass,resign',
    'black_moves_first=1',
    'suicide=illegal',
    'capture_algorithm=full-flood-fill-row-major-captures',
    'ko_rule=positional-superko-on-play',
    'pass_rule=no-superko-check;two-consecutive-passes-terminal',
    'resign_rule=terminal-immediate',
    'scoring=deferred-result-event',
    'state_hash=GOFTP-BOARD/1\\0 || board_size_decimal || \\0 || row_major_point_bytes',
    'engine_authority=perl-reference;inline-c-equivalent-only',
);

my @FIXTURE_DIGESTS = (
    [
        't/fixtures/rules/play-cases.jsonl',
        '15ad4be6bcc27982aee372949b837ca36ef34136b510f2cc3529597ecbef2dc1',
    ],
    [
        't/fixtures/rules/mechanics-boundary.jsonl',
        '59658a5419fb17b45552b628e88a2d496638b75b3cdc88556955071c87df62eb',
    ],
    [
        't/fixtures/rules/ko.json',
        'e4201211eebedd00158ecbf087a22fda9a72a85d546d66f432823fe3c55f319b',
    ],
);

sub ruleset_seal_record {
    my ($ruleset_id) = @_;
    $ruleset_id //= $RULESET_ID;
    _assert_supported($ruleset_id);

    return {
        ruleset_id             => $RULESET_ID,
        ruleset_semver         => $RULESET_SEMVER,
        ruleset_seal_version   => $RULESET_SEAL_VERSION,
        ruleset_fixture_digest => ruleset_fixture_digest($ruleset_id),
        ruleset_seal           => ruleset_seal($ruleset_id),
    };
}

sub ruleset_seal {
    my ($ruleset_id) = @_;
    return sha256_hex(ruleset_seal_preimage($ruleset_id));
}

sub ruleset_seal_preimage {
    my ($ruleset_id) = @_;
    $ruleset_id //= $RULESET_ID;
    _assert_supported($ruleset_id);

    return join(
        "\0",
        $RULESET_SEAL_VERSION,
        @RULESET_FACTS,
        'fixture_digest=' . ruleset_fixture_digest($ruleset_id),
        (map { 'fixture:' . $_->[0] . '=' . $_->[1] } @FIXTURE_DIGESTS),
        '',
    );
}

sub ruleset_fixture_digest {
    my ($ruleset_id) = @_;
    return sha256_hex(ruleset_fixture_manifest($ruleset_id));
}

sub ruleset_fixture_manifest {
    my ($ruleset_id) = @_;
    $ruleset_id //= $RULESET_ID;
    _assert_supported($ruleset_id);

    return join(
        "\0",
        $FIXTURE_DIGEST_VERSION,
        (map { $_->[0] . '=' . $_->[1] } @FIXTURE_DIGESTS),
        '',
    );
}

sub ruleset_fixture_digests {
    my ($ruleset_id) = @_;
    $ruleset_id //= $RULESET_ID;
    _assert_supported($ruleset_id);

    return map { ($_->[0] => $_->[1]) } @FIXTURE_DIGESTS;
}

sub _assert_supported {
    my ($ruleset_id) = @_;
    croak "unsupported ruleset: $ruleset_id"
        if !defined($ruleset_id) || $ruleset_id ne $RULESET_ID;
}

1;

__END__

=head1 NAME

GobanFTP::RulesetSeal - sealed chinese-area-v1 ruleset witness facts

=cut
