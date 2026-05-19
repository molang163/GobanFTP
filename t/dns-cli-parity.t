use v5.34;
use strict;
use warnings;

use FindBin;
use File::Basename qw(dirname);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use JSON::PP;
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::Auth::HMACKey qw(generate_hmac_key_record write_hmac_key_file);
use GobanFTP::Auth::PublishToken qw(sign_publish_token);
use GobanFTP::CLI;
use GobanFTP::EventSetRoot qw(event_set_root_result);
use GobanFTP::MovePublisher qw(build_move_name);

my $GAME = 'g1.id-dns-cli-parity.s9.r-chinese-area-v1.k7500.pb-alice.pw-bob';
my ($MOVE_B, $ID_B) = build_move_name(
    game_descriptor => $GAME,
    ply             => 1,
    color           => 'b',
    action          => 'play-dd',
    parent_id       => 'genesis',
    player          => 'alice',
    nonce           => 'dnsb',
);
my ($MOVE_W, $ID_W) = build_move_name(
    game_descriptor => $GAME,
    ply             => 2,
    color           => 'w',
    action          => 'play-ee',
    parent_id       => $ID_B,
    player          => 'bob',
    nonce           => 'dnsw',
);
my ($POISON_MOVE) = build_move_name(
    game_descriptor => $GAME,
    ply             => 3,
    color           => 'b',
    action          => 'play-ff',
    parent_id       => $ID_W,
    player          => 'alice',
    nonce           => 'dnsp',
);

my $EXPECTED_ROOT = event_set_root_result(
    game_descriptor => $GAME,
    names           => [$MOVE_B, $MOVE_W],
)->{event_set_root};

subtest 'DNS record CLI verify replay and sgf match the local-equivalent event set' => sub {
    my $local_root = _local_root_with_events($MOVE_B, $MOVE_W);
    my $dns_file = _dns_record_file();

    my ($local_verify_exit, $local_verify_stdout, $local_verify_stderr);
    my ($local_replay_exit, $local_replay_stdout, $local_replay_stderr);
    my ($local_sgf_exit, $local_sgf_stdout, $local_sgf_stderr);
    {
        local %ENV = %ENV;
        _local_env($local_root);

        ($local_verify_exit, $local_verify_stdout, $local_verify_stderr) = _run_cli('verify', $GAME);
        ($local_replay_exit, $local_replay_stdout, $local_replay_stderr) = _run_cli('replay', $GAME);
        ($local_sgf_exit, $local_sgf_stdout, $local_sgf_stderr) = _run_cli('sgf', $GAME);
    }

    my ($dns_verify_exit, $dns_verify_stdout, $dns_verify_stderr);
    my ($dns_replay_exit, $dns_replay_stdout, $dns_replay_stderr);
    my ($dns_sgf_exit, $dns_sgf_stdout, $dns_sgf_stderr);
    {
        local %ENV = %ENV;
        _dns_env($dns_file);

        ($dns_verify_exit, $dns_verify_stdout, $dns_verify_stderr) = _run_cli('verify', $GAME);
        ($dns_replay_exit, $dns_replay_stdout, $dns_replay_stderr) = _run_cli('replay', $GAME);
        ($dns_sgf_exit, $dns_sgf_stdout, $dns_sgf_stderr) = _run_cli('sgf', $GAME);
    }

    is $local_verify_exit, 0, 'local verify exits success';
    is $local_verify_stderr, '', 'local verify has no diagnostics';
    is $dns_verify_exit, $local_verify_exit, 'DNS verify exit matches local';
    is $dns_verify_stderr, $local_verify_stderr, 'DNS verify diagnostics match local';
    like $dns_verify_stdout, qr/^gobanftp\.verify=ok$/m, 'DNS verify reports ok';
    _assert_summary_parity($dns_verify_stdout, $local_verify_stdout, qw(
        events
        event_set_count
        event_set_root
        canonical_moves
        legal_moves
    ));
    is _field($dns_verify_stdout, 'event_set_root'), $EXPECTED_ROOT,
        'DNS verify reports the local-equivalent event-set root';

    is $local_replay_exit, 0, 'local replay exits success';
    is $local_replay_stderr, '', 'local replay has no diagnostics';
    is $dns_replay_exit, $local_replay_exit, 'DNS replay exit matches local';
    is $dns_replay_stderr, $local_replay_stderr, 'DNS replay diagnostics match local';
    like $dns_replay_stdout, qr/^gobanftp\.replay=ok$/m, 'DNS replay reports ok';
    _assert_summary_parity($dns_replay_stdout, $local_replay_stdout, qw(
        events
        event_set_count
        event_set_root
        canonical_moves
        legal_moves
        canonical_ids
    ));
    is _field($dns_replay_stdout, 'canonical_ids'), "$ID_B,$ID_W",
        'DNS replay reports the local-equivalent canonical ids';

    is $local_sgf_exit, 0, 'local sgf exits success';
    is $local_sgf_stderr, '', 'local sgf has no diagnostics';
    is $dns_sgf_exit, $local_sgf_exit, 'DNS sgf exit matches local';
    is $dns_sgf_stderr, $local_sgf_stderr, 'DNS sgf diagnostics match local';
    is $dns_sgf_stdout, $local_sgf_stdout, 'DNS sgf projection matches local';
    like $dns_sgf_stdout, qr/;B\[dd\]/, 'DNS sgf renders the black move';
    like $dns_sgf_stdout, qr/;W\[ee\]/, 'DNS sgf renders the white move';
};

