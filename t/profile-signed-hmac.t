use v5.34;
use strict;
use warnings;

use FindBin;
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::Auth::HMAC qw(sign_event);
use GobanFTP::EventSetRoot qw(event_set_root_result);
use GobanFTP::Profile::SignedHMAC qw(is_signed_hmac_profile signed_hmac_event_set_result);

my $game = 'g1.id-replay.s3.r-chinese-area-v1.k0.pb-alice.pw-bob';
my $key_id = 'fixture-key-1';
my $key    = 'gobanftp signed hmac fixture key 1';
my %trusted_hmac_keys = ($key_id => $key);
my $public_key_id = 'k1.jk4bs0r77srdlpds260hka9fpp49clpg';

my @events = qw(
    m1.p000001.b.play-aa.pa-genesis.by-alice.n-chain1.h-khjclcui7pejbv3m
    m1.p000002.w.play-bb.pa-khjclcui7pejbv3m.by-bob.n-chain2.h-bihb3re4k9hlucat
);

ok is_signed_hmac_profile('signed-hmac-goftp1'), 'signed-hmac-goftp1 is the signed HMAC profile';
ok !is_signed_hmac_profile('local-goftp1'), 'local profile is not signed HMAC';

subtest 'valid trusted attestations become the signed accepted set' => sub {
    my @attestations = map { _valid_attestation($_) } @events;
    my $result = _signed_result(\@events, \@attestations);

    is $result->{event_count}, 2, 'accepts both trusted signed events';
    is_deeply $result->{accepted_events}, \@events, 'accepted set is the signed event set';
    is_deeply $result->{diagnostics}, [], 'no signature diagnostics';
};

subtest 'attestation aliases are accepted' => sub {
    my $signature_hex = _valid_attestation($events[0]);
    $signature_hex->{event} = delete $signature_hex->{event_basename};
    $signature_hex->{signature_hex} = delete $signature_hex->{signature};
    delete $signature_hex->{mac};

    my $hex_result = _signed_result([$events[0]], [$signature_hex]);
    is $hex_result->{event_count}, 1, 'event and signature_hex aliases accept';

    my $hmac_sha256 = _valid_attestation($events[0]);
    $hmac_sha256->{hmac_sha256} = delete $hmac_sha256->{signature};
    delete $hmac_sha256->{signature_hex};
    delete $hmac_sha256->{mac};

    my $hmac_result = _signed_result([$events[0]], [$hmac_sha256]);
    is $hmac_result->{event_count}, 1, 'hmac_sha256 alias accepts';
};

subtest 'signature failures are gate diagnostics, not accepted events' => sub {
    my @cases = (
        ['missing',   [],                         'missing_signature'],
        ['untrusted', [_untrusted_attestation()], 'untrusted_signature'],
        ['wrong',     [_wrong_attestation()],     'wrong_signature'],
        ['malformed', [_malformed_attestation()], 'malformed_signature'],
    );

    for my $case (@cases) {
        my ($label, $attestations, $code) = @$case;
        my $result = _signed_result([$events[0]], $attestations);

        is $result->{event_count}, 0, "$label: accepts no event";
        is_deeply $result->{accepted_events}, [], "$label: accepted set is empty";
        is scalar(@{ $result->{diagnostics} }), 1, "$label: one gate diagnostic";
        is $result->{diagnostics}[0]{code}, $code, "$label: diagnostic code";
    }
};

subtest 'duplicate attestations are order-independent' => sub {
    my $valid = _valid_attestation($events[0]);
    my $wrong = _wrong_attestation();

    for my $case (
        ['bad first',   [$wrong, $valid]],
        ['valid first', [$valid, $wrong]],
    ) {
        my ($label, $attestations) = @$case;
        my $result = _signed_result([$events[0]], $attestations);

        is $result->{event_count}, 1, "$label: any valid trusted attestation accepts";
        is_deeply $result->{diagnostics}, [], "$label: failed duplicate is not reported";
    }

    my $untrusted = _untrusted_attestation();
    my $malformed = _malformed_attestation();
    my $result = _signed_result([$events[0]], [$untrusted, $malformed, $wrong]);
    is $result->{event_count}, 0, 'no invalid duplicate accepts';
    is $result->{diagnostics}[0]{code}, 'wrong_signature',
        'diagnostic priority does not depend on duplicate order';
};

