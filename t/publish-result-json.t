use v5.34;
use strict;
use warnings;

use FindBin;
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use JSON::PP qw(decode_json);
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::Auth::HMACKey qw(generate_hmac_key_record write_hmac_key_file);
use GobanFTP::Auth::PublishToken qw(sign_publish_token);
use GobanFTP::CLI;
use GobanFTP::MovePublisher qw(build_move_name);

my $GAME = 'g1.id-publishjson.s9.r-chinese-area-v1.k7500.pb-alice.pw-bob';

subtest 'publish-move --json reports scoped publish state' => sub {
    my (undef, $game_root) = _make_game_root();

    my ($exit, $stdout, $stderr) = _run_cli(
        'publish-move',
        '--json',
        '--nonce',
        'json1',
        $game_root,
        'aa',
    );
    is $exit, 0, 'publish-move --json exits success';
    is $stderr, '', 'publish-move --json has no diagnostics';

    my $doc = decode_json($stdout);
    is $doc->{schema}, 'gobanftp.publish.result.v1', 'publish JSON has scoped schema';
    is $doc->{version}, '1.1', 'publish JSON has version 1.1';
    is $doc->{command}, 'publish-move', 'publish JSON records the command';
    is $doc->{status}, 'ok', 'publish JSON records status';
    is $doc->{stage}, 'published', 'publish JSON records stage';
    is $doc->{store_mode}, 'local', 'publish JSON records store mode';
    is $doc->{capabilities}{can_publish}, 1, 'publish JSON includes store capability';
    is $doc->{publish_state}{candidate_built}, 1, 'publish state says candidate was built';
    is $doc->{publish_state}{candidate_replay}, 'ok', 'publish state says candidate replay passed';
    is $doc->{publish_state}{auth_preflight}, 'not_requested', 'auth preflight is explicit';
    is $doc->{publish_state}{store_write}, 'attempted', 'store write state is explicit';
    is $doc->{publish_state}{visibility}, 'confirmed', 'post-publish visibility is confirmed';
    is $doc->{publish_state}{post_publish_replay}, 'ok', 'post-publish replay status is explicit';
    is $doc->{event_set}{available}, 1, 'event set is available after publish';
    is $doc->{event_set}{count}, 1, 'event set count is reported';
    is $doc->{publish_auth}{enabled}, 0, 'publish auth disabled is explicit';
    is $doc->{publish_auth}{scope}, 'fixture-preflight', 'publish auth scope is stable';

    ok -f File::Spec->catfile($game_root, 'events', $doc->{event}), 'event file was created';
    unlike $stdout, qr/secret|password|token/i, 'publish JSON does not contain credential-looking words';
};

subtest 'publish-ack --json reports candidate validation without event-set root' => sub {
    my (undef, $game_root) = _make_game_root();
    my ($move, $move_id) = build_move_name(
        game_descriptor => $GAME,
        ply             => 1,
        color           => 'b',
        action          => 'play-aa',
        parent_id       => 'genesis',
        player          => 'alice',
        nonce           => 'root',
    );
    _write_text(File::Spec->catfile($game_root, 'events', $move), '');

    my ($exit, $stdout, $stderr) = _run_cli(
        'publish-ack',
        '--json',
        '--nonce',
        'bad',
        $game_root,
        '0000000000000000',
    );
    is $exit, 2, 'invalid ack target exits validation';
    is $stderr, '', 'publish JSON keeps diagnostics in stdout JSON';
    my $doc = decode_json($stdout);

    is $doc->{schema}, 'gobanftp.publish.result.v1', 'ack JSON has scoped schema';
    is $doc->{command}, 'publish-ack', 'ack JSON records command';
    is $doc->{stage}, 'candidate', 'ack JSON records candidate stage';
    is $doc->{event_set}{available}, 0, 'candidate JSON suppresses post-publish event-set root';
    is $doc->{publish_state}{store_write}, 'not_attempted', 'candidate JSON says no store write was attempted';
    is $doc->{diagnostics}[0]{code}, 'ack_target_invalid', 'ack diagnostic is structured in JSON';
    is_deeply [_event_names($game_root)], [$move], 'invalid ack writes no event';

    note "root move id was $move_id";
};