subtest 'DNS record publish-move is rejected as read-only storage' => sub {
    my $dns_file = _dns_record_file();
    my $before = _read_text($dns_file);

    local %ENV = %ENV;
    _dns_env($dns_file);

    my ($exit, $stdout, $stderr) = _run_cli('publish-move', '--nonce', 'blocked', $GAME, 'ff');
    is $exit, 4, 'publish-move exits storage failure for DNS records';
    is $stdout, '', 'read-only publish writes no stdout';
    like $stderr, qr/^storage: .*read-only/m, 'read-only publish reports the storage boundary';
    is _read_text($dns_file), $before, 'read-only publish does not mutate the DNS record file';
};

subtest 'DNS record publish auth preflight is separate from read-only publish support' => sub {
    my $dns_file = _dns_record_file();
    my $before = _read_text($dns_file);
    my $auth_dir = tempdir(CLEANUP => 1);
    my ($key_path, $key) = _write_publish_key($auth_dir);
    my ($event, $event_id) = _candidate_publish_move('authgate');
    my $token_path = _write_publish_token($auth_dir, 'publish-token.jsonl',
        $key, $event, $event_id);

    local %ENV = %ENV;
    _dns_env($dns_file);

    my ($denied_exit, $denied_stdout, $denied_stderr) = _run_cli(
        'publish-move',
        '--nonce', 'authgate',
        '--publish-auth-token', $token_path,
        '--publish-auth-trusted-hmac-key-file', $key_path,
        '--publish-auth-trusted-hmac-status', "$key->{key_id}=rotated",
        $GAME,
        'ff',
    );
    is $denied_exit, 2, 'denied publish token exits validation before DNS publish';
    like $denied_stdout, qr/^gobanftp[.]publish-move=failed$/m,
        'denied token reports publish failure';
    like $denied_stdout, qr/^publish_auth[.]status=denied$/m,
        'denied token reports auth denial';
    like $denied_stderr, qr/diagnostic .*code=untrusted_signature.*reason=key[.]rotated/,
        'denied token reports lifecycle denial';
    unlike $denied_stderr, qr/^storage: .*read-only/m,
        'denied token does not reach the DNS read-only publish boundary';
    is _read_text($dns_file), $before, 'denied token does not mutate the DNS record file';

    my ($authorized_exit, $authorized_stdout, $authorized_stderr) = _run_cli(
        'publish-move',
        '--nonce', 'authgate',
        '--publish-auth-token', $token_path,
        '--publish-auth-trusted-hmac-key-file', $key_path,
        $GAME,
        'ff',
    );
    is $authorized_exit, 4, 'authorized token still exits storage failure for DNS records';
    unlike $authorized_stdout, qr/^gobanftp[.]publish-move=ok$/m,
        'authorized token does not turn DNS records into a publish-capable store';
    like $authorized_stderr, qr/^storage: dns record store is read-only/m,
        'authorized token still reports the DNS storage boundary';
    is _read_text($dns_file), $before, 'authorized token does not mutate the DNS record file';
};

done_testing;

