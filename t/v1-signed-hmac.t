use v5.34;
use strict;
use warnings;

use FindBin;
use File::Spec;
use JSON::PP qw(decode_json);
use Test::More;

use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/lib";

use GobanFTP::Test::WitnessHarness qw(witness_for_listing);

my $fixture_dir = "$FindBin::Bin/fixtures/v1/signed-hmac";
my $schema_path = "$FindBin::Bin/../docs/DIAGNOSTICS.md";

my %trusted_hmac_keys = (
    'fixture-key-1' => 'gobanftp signed hmac fixture key 1',
);

my @minimal_events = qw(
    m1.p000001.b.play-aa.pa-genesis.by-alice.n-chain1.h-khjclcui7pejbv3m
    m1.p000002.w.play-bb.pa-khjclcui7pejbv3m.by-bob.n-chain2.h-bihb3re4k9hlucat
    m1.p000003.b.pass.pa-bihb3re4k9hlucat.by-alice.n-chain3.h-kcvtlonfje163p9q
);

my $minimal_root = '599c00f0614e400274a92ab1c96d09087a53d0d88bd8b0ecba481ac60a1f1461';
my $empty_root   = 'c8bdfd7e8dc55bdef0a4571923d9ae370c876aa106ad666d125f8151dc05185d';

subtest 'signed-hmac-goftp1 accepts only valid HMAC-attested events' => sub {
    my ($witness, $attestations) = _witness_for_case('valid', 'signed-hmac-goftp1');

    is $witness->{profile_id}, 'signed-hmac-goftp1', 'records signed profile id';
    is $witness->{normalized_count}, 3, 'normalizes three candidate events';
    is $witness->{accepted_count}, 3, 'accepts all valid signed events';
    is_deeply $witness->{accepted_events}, \@minimal_events, 'accepted events are the signed event set';
    is $witness->{rejected_count}, 0, 'does not reject valid signatures';
    is_deeply $witness->{rejected_codes}, [], 'no rejected signature codes';
    is_deeply $witness->{rejected_classes}, [], 'no rejected signature classes';
    is $witness->{event_set_root}, $minimal_root, 'signed accepted set keeps the GOFTP/1 root';
    is $witness->{replay_status}, 'ok', 'signed accepted events replay';
    is $witness->{canonical_tip}, 'kcvtlonfje163p9q', 'canonical tip comes from signed events';
    is_deeply $witness->{diagnostic_classes}, [], 'no replay diagnostics';
    _assert_every_accepted_event_has_attestation($witness, $attestations);
};

my @negative_cases = (
    ['missing-signature', 'missing_signature'],
    ['wrong-signature', 'wrong_signature'],
    ['untrusted-key-id', 'untrusted_signature'],
    ['malformed-signature', 'malformed_signature'],
);

for my $case (@negative_cases) {
    my ($case_name, $code) = @$case;
    subtest "$case_name rejects with signature class" => sub {
        my ($witness) = _witness_for_case($case_name, 'signed-hmac-goftp1');

        is $witness->{normalized_count}, 1, 'normalizes one candidate event';
        is $witness->{accepted_count}, 0, 'does not accept the unsigned or untrusted event';
        is_deeply $witness->{accepted_events}, [], 'signature failure leaves no accepted events';
        is $witness->{rejected_count}, 1, 'records one rejected event';
        is_deeply $witness->{rejected_codes}, [$code], 'records stable signature diagnostic code';
        is_deeply $witness->{rejected_classes}, ['signature'], 'maps rejection to signature class';
        is $witness->{event_set_root}, $empty_root, 'root is the empty accepted signed set';
        is $witness->{replay_status}, 'ok', 'replay sees no rejected signature event';
        is $witness->{canonical_tip}, 'genesis', 'canonical line remains empty';
        is_deeply $witness->{diagnostic_classes}, [], 'signature diagnostics stay at witness gate';
    };
}

subtest 'unsigned profiles ignore signed-hmac attestations' => sub {
    my @hostile_attestations = _read_jsonl(
        File::Spec->catfile($fixture_dir, 'unsigned-unaffected', 'attestations.jsonl'),
    );

    for my $profile (qw(local-goftp1 ftp-goftp1 git-tree-goftp1 dns-record-goftp1 webdav-goftp1)) {
        my ($witness) = _witness_for_case(
            'unsigned-unaffected',
            $profile,
            hmac_attestations => \@hostile_attestations,
        );

        is $witness->{accepted_count}, 3, "$profile accepts the unsigned GOFTP/1 events";
        is_deeply $witness->{accepted_events}, \@minimal_events, "$profile accepted events unchanged";
        is $witness->{rejected_count}, 0, "$profile has no signature rejection";
        is_deeply $witness->{rejected_classes}, [], "$profile has no rejected signature class";
        is $witness->{event_set_root}, $minimal_root, "$profile root unchanged";
        is $witness->{replay_status}, 'ok', "$profile replay unchanged";
        is $witness->{canonical_tip}, 'kcvtlonfje163p9q', "$profile canonical tip unchanged";
        is_deeply $witness->{diagnostic_classes}, [], "$profile replay diagnostics unchanged";
    }
};

subtest 'duplicate attestations are order-independent' => sub {
    my @valid = _read_jsonl(
        File::Spec->catfile($fixture_dir, 'valid', 'signed-hmac-goftp1', 'attestations.jsonl'),
    );
    my @bad = _read_jsonl(
        File::Spec->catfile($fixture_dir, 'wrong-signature', 'signed-hmac-goftp1', 'attestations.jsonl'),
    );

    my @bad_first   = ($bad[0], @valid);
    my @valid_first = (@valid, $bad[0]);

    for my $case (
        ['bad first',   \@bad_first],
        ['valid first', \@valid_first],
    ) {
        my ($label, $attestations) = @$case;
        my ($witness) = _witness_for_case(
            'valid',
            'signed-hmac-goftp1',
            hmac_attestations => $attestations,
        );

        is $witness->{accepted_count}, 3, "$label: any valid trusted attestation accepts";
        is_deeply $witness->{accepted_events}, \@minimal_events, "$label: accepted events unchanged";
        is $witness->{event_set_root}, $minimal_root, "$label: root unchanged";
        is $witness->{rejected_count}, 0, "$label: failed duplicate does not reject a signed event";
    }
};

done_testing;

sub _witness_for_case {
    my ($case, $profile, %overrides) = @_;

    my $case_dir = File::Spec->catdir($fixture_dir, $case);
    my $game = _read_single(File::Spec->catfile($case_dir, 'game.name'));
    my @raw  = _read_names(File::Spec->catfile($case_dir, $profile, 'listing.names'));

    my @attestations = exists $overrides{hmac_attestations}
        ? @{ $overrides{hmac_attestations} }
        : _read_jsonl(File::Spec->catfile($case_dir, $profile, 'attestations.jsonl'));

    my $witness = witness_for_listing(
        profile_id              => $profile,
        game_descriptor         => $game,
        raw_names               => \@raw,
        diagnostics_schema_path => $schema_path,
        hmac_attestations       => \@attestations,
        trusted_hmac_keys       => \%trusted_hmac_keys,
    );

    return ($witness, \@attestations);
}

sub _assert_every_accepted_event_has_attestation {
    my ($witness, $attestations) = @_;

    my %attested = map { ($_->{event_basename} // $_->{event} // '') => 1 } @$attestations;
    for my $event (@{ $witness->{accepted_events} }) {
        ok $attested{$event}, "$event has a fixture attestation";
    }
}

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
