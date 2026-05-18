use v5.34;
use strict;
use warnings;

use FindBin;
use File::Spec;
use JSON::PP qw(decode_json);
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::Auth::HMAC qw(event_attestation_preimage hmac_sha256_hex);
use GobanFTP::Auth::KeyID qw(parse_public_key_record);
use GobanFTP::Auth::TrustReport qw(trust_report_summary);
use GobanFTP::Witness qw(witness_for_listing);

my $fixture_dir = "$FindBin::Bin/fixtures/v1/signed-hmac";
my $schema_path = "$FindBin::Bin/../docs/DIAGNOSTICS.md";
my $minimal_game = 'g1.id-replay.s3.r-chinese-area-v1.k0.pb-alice.pw-bob';
my $payload_mismatch_game = 'g1.id-other.s3.r-chinese-area-v1.k0.pb-alice.pw-bob';

my %trusted_hmac_keys = (
    'fixture-key-1' => 'gobanftp signed hmac fixture key 1',
);

my @minimal_events = qw(
    m1.p000001.b.play-aa.pa-genesis.by-alice.n-chain1.h-khjclcui7pejbv3m
    m1.p000002.w.play-bb.pa-khjclcui7pejbv3m.by-bob.n-chain2.h-bihb3re4k9hlucat
    m1.p000003.b.pass.pa-bihb3re4k9hlucat.by-alice.n-chain3.h-kcvtlonfje163p9q
);

my $injected_event =
    'm1.p000004.w.play-cc.pa-kcvtlonfje163p9q.by-bob.n-inject1.h-nr55esqpd0ika4bt';

my $minimal_root = '599c00f0614e400274a92ab1c96d09087a53d0d88bd8b0ecba481ac60a1f1461';
my $empty_root   = 'c8bdfd7e8dc55bdef0a4571923d9ae370c876aa106ad666d125f8151dc05185d';
my $public_trusted_key_id = 'k1.jk4bs0r77srdlpds260hka9fpp49clpg';
my $public_revoked_key_id = 'k1.b9qqr423d7t8utun0q6f9nbt9o5jcita';
my $public_expired_key_id = 'k1.8fqoc7krroqkucq5avbaa48qoi7p882a';