sub _dns_rows {
    my $other_game = 'g1.id-dns-other.s9.r-chinese-area-v1.k7500.pb-alice.pw-bob';
    return (
        "ttl=3600 type=TXT owner=02.events.$GAME.example. event=\"$MOVE_W\"",
        "ttl=1 type=txt owner=01.events.$GAME.example. event=$MOVE_B",
        "ttl=2 type=TXT owner=01.duplicate.events.$GAME.example. event=\"$MOVE_B\"",
        "ttl=3 type=A owner=03.events.$GAME.example. event=$POISON_MOVE",
        "ttl=4 type=TXT owner=03.events.$other_game.example. event=$POISON_MOVE",
        "ttl=5 type=TXT owner=03.events.$GAME.evil. event=$POISON_MOVE",
        "ttl=6 type=TXT event=$POISON_MOVE",
        "ttl=7 type=TXT owner=sidecar.$GAME.example. event=$POISON_MOVE sidecar=$ID_B.sig",
        "ttl=8 type=TXT owner=projections.sgf.$GAME.example. event=$POISON_MOVE projection=sgf/main.sgf",
        "ttl=9 type=TXT owner=tmp.$GAME.example. event=$POISON_MOVE tmp=upload.part",
    );
}

sub _dns_record_file {
    my $dir = tempdir(CLEANUP => 1);
    my $path = File::Spec->catfile($dir, 'dns-records.txt');
    _write_text($path, join('', map { "$_\n" } _dns_rows()));
    return $path;
}

sub _write_publish_key {
    my ($dir) = @_;

    my $key = generate_hmac_key_record(secret => ('d' x 32));
    my $path = File::Spec->catfile($dir, 'player.hmac-key');
    write_hmac_key_file($path, $key);

    return ($path, $key);
}

sub _candidate_publish_move {
    my ($nonce) = @_;

    return build_move_name(
        game_descriptor => $GAME,
        ply             => 3,
        color           => 'b',
        action          => 'play-ff',
        parent_id       => $ID_W,
        player          => 'alice',
        nonce           => $nonce,
    );
}

sub _write_publish_token {
    my ($dir, $name, $key, $event, $event_id) = @_;

    my $token = sign_publish_token(
        profile         => 'signed-hmac-goftp1',
        game_descriptor => $GAME,
        event_basename  => $event,
        event_id        => $event_id,
        key_id          => $key->{key_id},
        key             => $key->{secret},
    );

    my $path = File::Spec->catfile($dir, $name);
    open my $fh, '>:encoding(UTF-8)', $path or die "open $path: $!";
    print {$fh} JSON::PP->new->canonical(1)->encode($token), "\n";
    close $fh or die "close $path: $!";

    return $path;
}

sub _local_root_with_events {
    my (@events) = @_;

    my $root = tempdir(CLEANUP => 1);
    for my $event (@events) {
        _write_text(File::Spec->catfile($root, $GAME, 'events', $event), "\n");
    }
    _write_text(File::Spec->catfile($root, $GAME, 'sidecar', "$ID_B.sig"), "ignored\n");
    _write_text(File::Spec->catfile($root, $GAME, 'projections', 'sgf', 'main.sgf'), "ignored\n");
    _write_text(File::Spec->catfile($root, $GAME, 'tmp', 'upload.part'), "ignored\n");

    return $root;
}

sub _local_env {
    my ($root) = @_;

    $ENV{GOBANFTP_STORE} = 'local';
    $ENV{GOBANFTP_ROOT} = $root;
    return;
}

sub _dns_env {
    my ($record_file) = @_;

    $ENV{GOBANFTP_STORE} = 'dns-record';
    $ENV{GOBANFTP_DNS_RECORD_FILE} = $record_file;
    $ENV{GOBANFTP_DNS_OWNER_SUFFIX} = 'example.';
    delete $ENV{GOBANFTP_ROOT};
    return;
}

sub _assert_summary_parity {
    my ($got, $want, @fields) = @_;

    for my $field (@fields) {
        is _field($got, $field), _field($want, $field), "DNS $field matches local";
    }
}

sub _field {
    my ($stdout, $field) = @_;

    my ($value) = $stdout =~ /^\Q$field\E=(.*)$/m;
    return $value;
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

sub _write_text {
    my ($path, $content) = @_;

    make_path(dirname($path));
    open my $fh, '>:encoding(UTF-8)', $path or die "open $path: $!";
    print {$fh} $content;
    close $fh or die "close $path: $!";
    return 1;
}

sub _read_text {
    my ($path) = @_;

    open my $fh, '<:encoding(UTF-8)', $path or die "open $path: $!";
    local $/;
    my $text = <$fh> // '';
    close $fh or die "close $path: $!";
    return $text;
}