subtest 'publish-move --json reports enabled authorized auth preflight' => sub {
    my ($root, $game_root) = _make_game_root();
    my ($key_path, $key) = _write_key($root);
    my $secret = $key->{secret};
    my $secret_hex = $key->{secret_hex};
    my ($event, $event_id) = _move(nonce => 'authok');
    my $token_path = _write_token($root, 'authorized-token.jsonl', _token($key, $event, $event_id));

    my ($exit, $stdout, $stderr) = _run_cli(
        'publish-move',
        '--json',
        '--nonce', 'authok',
        '--publish-auth-token', $token_path,
        '--publish-auth-trusted-hmac-key-file', $key_path,
        $game_root,
        'aa',
    );
    is $exit, 0, 'authorized publish exits success';
    is $stderr, '', 'authorized publish has no diagnostics';

    my $doc = decode_json($stdout);
    is $doc->{stage}, 'published', 'authorized publish reaches published stage';
    is $doc->{publish_state}{auth_preflight}, 'authorized', 'publish state records authorized preflight';
    is $doc->{publish_state}{store_write}, 'attempted', 'authorized publish attempts store write';
    is $doc->{event}, $event, 'authorized publish reports the authorized event';
    is $doc->{event_id}, $event_id, 'authorized publish reports the authorized event id';
    is $doc->{publish_auth}{enabled}, 1, 'publish auth is enabled in JSON';
    is $doc->{publish_auth}{authorized}, 1, 'publish auth JSON reports authorized';
    is $doc->{publish_auth}{status}, 'authorized', 'publish auth JSON has authorized status';
    is $doc->{publish_auth}{diagnostic_count}, 0, 'authorized auth has no diagnostics';
    is_deeply $doc->{publish_auth}{diagnostic_codes}, [], 'authorized auth has no diagnostic codes';
    ok -f File::Spec->catfile($game_root, 'events', $event), 'authorized publish writes the event';
    unlike $stdout . $stderr, qr/\Q$secret_hex\E/, 'authorized JSON does not leak exact HMAC secret hex';
    unlike $stdout . $stderr, qr/\Q$secret\E/, 'authorized JSON does not leak exact HMAC secret bytes';
    unlike $stdout . $stderr, qr/secret_hex|GOFTP-HMAC-KEY/, 'authorized JSON does not leak key-file fields or marker';
};

subtest 'publish-move --json reports denied auth without writing event' => sub {
    my ($root, $game_root) = _make_game_root();
    my ($key_path, $key) = _write_key($root);
    my $secret = $key->{secret};
    my $secret_hex = $key->{secret_hex};
    my ($event, $event_id) = _move(nonce => 'authno');
    my $token_path = _write_token($root, 'denied-token.jsonl', _token($key, $event, $event_id));

    my ($exit, $stdout, $stderr) = _run_cli(
        'publish-move',
        '--json',
        '--nonce', 'authno',
        '--publish-auth-token', $token_path,
        '--publish-auth-trusted-hmac-key-file', $key_path,
        '--publish-auth-trusted-hmac-status', "$key->{key_id}=rotated",
        $game_root,
        'aa',
    );
    is $exit, 2, 'denied publish exits validation';
    is $stderr, '', 'denied publish keeps diagnostics in stdout JSON';

    my $doc = decode_json($stdout);
    is $doc->{schema}, 'gobanftp.publish.result.v1', 'denied publish JSON has scoped schema';
    is $doc->{version}, '1.1', 'denied publish JSON has version 1.1';
    is $doc->{status}, 'failed', 'denied publish reports failed status';
    is $doc->{stage}, 'auth', 'denied publish stops at auth stage';
    is $doc->{publish_state}{auth_preflight}, 'denied', 'publish state records denied preflight';
    is $doc->{publish_state}{store_write}, 'not_attempted', 'denied publish does not attempt store write';
    is $doc->{event}, $event, 'denied publish reports the candidate event';
    is $doc->{event_id}, $event_id, 'denied publish reports the candidate event id';
    is $doc->{event_set}{available}, 0, 'denied publish suppresses post-publish event set';
    is $doc->{publish_auth}{enabled}, 1, 'publish auth is enabled in denied JSON';
    is $doc->{publish_auth}{authorized}, 0, 'publish auth JSON reports denied authorization';
    is $doc->{publish_auth}{status}, 'denied', 'publish auth JSON has denied status';
    is $doc->{publish_auth}{diagnostic_count}, 1, 'denied auth has one diagnostic';
    is_deeply $doc->{publish_auth}{diagnostic_codes}, ['untrusted_signature'],
        'denied auth exposes stable diagnostic code';
    is $doc->{diagnostics}[0]{code}, 'untrusted_signature', 'top-level diagnostics expose stable auth code';
    is_deeply [_event_names($game_root)], [], 'denied publish writes no event';
    unlike $stdout . $stderr, qr/\Q$secret_hex\E/, 'denied JSON does not leak exact HMAC secret hex';
    unlike $stdout . $stderr, qr/\Q$secret\E/, 'denied JSON does not leak exact HMAC secret bytes';
    unlike $stdout . $stderr, qr/secret_hex|GOFTP-HMAC-KEY/, 'denied JSON does not leak key-file fields or marker';
};

