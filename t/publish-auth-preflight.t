use v5.34;
use strict;
use warnings;

use FindBin;
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use JSON::PP;
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::AckPublisher qw(build_ack_name);
use GobanFTP::Auth::HMACKey qw(generate_hmac_key_record write_hmac_key_file);
use GobanFTP::Auth::PublishToken qw(sign_publish_token);
use GobanFTP::CLI;
use GobanFTP::MovePublisher qw(build_move_name);

my $GAME = 'g1.id-publishauth.s9.r-chinese-area-v1.k7500.pb-alice.pw-bob';

subtest 'publish auth is default-off for existing publish-move behavior' => sub {
    my ($root, $game_root) = _make_game_root();
    my ($key_path, $key) = _write_key($root);
    my ($event, $event_id) = _move(nonce => 'b1');
    my $toxic_token = _write_token($root, 'toxic.jsonl', _token($key, $event, $event_id));

    local %ENV = %ENV;
    $ENV{GOBANFTP_PUBLISH_AUTH_TOKEN} = $toxic_token;
    $ENV{GOBANFTP_PUBLISH_AUTH_KEY} = $key_path;

    my ($exit, $stdout, $stderr) =
        _run_cli('publish-move', '--nonce', 'b1', $game_root, 'aa');

    is $exit, 0, 'default-off publish-move still succeeds';
    like $stdout, qr/^gobanftp[.]publish-move=ok$/m, 'status stays ok';
    unlike $stdout, qr/^publish_auth[.]/m, 'default-off path prints no auth fields';
    is $stderr, '', 'default-off path emits no diagnostics';
    ok -f File::Spec->catfile($game_root, 'events', $event),
        'default-off path writes the expected event';
};

subtest 'publish-move authorized preflight writes the exact candidate event' => sub {
    my ($root, $game_root) = _make_game_root();
    my ($key_path, $key) = _write_key($root);
    my ($event, $event_id) = _move(nonce => 'b1');
    my $token_path = _write_token($root, 'publish-token.jsonl', _token($key, $event, $event_id));

    my ($exit, $stdout, $stderr) = _run_cli(
        'publish-move',
        '--nonce', 'b1',
        '--publish-auth-token', $token_path,
        '--publish-auth-trusted-hmac-key-file', $key_path,
        $game_root,
        'aa',
    );

    is $exit, 0, 'authorized preflight exits success';
    like $stdout, qr/^gobanftp[.]publish-move=ok$/m, 'publish-move reports ok';
    like $stdout, qr/^event=\Q$event\E$/m, 'reports the pre-authorized event';
    like $stdout, qr/^event_id=\Q$event_id\E$/m, 'reports the pre-authorized id';
    like $stdout, qr/^publish_auth[.]scope=fixture-preflight$/m,
        'prints fixture preflight scope';
    like $stdout, qr/^publish_auth[.]production_authorization=0$/m,
        'prints non-production auth boundary';
    like $stdout, qr/^publish_auth[.]status=authorized$/m, 'prints authorized status';
    like $stdout, qr/^publish_auth[.]key_id=\Q$key->{key_id}\E$/m, 'prints public key selector';
    like $stdout, qr/^publish_auth[.]diagnostic_count=0$/m, 'authorized path has no diagnostics';
    is $stderr, '', 'authorized path emits no diagnostics';
    ok -f File::Spec->catfile($game_root, 'events', $event),
        'authorized preflight writes the event';
    unlike $stdout . $stderr, qr/\Q$key->{secret_hex}\E|GOFTP-HMAC-KEY|secret_hex/,
        'authorized path does not leak key material';
};

