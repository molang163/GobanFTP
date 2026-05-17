use v5.34;
use strict;
use warnings;

use FindBin;
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::AckPublisher qw(build_ack_name);
use GobanFTP::CLI;
use GobanFTP::MovePublisher qw(build_move_name);

my $GAME = 'g1.id-publishack.s9.r-chinese-area-v1.k7500.pb-alice.pw-bob';

subtest 'publish-ack writes an opponent ack for a legal move' => sub {
    my (undef, $game_root) = _make_game_root();
    my ($move, $move_id) = _move(
        ply       => 1,
        color     => 'b',
        action    => 'play-aa',
        parent_id => 'genesis',
        nonce     => 'root',
    );
    _write_text(File::Spec->catfile($game_root, 'events', $move), '');

    my ($exit, $stdout, $stderr) = _run_cli('publish-ack', '--nonce', 'ack1', $game_root, $move_id);

    is $exit, 0, 'publish-ack exits success on a clean line';
    like $stdout, qr/^gobanftp\.publish-ack=ok$/m, 'success status is reported';
    like $stdout, qr/^events=2$/m, 'published ack is visible after reload';
    like $stdout, qr/^event=a1\.t-\Q$move_id\E\.by-bob\.n-ack1\.h-[0-9a-v]{16}$/m,
        'ack event basename is reported';
    is $stderr, '', 'clean ack has no diagnostics';

    my ($ack) = $stdout =~ /^event=(a1\..+)$/m;
    ok -f File::Spec->catfile($game_root, 'events', $ack), 'ack event was created';
    is -s File::Spec->catfile($game_root, 'events', $ack), 0, 'ack event is zero bytes';
};

subtest 'publish-ack is allowed while a fork is the only existing problem' => sub {
    my (undef, $game_root) = _make_game_root();
    my ($left, $left_id) = _move(
        ply       => 1,
        color     => 'b',
        action    => 'play-aa',
        parent_id => 'genesis',
        nonce     => 'left',
    );
    my ($right) = _move(
        ply       => 1,
        color     => 'b',
        action    => 'play-bb',
        parent_id => 'genesis',
        nonce     => 'right',
    );
    _write_text(File::Spec->catfile($game_root, 'events', $_), '') for ($left, $right);

    my ($exit, $stdout, $stderr) = _run_cli('publish-ack', '--nonce', 'ackleft', $game_root, $left_id);

    is $exit, 3, 'publish-ack preserves conservative fork exit after publishing';
    like $stdout, qr/^gobanftp\.publish-ack=fork$/m, 'fork status is reported';
    like $stdout, qr/^events=3$/m, 'ack is included in the post-publish listing';
    like $stdout, qr/^event=a1\.t-\Q$left_id\E\.by-bob\.n-ackleft\.h-[0-9a-v]{16}$/m,
        'fork child ack event is reported';
    like $stderr, qr/diagnostic .*code=fork/, 'conservative post-publish replay still reports fork';
    is scalar(grep { /\Aa1\./ } _event_names($game_root)), 1, 'one ack event was added';
};

subtest 'publish-ack rejects pre-existing validation failures without publishing' => sub {
    my (undef, $game_root) = _make_game_root();
    _write_text(File::Spec->catfile($game_root, 'events', 'm1.bad'), "ignored\n");

    my ($exit, $stdout, $stderr) = _run_cli('publish-ack', '--nonce', 'ackbad', $game_root, '0000000000000000');

    is $exit, 2, 'pre-existing validation failure exits validation';
    like $stdout, qr/^gobanftp\.publish-ack=failed$/m, 'failure status is reported';
    like $stderr, qr/diagnostic .*code=parse_event/, 'existing validation diagnostic is reported';
    is_deeply [_event_names($game_root)], ['m1.bad'], 'no ack event was added';
};

subtest 'publish-ack rejects unknown targets without publishing' => sub {
    my (undef, $game_root) = _make_game_root();

    my ($exit, $stdout, $stderr) = _run_cli('publish-ack', '--nonce', 'ackunknown', $game_root, '0000000000000000');

    is $exit, 2, 'unknown target exits validation';
    like $stdout, qr/^gobanftp\.publish-ack=failed$/m, 'failure status is reported';
    like $stderr, qr/diagnostic .*code=ack_target_invalid.*reason=unknown.*target_id=0000000000000000/,
        'unknown target diagnostic is reported';
    is_deeply [_event_names($game_root)], [], 'no ack event was added';
};

subtest 'publish-ack rejects non-move targets without publishing' => sub {
    my (undef, $game_root) = _make_game_root();
    my ($move, $move_id) = _move(
        ply       => 1,
        color     => 'b',
        action    => 'play-aa',
        parent_id => 'genesis',
        nonce     => 'root',
    );
    my ($existing_ack, $existing_ack_id) = build_ack_name(
        game_descriptor => $GAME,
        target_id       => $move_id,
        player          => 'bob',
        nonce           => 'knownack',
    );
    _write_text(File::Spec->catfile($game_root, 'events', $_), '') for ($move, $existing_ack);

    my ($exit, $stdout, $stderr) = _run_cli('publish-ack', '--nonce', 'ackack', $game_root, $existing_ack_id);

    is $exit, 2, 'non-move target exits validation';
    like $stdout, qr/^gobanftp\.publish-ack=failed$/m, 'failure status is reported';
    like $stderr, qr/diagnostic .*code=ack_target_invalid.*reason=not_move.*target_id=\Q$existing_ack_id\E/,
        'non-move target diagnostic is reported';
    is_deeply [_event_names($game_root)], [sort ($move, $existing_ack)], 'no new ack event was added';
};

subtest 'publish-ack preserves existing validation before target checks' => sub {
    my (undef, $game_root) = _make_game_root();
    my ($root, $root_id) = _move(
        ply       => 1,
        color     => 'b',
        action    => 'play-aa',
        parent_id => 'genesis',
        nonce     => 'root',
    );
    my ($illegal, $illegal_id) = _move(
        ply       => 2,
        color     => 'w',
        action    => 'play-aa',
        parent_id => $root_id,
        nonce     => 'occupied',
    );
    _write_text(File::Spec->catfile($game_root, 'events', $_), '') for ($root, $illegal);

    my ($exit, $stdout, $stderr) = _run_cli('publish-ack', '--nonce', 'ackillegal', $game_root, $illegal_id);

    is $exit, 2, 'existing illegal move exits validation';
    like $stdout, qr/^gobanftp\.publish-ack=failed$/m, 'failure status is reported';
    like $stderr, qr/diagnostic .*code=illegal_move.*event_id=\Q$illegal_id\E.*reason=occupied/,
        'existing illegal move diagnostic is reported before ack target validation';
    is_deeply [_event_names($game_root)], [sort ($root, $illegal)], 'no ack event was added';
};

done_testing;

sub _make_game_root {
    my $root = tempdir(CLEANUP => 1);
    my $game_root = File::Spec->catdir($root, $GAME);
    make_path(File::Spec->catdir($game_root, 'events'));
    make_path(File::Spec->catdir($game_root, 'tmp'));
    make_path(File::Spec->catdir($game_root, 'sidecar'));
    _write_text(File::Spec->catfile($game_root, 'sidecar', 'ignored.json'), "{ignored}\n");

    return ($root, $game_root);
}

sub _move {
    my (%args) = @_;

    my $color = $args{color};
    my $player = $args{player}
        // ($color eq 'b' ? 'alice' : $color eq 'w' ? 'bob' : undef);

    return build_move_name(
        game_descriptor => $GAME,
        %args,
        player => $player,
    );
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
