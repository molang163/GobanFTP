use v5.34;
use strict;
use warnings;

use FindBin;
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::Auth::PublishToken qw(
    publish_authorization_result
    publish_token_preimage
    sign_publish_token
    verify_publish_token
);

my $game = 'g1.id-replay.s3.r-chinese-area-v1.k0.pb-alice.pw-bob';
my $event = 'm1.p000001.b.play-aa.pa-genesis.by-alice.n-chain1.h-khjclcui7pejbv3m';
my $other_event =
    'm1.p000002.w.play-bb.pa-khjclcui7pejbv3m.by-bob.n-chain2.h-bihb3re4k9hlucat';
my $key_id = 'fixture-key-1';
my $key = 'gobanftp signed hmac fixture key 1';

subtest 'publish tokens bind purpose, game, event, event id, and key selector' => sub {
    my $token = sign_publish_token(
        profile         => 'signed-hmac-goftp1',
        game_descriptor => $game,
        event_basename  => $event,
        key_id          => $key_id,
        key             => $key,
    );

    is $token->{version}, 'GOFTP-HMAC-PUBLISH/1', 'token has publish version';
    is $token->{purpose}, 'publish', 'token has publish purpose';
    is $token->{profile}, 'signed-hmac-goftp1', 'token binds signed profile';
    is $token->{algorithm}, 'hmac-sha256', 'token binds HMAC algorithm';
    is $token->{game_descriptor}, $game, 'token binds game';
    is $token->{event_basename}, $event, 'token binds event basename';
    is $token->{event_id}, 'khjclcui7pejbv3m', 'token binds visible event id';
    is $token->{key_id}, $key_id, 'token carries public selector';
    like $token->{signature}, qr/\A[0-9a-f]{64}\z/, 'token has hex HMAC';
    is $token->{mac}, $token->{signature}, 'mac alias matches signature';
    is $token->{signature_hex}, $token->{signature}, 'signature_hex alias matches';

    my $preimage = publish_token_preimage(
        profile         => 'signed-hmac-goftp1',
        game_descriptor => $game,
        event_basename  => $event,
        key_id          => $key_id,
    );
    is $preimage, join("\0",
        'GOFTP-HMAC-PUBLISH/1',
        'profile=signed-hmac-goftp1',
        'purpose=publish',
        'alg=hmac-sha256',
        "key_id=$key_id",
        "game=$game",
        'event_id=khjclcui7pejbv3m',
        "event=$event",
        '',
    ), 'preimage framing is stable';

    my $verified = verify_publish_token(
        profile         => 'signed-hmac-goftp1',
        game_descriptor => $game,
        event_basename  => $event,
        event_id        => 'khjclcui7pejbv3m',
        key_id          => $key_id,
        key             => $key,
        signature       => $token,
    );
    is $verified->{ok}, 1, 'valid publish token verifies';

    my $wrong_event = verify_publish_token(
        profile         => 'signed-hmac-goftp1',
        game_descriptor => $game,
        event_basename  => $other_event,
        key_id          => $key_id,
        key             => $key,
        signature       => $token,
    );
    is $wrong_event->{ok}, 0, 'token cannot be replayed for another event';
    is $wrong_event->{error}, 'event_basename.mismatch', 'wrong event has stable error';
};

subtest 'publish authorization accepts only trusted lifecycle status for new material' => sub {
    my $token = sign_publish_token(
        profile         => 'signed-hmac-goftp1',
        game_descriptor => $game,
        event_basename  => $event,
        key_id          => $key_id,
        key             => $key,
    );

    my %keys = ($key_id => $key);
    my %expected = (
        trusted => [1, undef],
        rotated => [0, 'key.rotated'],
        revoked => [0, 'key.revoked'],
        expired => [0, 'key.expired'],
    );

    for my $status (sort keys %expected) {
        my $result = publish_authorization_result(
            profile_id                => 'signed-hmac-goftp1',
            game_descriptor           => $game,
            event_basename            => $event,
            token                     => $token,
            trusted_hmac_keys         => \%keys,
            trusted_hmac_key_statuses => { $key_id => $status },
        );

        my ($authorized, $reason) = @{ $expected{$status} };
        is $result->{authorized}, $authorized, "$status authorization flag";
        is $result->{status}, $authorized ? 'authorized' : 'denied', "$status status";
        if ($authorized) {
            is_deeply $result->{diagnostics}, [], "$status emits no diagnostics";
        }
        else {
            is $result->{diagnostics}[0]{code}, 'untrusted_signature',
                "$status emits trust diagnostic";
            is $result->{diagnostics}[0]{reason}, $reason, "$status reason";
        }
    }
};

subtest 'publish authorization rejects untrusted selectors and public-key namespace selectors' => sub {
    my $token = sign_publish_token(
        profile         => 'signed-hmac-goftp1',
        game_descriptor => $game,
        event_basename  => $event,
        key_id          => $key_id,
        key             => $key,
    );

    my $untrusted = publish_authorization_result(
        profile_id        => 'signed-hmac-goftp1',
        game_descriptor   => $game,
        event_basename    => $event,
        token             => $token,
        trusted_hmac_keys => {},
    );
    is $untrusted->{authorized}, 0, 'untrusted key is denied';
    is $untrusted->{diagnostics}[0]{reason}, 'key.untrusted', 'untrusted reason is stable';

    my $public_key_id = 'k1.jk4bs0r77srdlpds260hka9fpp49clpg';
    my $public_token = {
        %$token,
        key_id => $public_key_id,
    };
    my $public = publish_authorization_result(
        profile_id        => 'signed-hmac-goftp1',
        game_descriptor   => $game,
        event_basename    => $event,
        token             => $public_token,
        trusted_hmac_keys => { $public_key_id => $key },
    );
    is $public->{authorized}, 0, 'k1 public-key namespace cannot authorize HMAC publish';
    is $public->{diagnostics}[0]{reason}, 'key_id.public_key_namespace',
        'public namespace reason is stable';
};

done_testing;