subtest 'filename gate diagnostics are preserved before signature checks' => sub {
    my $bad = 'm1.p000001.b.play-aa.pa-genesis.by-alice.n-chain1.h-0000000000000000';
    my $result = _signed_result([$bad], []);

    is $result->{event_count}, 0, 'bad event id cannot enter signed set';
    is scalar(@{ $result->{diagnostics} }), 1, 'only filename gate diagnostic is reported';
    is $result->{diagnostics}[0]{code}, 'parse_event', 'signature gate does not mask parse_event';
};

subtest 'GOFTP-KEY public namespace cannot authorize signed-HMAC' => sub {
    my $attestation = sign_event(
        version         => 'GOFTP-HMAC-EVENT/1',
        profile         => 'signed-hmac-goftp1',
        algorithm       => 'hmac-sha256',
        game_descriptor => $game,
        event_basename  => $events[0],
        key_id          => $public_key_id,
        key             => $key,
    );

    my $result = signed_hmac_event_set_result(
        profile_id        => 'signed-hmac-goftp1',
        game_descriptor   => $game,
        unsigned_result   => _unsigned_result([$events[0]]),
        hmac_attestations => [$attestation],
        trusted_hmac_keys => { $public_key_id => $key },
    );

    is $result->{event_count}, 0, 'does not accept a k1 public-key id as an HMAC selector';
    is_deeply $result->{accepted_events}, [], 'public-key namespace leaves signed set empty';
    is $result->{diagnostics}[0]{code}, 'untrusted_signature',
        'public-key namespace is a trust failure';
    is $result->{diagnostics}[0]{reason}, 'key_id.public_key_namespace',
        'diagnostic names the namespace boundary';
};

like dies(sub {
    signed_hmac_event_set_result(
        profile_id        => 'local-goftp1',
        game_descriptor   => $game,
        unsigned_result   => _unsigned_result([$events[0]]),
        hmac_attestations => [],
        trusted_hmac_keys => \%trusted_hmac_keys,
    );
}), qr/unsupported signed HMAC profile/, 'unsupported profile is rejected';

done_testing;

sub _signed_result {
    my ($events, $attestations) = @_;

    return signed_hmac_event_set_result(
        profile_id        => 'signed-hmac-goftp1',
        game_descriptor   => $game,
        unsigned_result   => _unsigned_result($events),
        hmac_attestations => $attestations,
        trusted_hmac_keys => \%trusted_hmac_keys,
    );
}

sub _unsigned_result {
    my ($events) = @_;
    return event_set_root_result(
        game_descriptor => $game,
        names           => $events,
    );
}

sub _valid_attestation {
    my ($event) = @_;

    return sign_event(
        version         => 'GOFTP-HMAC-EVENT/1',
        profile         => 'signed-hmac-goftp1',
        algorithm       => 'hmac-sha256',
        game_descriptor => $game,
        event_basename  => $event,
        key_id          => $key_id,
        key             => $key,
    );
}

sub _wrong_attestation {
    my $attestation = _valid_attestation($events[0]);
    $attestation->{signature} = '0' x 64;
    $attestation->{mac} = $attestation->{signature};
    $attestation->{signature_hex} = $attestation->{signature};
    return $attestation;
}

sub _untrusted_attestation {
    my $attestation = _valid_attestation($events[0]);
    $attestation->{key_id} = 'fixture-key-untrusted';
    return $attestation;
}

sub _malformed_attestation {
    my $attestation = _valid_attestation($events[0]);
    $attestation->{signature} = 'not-a-hex-signature';
    $attestation->{mac} = $attestation->{signature};
    $attestation->{signature_hex} = $attestation->{signature};
    $attestation->{signature_id} = 'fixture-malformed-signature';
    return $attestation;
}

sub dies {
    my ($code) = @_;
    my $error = '';
    eval { $code->(); 1 } or $error = $@;
    return $error;
}