subtest 'publish-move denied preflight does not write' => sub {
    my ($root, $game_root) = _make_game_root();
    my ($key_path, $key) = _write_key($root);
    my ($event, $event_id) = _move(nonce => 'b1');
    my $token_path = _write_token($root, 'publish-token.jsonl', _token($key, $event, $event_id));

    my ($exit, $stdout, $stderr) = _run_cli(
        'publish-move',
        '--nonce', 'b1',
        '--publish-auth-token', $token_path,
        '--publish-auth-trusted-hmac-key-file', $key_path,
        '--publish-auth-trusted-hmac-status', "$key->{key_id}=rotated",
        $game_root,
        'aa',
    );

    is $exit, 2, 'rotated publish key exits validation';
    like $stdout, qr/^gobanftp[.]publish-move=failed$/m, 'publish-move reports failed';
    like $stdout, qr/^event=\Q$event\E$/m, 'denied path still reports the candidate event';
    like $stdout, qr/^publish_auth[.]scope=fixture-preflight$/m,
        'denied path prints fixture preflight scope';
    like $stdout, qr/^publish_auth[.]production_authorization=0$/m,
        'denied path prints non-production auth boundary';
    like $stdout, qr/^publish_auth[.]status=denied$/m, 'prints denied status';
    like $stdout, qr/^publish_auth[.]diagnostic_codes=untrusted_signature$/m,
        'stdout exposes stable auth diagnostic code';
    unlike $stdout, qr/^event_set_root=/m, 'denied preflight does not print post-publish root';
    like $stderr, qr/diagnostic .*code=untrusted_signature.*reason=key[.]rotated/,
        'stderr reports lifecycle denial';
    is_deeply [_event_names($game_root)], [], 'denied preflight writes no event';
    unlike $stdout . $stderr, qr/\Q$key->{secret_hex}\E|GOFTP-HMAC-KEY|secret_hex/,
        'denied path does not leak key material';
};

subtest 'candidate replay validation happens before auth material is read' => sub {
    my ($root, $game_root) = _make_game_root();
    my $missing_token = File::Spec->catfile($root, 'missing-token.jsonl');
    my $missing_key = File::Spec->catfile($root, 'missing-key.hmac-key');

    my ($exit, $stdout, $stderr) = _run_cli(
        'publish-move',
        '--nonce', 'bad',
        '--publish-auth-token', $missing_token,
        '--publish-auth-trusted-hmac-key-file', $missing_key,
        $game_root,
        'zz',
    );

    is $exit, 2, 'invalid candidate exits validation before auth file reads';
    like $stdout, qr/^gobanftp[.]publish-move=failed$/m, 'invalid candidate reports failed';
    unlike $stdout, qr/^publish_auth[.]/m, 'auth fields are absent before the auth gate';
    like $stderr, qr/diagnostic .*code=parse_event.*error=move[.]point_bounds/,
        'candidate replay diagnostic is reported';
    unlike $stderr, qr/open \Q$missing_token\E|open \Q$missing_key\E/,
        'missing auth files are not opened for invalid candidates';
    is_deeply [_event_names($game_root)], [], 'invalid candidate writes no event';
};

subtest 'publish-ack denied preflight does not add an ack event' => sub {
    my ($root, $game_root) = _make_game_root();
    my ($key_path, $key) = _write_key($root);
    my ($move, $move_id) = _move(nonce => 'root');
    _write_text(File::Spec->catfile($game_root, 'events', $move), '');

    my ($ack, $ack_id) = build_ack_name(
        game_descriptor => $GAME,
        target_id       => $move_id,
        player          => 'bob',
        nonce           => 'ack1',
    );
    my ($wrong_ack, $wrong_ack_id) = build_ack_name(
        game_descriptor => $GAME,
        target_id       => $move_id,
        player          => 'bob',
        nonce           => 'wrongack',
    );
    my $token_path = _write_token($root, 'wrong-ack-token.jsonl',
        _token($key, $wrong_ack, $wrong_ack_id));

    my ($exit, $stdout, $stderr) = _run_cli(
        'publish-ack',
        '--nonce', 'ack1',
        '--publish-auth-token', $token_path,
        '--publish-auth-trusted-hmac-key-file', $key_path,
        $game_root,
        $move_id,
    );

    is $exit, 2, 'wrong ack token exits validation';
    like $stdout, qr/^gobanftp[.]publish-ack=failed$/m, 'publish-ack reports failed';
    like $stdout, qr/^event=\Q$ack\E$/m, 'reports the candidate ack';
    like $stdout, qr/^event_id=\Q$ack_id\E$/m, 'reports the candidate ack id';
    like $stdout, qr/^publish_auth[.]status=denied$/m, 'prints denied status';
    like $stdout, qr/^publish_auth[.]diagnostic_codes=wrong_signature$/m,
        'stdout exposes wrong signature code';
    like $stderr, qr/diagnostic .*code=wrong_signature.*reason=event_basename[.]mismatch/,
        'stderr reports token binding mismatch';
    is_deeply [_event_names($game_root)], [$move], 'denied ack writes no a1 event';
    unlike $stdout . $stderr, qr/\Q$key->{secret_hex}\E|GOFTP-HMAC-KEY|secret_hex/,
        'ack denial does not leak key material';
};

