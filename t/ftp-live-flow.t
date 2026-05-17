use v5.34;
use strict;
use warnings;

use FindBin;
use Test::More;

use lib "$FindBin::Bin/../lib";

BEGIN {
    if (($ENV{GOBANFTP_FTP_TEST} // '') ne '1') {
        plan skip_all => 'live FTP flow test requires GOBANFTP_FTP_TEST=1';
    }

    my @missing = grep { !defined($ENV{$_}) || $ENV{$_} eq '' } qw(
        GOBANFTP_FTP_HOST
        GOBANFTP_FTP_USER
        GOBANFTP_FTP_PASSWORD
        GOBANFTP_FTP_ROOT
    );

    plan skip_all => 'live FTP flow test requires env: ' . join(', ', @missing) if @missing;
}

use GobanFTP::CLI;
use GobanFTP::MovePublisher qw(build_move_name);
use GobanFTP::Store::Config qw(store_from_env);

local %ENV = %ENV;
$ENV{GOBANFTP_STORE} = 'ftp';

my $game_id = sprintf 'ftp-flow-%x-%x-%08x', time, $$, int(rand(0xffffffff));

my ($create_exit, $create_stdout, $create_stderr) = _run_cli(
    qw(create-game --size 9 --black alice --white bob --id),
    $game_id,
);

is $create_exit, 0, 'FTP create-game succeeds';
like $create_stdout, qr/^store=ftp$/m, 'FTP store is selected';
is $create_stderr, '', 'FTP create-game has no diagnostics';

my ($game) = $create_stdout =~ /^game=(g1\..+)$/m;
ok $game, 'created game descriptor was reported';

my ($black_exit, $black_stdout, $black_stderr) = _run_cli(
    qw(publish-move --nonce liveb),
    $game,
    'aa',
);
is $black_exit, 0, 'FTP black move publishes';
like $black_stdout, qr/^events=1$/m, 'FTP black move is visible in listing';
is $black_stderr, '', 'FTP black move has no diagnostics';

my ($black_id) = $black_stdout =~ /^event_id=([0-9a-v]{16})$/m;
like $black_id // '', qr/\A[0-9a-v]{16}\z/, 'FTP black move reports event id';

my ($white_exit, $white_stdout, $white_stderr) = _run_cli(
    qw(publish-move --nonce livew),
    $game,
    'bb',
);
is $white_exit, 0, 'FTP white move publishes';
like $white_stdout, qr/^events=2$/m, 'FTP white move is visible in listing';
is $white_stderr, '', 'FTP white move has no diagnostics';

my ($white_id) = $white_stdout =~ /^event_id=([0-9a-v]{16})$/m;
like $white_id // '', qr/\A[0-9a-v]{16}\z/, 'FTP white move reports event id';

my ($verify_exit, $verify_stdout, $verify_stderr) = _run_cli('verify', $game);
is $verify_exit, 0, 'FTP verify accepts descriptor basename';
like $verify_stdout, qr/^gobanftp\.verify=ok$/m, 'FTP verify reports ok';
like $verify_stdout, qr/^canonical_moves=2$/m, 'FTP verify replays both moves';
is $verify_stderr, '', 'FTP verify has no diagnostics';

my ($replay_exit, $replay_stdout, $replay_stderr) = _run_cli('replay', $game);
is $replay_exit, 0, 'FTP replay accepts descriptor basename';
like $replay_stdout, qr/^canonical_moves=2$/m, 'FTP replay sees FTP event listing';
is $replay_stderr, '', 'FTP replay has no diagnostics';

my ($sgf_exit, $sgf_stdout, $sgf_stderr) = _run_cli('sgf', $game);
is $sgf_exit, 0, 'FTP sgf reads event listing';
like $sgf_stdout, qr/\A\(;/, 'FTP sgf prints an SGF collection';
like $sgf_stdout, qr/;B\[aa\].*;W\[bb\]/s, 'FTP sgf renders both moves';
is $sgf_stderr, '', 'FTP sgf has no diagnostics';

my ($play_once_exit, $play_once_stdout, $play_once_stderr) = _run_cli('play', '--once', $game);
is $play_once_exit, 0, 'FTP play --once exits success';
like $play_once_stdout, qr/^gobanftp\.play=ok$/m, 'FTP play --once reports ok';
like $play_once_stdout, qr/^events=2$/m, 'FTP play --once sees event listing';
like $play_once_stdout, qr/^canonical_moves=2$/m, 'FTP play --once replays both moves';
like $play_once_stdout, qr/^worldline\.status=main$/m, 'FTP play --once renders main worldline';
is $play_once_stderr, '', 'FTP play --once has no diagnostics';

my ($watch_exit, $watch_stdout, $watch_stderr) = _run_cli('watch', '--once', '--interval', '0', $game);
is $watch_exit, 0, 'FTP watch --once --interval 0 exits success';
like $watch_stdout, qr/^gobanftp\.watch=ok$/m, 'FTP watch reports ok';
like $watch_stdout, qr/^snapshot=1$/m, 'FTP watch reports one bounded snapshot';
like $watch_stdout, qr/^events=2$/m, 'FTP watch sees event listing';
like $watch_stdout, qr/^worldline\.status=main$/m, 'FTP watch renders main worldline';
is $watch_stderr, '', 'FTP watch has no diagnostics';

my ($fork_event, $fork_id) = build_move_name(
    game_descriptor => $game,
    ply             => 1,
    color           => 'b',
    action          => 'play-cc',
    parent_id       => 'genesis',
    player          => 'alice',
    nonce           => 'forkr',
);
ok _publish_ftp_event_name($game, $fork_event), 'FTP fork setup publishes a competing event name';

my ($ack_exit, $ack_stdout, $ack_stderr) = _run_cli(
    qw(publish-ack --nonce ackleft),
    $game,
    $black_id,
);
is $ack_exit, 3, 'FTP publish-ack preserves conservative fork exit';
like $ack_stdout, qr/^gobanftp\.publish-ack=fork$/m, 'FTP publish-ack reports fork status';
like $ack_stdout, qr/^events=4$/m, 'FTP publish-ack sees both fork moves, the line move, and the ack';
like $ack_stdout, qr/^canonical_moves=0$/m, 'FTP publish-ack remains conservative at the fork';
like $ack_stdout, qr/^event=a1\.t-\Q$black_id\E\.by-bob\.n-ackleft\.h-[0-9a-v]{16}$/m,
    'FTP publish-ack reports ack event basename';
like $ack_stderr, qr/diagnostic .*code=fork/, 'FTP publish-ack emits conservative fork diagnostic';

my ($play_ack_exit, $play_ack_stdout, $play_ack_stderr) = _run_cli(
    'play',
    '--ack',
    $black_id,
    '--nonce',
    'playack',
    $game,
);
is $play_ack_exit, 0, 'FTP play --ack exits success after ack-assisted recovery';
like $play_ack_stdout, qr/^event=a1\.t-\Q$black_id\E\.by-bob\.n-playack\.h-[0-9a-v]{16}$/m,
    'FTP play --ack reports ack event basename';
like $play_ack_stdout, qr/^gobanftp\.play=ok$/m, 'FTP play --ack reports ok';
like $play_ack_stdout, qr/^events=5$/m, 'FTP play --ack reloads the listing after publishing';
like $play_ack_stdout, qr/^canonical_moves=2$/m, 'FTP play --ack follows the acked line';
like $play_ack_stdout, qr/^worldline\.status=main$/m, 'FTP play --ack renders recovered main worldline';
like $play_ack_stdout, qr/^worldline\.canonical_ids=\Q$black_id,$white_id\E$/m,
    'FTP play --ack chooses the acked fork child and its continuation';
unlike $play_ack_stdout, qr/^worldline\.canonical_ids=.*\Q$fork_id\E/m,
    'FTP play --ack does not choose the unacked fork child';
is $play_ack_stderr, '', 'FTP play --ack has no diagnostics after recovery';

my ($fork_watch_exit, $fork_watch_stdout, $fork_watch_stderr) = _run_cli(
    'watch',
    '--once',
    '--interval',
    '0',
    $game,
);
is $fork_watch_exit, 3, 'FTP watch remains conservative on an acked fork';
like $fork_watch_stdout, qr/^gobanftp\.watch=fork$/m, 'FTP watch reports fork status on the acked listing';
like $fork_watch_stdout, qr/^snapshot=1$/m, 'FTP fork watch reports one bounded snapshot';
like $fork_watch_stdout, qr/^events=5$/m, 'FTP fork watch sees all fork and ack events';
like $fork_watch_stdout, qr/^worldline\.status=fork$/m, 'FTP fork watch does not use ack-assisted recovery';
like $fork_watch_stderr, qr/diagnostic .*code=fork/, 'FTP fork watch emits conservative fork diagnostic';

ok !_ftp_has_name($game, 'projections'), 'FTP live flow did not write projections';

done_testing;

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

sub _publish_ftp_event_name {
    my ($game, $event_name) = @_;

    my $store = _ftp_store_from_env();
    my $ok = eval {
        $store->publish_event_name($game, $event_name);
        1;
    };
    my $error = $@;
    _quit_store($store);
    die $error || 'publish FTP event failed' if !$ok;

    return 1;
}

sub _ftp_has_name {
    my ($path, $name) = @_;

    my $store = _ftp_store_from_env();
    my $exists = eval { $store->exists_name($path, $name) ? 1 : 0 };
    my $error = $@;
    _quit_store($store);
    die $error if $error;

    return $exists;
}

sub _ftp_store_from_env {
    my $store = eval { store_from_env(mode => 'ftp') };
    die $@ || 'create FTP store failed' if !$store;

    return $store;
}

sub _quit_store {
    my ($store) = @_;

    return if !$store || !$store->can('quit');
    eval { $store->quit };
    return;
}