done_testing;

sub _make_game_root {
    my $root = tempdir(CLEANUP => 1);
    my $game_root = File::Spec->catdir($root, $GAME);
    make_path(File::Spec->catdir($game_root, 'events'));
    make_path(File::Spec->catdir($game_root, 'tmp'));
    make_path(File::Spec->catdir($game_root, 'sidecar'));

    return ($root, $game_root);
}

sub _run_cli {
    my (@args) = @_;

    my ($stdout, $stderr) = ('', '');
    open my $out_fh, '>', \$stdout or die "open stdout scalar: $!";
    open my $err_fh, '>', \$stderr or die "open stderr scalar: $!";

    my $exit;
    {
        local *STDOUT = $out_fh;
        local *STDERR = $err_fh;
        $exit = GobanFTP::CLI->run(@args);
    }

    return ($exit, $stdout, $stderr);
}

sub _write_key {
    my ($root) = @_;

    my $key = generate_hmac_key_record(secret => ('j' x 32));
    my $path = File::Spec->catfile($root, 'player.hmac-key');
    write_hmac_key_file($path, $key);

    return ($path, $key);
}

sub _move {
    my (%args) = @_;

    return build_move_name(
        game_descriptor => $GAME,
        ply             => 1,
        color           => 'b',
        action          => 'play-aa',
        parent_id       => 'genesis',
        player          => 'alice',
        nonce           => $args{nonce},
    );
}

sub _token {
    my ($key, $event, $event_id) = @_;

    return sign_publish_token(
        profile         => 'signed-hmac-goftp1',
        game_descriptor => $GAME,
        event_basename  => $event,
        event_id        => $event_id,
        key_id          => $key->{key_id},
        key             => $key->{secret},
    );
}

sub _write_token {
    my ($root, $name, $token) = @_;

    my $path = File::Spec->catfile($root, $name);
    open my $fh, '>:encoding(UTF-8)', $path or die "write $path: $!";
    print {$fh} JSON::PP->new->canonical(1)->encode($token), "\n";
    close $fh or die "close $path: $!";

    return $path;
}

sub _event_names {
    my ($game_root) = @_;

    my $dir = File::Spec->catdir($game_root, 'events');
    opendir my $dh, $dir or die "opendir $dir: $!";
    my @names = sort grep { $_ ne '.' && $_ ne '..' } readdir $dh;
    closedir $dh or die "closedir $dir: $!";

    return @names;
}

sub _write_text {
    my ($path, $text) = @_;

    open my $fh, '>:encoding(UTF-8)', $path or die "write $path: $!";
    print {$fh} $text;
    close $fh or die "close $path: $!";
}