subtest 'signed-hmac-goftp1 accepts only valid HMAC-attested events' => sub {
    my ($witness, $attestations) = _witness_for_case('valid', 'signed-hmac-goftp1');

    is $witness->{profile_id}, 'signed-hmac-goftp1', 'records signed profile id';
    is $witness->{profile_consensus_version}, 'GOFTP-PROFILE/signed-hmac-goftp1/1',
        'records signed profile consensus version';
    is $witness->{adapter_id}, 'signed-hmac-listing-goftp1', 'records signed adapter id';
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

subtest 'signed-HMAC rejects an unsigned event injection without changing accepted truth' => sub {
    my ($baseline) = _witness_for_case('valid', 'signed-hmac-goftp1');
    my ($witness)  = _witness_for_case('injected-event', 'signed-hmac-goftp1');

    is $witness->{normalized_count}, 4, 'normalizes the signed chain plus injected event';
    ok grep({ $_ eq $injected_event } @{ $witness->{normalized_events} }),
        'the injected event reaches the signed profile gate';
    is $witness->{accepted_count}, 3, 'accepts only the valid signed chain';
    is_deeply $witness->{accepted_events}, \@minimal_events,
        'accepted events ignore the unsigned injection';
    is_deeply $witness->{accepted_events}, $baseline->{accepted_events},
        'accepted events match valid baseline';
    is $witness->{event_set_root}, $baseline->{event_set_root}, 'event_set_root matches valid baseline';
    is $witness->{canonical_tip}, $baseline->{canonical_tip}, 'canonical tip matches valid baseline';
    is_deeply $witness->{canonical_ids}, $baseline->{canonical_ids},
        'canonical ids match valid baseline';
    is_deeply $witness->{legal_ids}, $baseline->{legal_ids}, 'legal ids match valid baseline';
    is $witness->{board_hash}, $baseline->{board_hash}, 'board hash matches valid baseline';
    is $witness->{sgf_hash}, $baseline->{sgf_hash}, 'SGF hash matches valid baseline';
    is $witness->{variations_sgf_hash}, $baseline->{variations_sgf_hash},
        'variations SGF hash matches valid baseline';
    is $witness->{rejected_count}, 1, 'records the injected event rejection';
    is_deeply $witness->{rejected_codes}, ['missing_signature'],
        'records stable missing-signature code';
    is_deeply $witness->{rejected_classes}, ['signature'],
        'maps injection rejection to signature class';
    is $witness->{rejected_diagnostics}[0]{name}, $injected_event,
        'diagnostic names the injected event';
    is $witness->{rejected_diagnostics}[0]{event_id}, 'nr55esqpd0ika4bt',
        'diagnostic records the injected event id';
    is $witness->{replay_status}, 'ok', 'accepted signed chain still replays';
    is_deeply $witness->{diagnostic_classes}, [], 'replay diagnostics remain clean';
};

my @negative_cases = (
    ['missing-signature', 'missing_signature'],
    ['wrong-signature', 'wrong_signature', 'signature.mismatch'],
    ['payload-mismatch', 'wrong_signature', 'signature.mismatch'],
    ['game-descriptor-mismatch', 'wrong_signature', 'game_descriptor.mismatch'],
    ['untrusted-key-id', 'untrusted_signature'],
    ['malformed-signature', 'malformed_signature'],
);

for my $case (@negative_cases) {
    my ($case_name, $code, $reason) = @$case;
    subtest "$case_name rejects with signature class" => sub {
        my ($witness) = _witness_for_case($case_name, 'signed-hmac-goftp1');

        is $witness->{normalized_count}, 1, 'normalizes one candidate event';
        is $witness->{accepted_count}, 0, 'does not accept the unsigned or untrusted event';
        is_deeply $witness->{accepted_events}, [], 'signature failure leaves no accepted events';
        is $witness->{rejected_count}, 1, 'records one rejected event';
        is_deeply $witness->{rejected_codes}, [$code], 'records stable signature diagnostic code';
        is_deeply $witness->{rejected_classes}, ['signature'], 'maps rejection to signature class';
        is $witness->{rejected_diagnostics}[0]{reason}, $reason, 'records stable rejection reason'
            if defined $reason;
        is $witness->{event_set_root}, $empty_root, 'root is the empty accepted signed set';
        is $witness->{replay_status}, 'ok', 'replay sees no rejected signature event';
        is $witness->{canonical_tip}, 'genesis', 'canonical line remains empty';
        is_deeply $witness->{diagnostic_classes}, [], 'signature diagnostics stay at witness gate';
    };
}

subtest 'payload-mismatch fixture is a real HMAC over another payload' => sub {
    my (undef, $attestations) = _witness_for_case('payload-mismatch', 'signed-hmac-goftp1');
    is scalar(@$attestations), 1, 'fixture has one attestation';

    my $record = $attestations->[0];
    is $record->{game_descriptor}, $minimal_game,
        'public attestation record claims the observed game descriptor';

    my %payload = (
        version         => 'GOFTP-HMAC-EVENT/1',
        profile         => 'signed-hmac-goftp1',
        algorithm       => 'hmac-sha256',
        key_id          => 'fixture-key-1',
        event_basename  => $minimal_events[0],
        event_id        => 'khjclcui7pejbv3m',
    );

    my $wrong_payload_mac = hmac_sha256_hex(
        $trusted_hmac_keys{'fixture-key-1'},
        event_attestation_preimage(%payload, game_descriptor => $payload_mismatch_game),
    );
    my $canonical_mac = hmac_sha256_hex(
        $trusted_hmac_keys{'fixture-key-1'},
        event_attestation_preimage(%payload, game_descriptor => $minimal_game),
    );

    is $record->{signature}, $wrong_payload_mac,
        'fixture signature is a trusted HMAC over the alternate payload';
    is $record->{mac}, $wrong_payload_mac, 'mac alias matches the mismatched payload signature';
    isnt $record->{signature}, $canonical_mac,
        'fixture signature is not the canonical attestation for this game';
};

subtest 'game-descriptor-mismatch fixture is bound to the declared alternate game' => sub {
    my (undef, $attestations) = _witness_for_case('game-descriptor-mismatch', 'signed-hmac-goftp1');
    is scalar(@$attestations), 1, 'fixture has one attestation';

    my $record = $attestations->[0];
    is $record->{game_descriptor}, $payload_mismatch_game,
        'public attestation record declares the alternate game descriptor';

    my %payload = (
        version         => 'GOFTP-HMAC-EVENT/1',
        profile         => 'signed-hmac-goftp1',
        algorithm       => 'hmac-sha256',
        key_id          => 'fixture-key-1',
        event_basename  => $minimal_events[0],
        event_id        => 'khjclcui7pejbv3m',
        game_descriptor => $payload_mismatch_game,
    );
    my $declared_game_mac = hmac_sha256_hex(
        $trusted_hmac_keys{'fixture-key-1'},
        event_attestation_preimage(%payload),
    );

    is $record->{signature}, $declared_game_mac,
        'fixture signature is a trusted HMAC over its declared alternate game';
    is $record->{mac}, $declared_game_mac, 'mac alias matches the declared alternate game signature';
};

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

subtest 'signed-HMAC lifecycle status is enforced by witness assembly only for signed profile' => sub {
    my ($rotated) = _witness_for_case(
        'valid',
        'signed-hmac-goftp1',
        trusted_hmac_key_statuses => { 'fixture-key-1' => 'rotated' },
    );
    is $rotated->{accepted_count}, 3, 'rotated HMAC selector verifies old signed material';
    is $rotated->{event_set_root}, $minimal_root, 'rotated selector keeps the signed root';
    is $rotated->{rejected_count}, 0, 'rotated selector has no gate rejection';

    for my $case (
        [revoked => 'key.revoked'],
        [expired => 'key.expired'],
    ) {
        my ($status, $reason) = @$case;
        my ($witness) = _witness_for_case(
            'valid',
            'signed-hmac-goftp1',
            trusted_hmac_key_statuses => { 'fixture-key-1' => $status },
        );

        is $witness->{accepted_count}, 0, "$status HMAC selector accepts no events";
        is $witness->{event_set_root}, $empty_root, "$status selector roots the empty signed set";
        is_deeply $witness->{rejected_codes}, ['untrusted_signature'],
            "$status selector reports trust rejection";
        is $witness->{rejected_diagnostics}[0]{reason}, $reason,
            "$status selector records lifecycle reason";
    }

    for my $profile (qw(local-goftp1 ftp-goftp1 git-tree-goftp1 dns-record-goftp1 webdav-goftp1)) {
        my ($witness) = _witness_for_case(
            'unsigned-unaffected',
            $profile,
            hmac_attestations => [],
            trusted_hmac_key_statuses => { 'fixture-key-1' => 'revoked' },
        );

        is $witness->{accepted_count}, 3, "$profile ignores revoked HMAC lifecycle input";
        is $witness->{event_set_root}, $minimal_root, "$profile root stays unsigned truth";
        is_deeply $witness->{rejected_classes}, [], "$profile has no signature gate rejection";
    }
};

subtest 'public GOFTP-TRUST rows cannot bridge into signed-HMAC lifecycle' => sub {
    my $case_dir = File::Spec->catdir($fixture_dir, 'public-trust-bridge-poison');
    my @public_keys = map { parse_public_key_record(_read_text($_)) }
        sort glob File::Spec->catfile($case_dir, 'keys', '*.pub');
    my $trust = trust_report_summary(
        public_keys => \@public_keys,
        trust_tsv   => _read_text(File::Spec->catfile($case_dir, 'trust.tsv')),
    );

    is $trust->{status}, 'advisory', 'fixture has public advisory trust rows';
    is_deeply $trust->{trusted_key_ids}, [$public_trusted_key_id],
        'fixture carries a public trusted k1 key';
    is_deeply $trust->{revoked_key_ids}, [$public_revoked_key_id],
        'fixture carries a public revoked k1 key';
    is_deeply $trust->{expired_key_ids}, [$public_expired_key_id],
        'fixture carries a public expired k1 key';

    my @k1_attestations = _read_jsonl(
        File::Spec->catfile($case_dir, 'signed-hmac-goftp1', 'k1-attestations.jsonl'),
    );
    my ($public_key_witness) = _witness_for_case(
        'public-trust-bridge-poison',
        'signed-hmac-goftp1',
        hmac_attestations => \@k1_attestations,
        trusted_hmac_keys => { $public_trusted_key_id => $trusted_hmac_keys{'fixture-key-1'} },
        trusted_hmac_key_statuses => { $public_trusted_key_id => 'trusted' },
    );

    is $public_key_witness->{accepted_count}, 0,
        'public trusted k1 row cannot authorize a signed-HMAC selector';
    is_deeply $public_key_witness->{rejected_codes}, ['untrusted_signature'],
        'k1 selector stays an untrusted signed-HMAC signature';
    is_deeply [
        map { $_->{reason} } @{ $public_key_witness->{rejected_diagnostics} }
    ], [
        ('key_id.public_key_namespace') x 3,
    ], 'public-key namespace is rejected before HMAC verification';
    is $public_key_witness->{event_set_root}, $empty_root,
        'public-key namespace leaves the signed accepted set empty';

    my ($hmac_witness) = _witness_for_case(
        'public-trust-bridge-poison',
        'signed-hmac-goftp1',
        trusted_hmac_key_statuses => { 'fixture-key-1' => 'trusted' },
    );

    is $hmac_witness->{accepted_count}, 3,
        'public revoked or expired k1 rows cannot revoke the explicit HMAC selector';
    is_deeply $hmac_witness->{accepted_events}, \@minimal_events,
        'explicit signed-HMAC trust set still accepts the valid chain';
    is $hmac_witness->{event_set_root}, $minimal_root,
        'public trust poison does not alter the signed accepted root';
    is $hmac_witness->{rejected_count}, 0,
        'public trust poison creates no signed-HMAC rejection';

    my ($unsigned_witness) = _witness_for_case(
        'public-trust-bridge-poison',
        'local-goftp1',
        hmac_attestations => \@k1_attestations,
        trusted_hmac_keys => { $public_trusted_key_id => $trusted_hmac_keys{'fixture-key-1'} },
        trusted_hmac_key_statuses => { $public_trusted_key_id => 'trusted' },
    );

    is $unsigned_witness->{accepted_count}, 3,
        'unsigned local profile ignores public trust bridge poison';
    is_deeply $unsigned_witness->{accepted_events}, \@minimal_events,
        'unsigned local profile keeps the filename-derived chain';
    is $unsigned_witness->{event_set_root}, $minimal_root,
        'unsigned local root is unchanged by public trust material';
    is_deeply $unsigned_witness->{rejected_classes}, [],
        'unsigned local profile has no signature gate rejection';
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
        trusted_hmac_keys       => $overrides{trusted_hmac_keys} // \%trusted_hmac_keys,
        trusted_hmac_key_statuses => $overrides{trusted_hmac_key_statuses} // {},
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

sub _read_text {
    my ($path) = @_;

    open my $fh, '<:encoding(UTF-8)', $path or die "open $path: $!";
    local $/;
    my $text = <$fh>;
    close $fh or die "close $path: $!";

    return $text;
}