subtest 'play --move denied preflight prints no board snapshot and writes no event' => sub {
    my ($root, $game_root) = _make_game_root();
    my ($key_path, $key) = _write_key($root);
    my ($wrong_event, $wrong_id) = _move(nonce => 'other');
    my $token_path = _write_token($root, 'wrong-move-token.jsonl',
        _token($key, $wrong_event, $wrong_id));

    my ($exit, $stdout, $stderr) = _run_cli(
        'play',
        '--move', 'aa',
        '--nonce', 'p1',
        '--publish-auth-token', $token_path,
        '--publish-auth-trusted-hmac-key-file', $key_path,
        $game_root,
    );

    is $exit, 2, 'play --move denied exits validation';
    like $stdout, qr/^gobanftp[.]play=failed$/m, 'play reports failed';
    like $stdout, qr/^publish_auth[.]status=denied$/m, 'play prints denied auth status';
    unlike $stdout, qr/^worldline[.]status=/m, 'denied play does not print a board snapshot';
    unlike $stdout, qr/^turn_player=/m, 'denied play does not advance terminal view';
    like $stderr, qr/diagnostic .*code=wrong_signature.*reason=event_basename[.]mismatch/,
        'play denial reports token binding mismatch';
    is_deeply [_event_names($game_root)], [], 'denied play writes no event';
    unlike $stdout . $stderr, qr/\Q$key->{secret_hex}\E|GOFTP-HMAC-KEY|secret_hex/,
        'play denial does not leak key material';
};

subtest 'play --ack denied preflight prints no post-publish snapshot and writes no ack' => sub {
    my ($root, $game_root) = _make_game_root();
    my ($key_path, $key) = _write_key($root);
    my ($move, $move_id) = _move(nonce => 'root');
    _write_text(File::Spec->catfile($game_root, 'events', $move), '');

    my ($ack, $ack_id) = build_ack_name(
        game_descriptor => $GAME,
        target_id       => $move_id,
        player          => 'bob',
        nonce           => 'ack1',
    );
    my ($wrong_event, $wrong_id) = _move(nonce => 'wrong-event');
    my $token_path = _write_token($root, 'wrong-event-token.jsonl',
        _token($key, $wrong_event, $wrong_id));

    my ($exit, $stdout, $stderr) = _run_cli(
        'play',
        '--ack', $move_id,
        '--nonce', 'ack1',
        '--publish-auth-token', $token_path,
        '--publish-auth-trusted-hmac-key-file', $key_path,
        $game_root,
    );

    is $exit, 2, 'play --ack denied exits validation';
    like $stdout, qr/^gobanftp[.]play=failed$/m, 'play reports failed';
    like $stdout, qr/^event=\Q$ack\E$/m, 'reports the candidate ack';
    like $stdout, qr/^event_id=\Q$ack_id\E$/m, 'reports the candidate ack id';
    like $stdout, qr/^publish_auth[.]status=denied$/m, 'play prints denied auth status';
    like $stdout, qr/^publish_auth[.]diagnostic_codes=wrong_signature$/m,
        'stdout exposes wrong signature code';
    unlike $stdout, qr/^event_set_(?:count|root)=/m,
        'denied play --ack does not print post-publish event set';
    unlike $stdout, qr/^worldline[.]/m,
        'denied play --ack does not print worldline state';
    unlike $stdout, qr/^turn_(?:color|player)=/m,
        'denied play --ack does not print turn state';
    unlike $stdout, qr/^  a b c d e f g h i$/m,
        'denied play --ack does not print a board';
    like $stderr, qr/diagnostic .*code=wrong_signature.*reason=event_basename[.]mismatch/,
        'play --ack denial reports token binding mismatch';
    is_deeply [_event_names($game_root)], [$move], 'denied play --ack writes no a1 event';
    unlike $stdout . $stderr, qr/\Q$key->{secret_hex}\E|GOFTP-HMAC-KEY|secret_hex/,
        'play --ack denial does not leak key material';
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

sub _write_key {
    my ($root) = @_;

    my $key = generate_hmac_key_record(secret => ('p' x 32));
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
