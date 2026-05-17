use v5.34;
use strict;
use warnings;

use FindBin;
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::CLI;
use GobanFTP::EventID qw(event_id);
use GobanFTP::MovePublisher qw(build_move_name);

my $GAME = 'g1.id-publish.s9.r-chinese-area-v1.k7500.pb-alice.pw-bob';

subtest 'build_move_name uses the EventID hash' => sub {
    my ($name, $id) = build_move_name(
        game_descriptor => $GAME,
        ply             => 1,
        color           => 'b',
        action          => 'play-aa',
        parent_id       => 'genesis',
        player          => 'alice',
        nonce           => 'b1',
    );

    my ($without_hash) = $name =~ /\A(.+)\.h-[0-9a-v]{16}\z/;
    is $id, event_id($GAME, $without_hash), 'event id comes from GobanFTP::EventID';
    is $name, "$without_hash.h-$id", 'event name appends the EventID value';
};

subtest 'publish-move writes a validated local move event' => sub {
    my ($root, $game_root) = _make_game_root();

    local %ENV = %ENV;
    delete $ENV{GOBANFTP_STORE};
    delete $ENV{GOBANFTP_ROOT};

    my ($exit, $stdout, $stderr) = _run_cli('publish-move', '--nonce', 'b1', $game_root, 'aa');

    is $exit, 0, 'publish-move exits success';
    like $stdout, qr/^gobanftp\.publish-move=ok$/m, 'status is reported';
    like $stdout, qr/^events=1$/m, 'one event is listed after publish';
    is $stderr, '', 'no diagnostics';

    my ($event) = $stdout =~ /^event=(m1\..+)$/m;
    like $event, qr/\Am1\.p000001\.b\.play-aa\.pa-genesis\.by-alice\.n-b1\.h-[0-9a-v]{16}\z/,
        'event basename has the expected move fields';
    ok -f File::Spec->catfile($game_root, 'events', $event), 'event file was created';
    is -s File::Spec->catfile($game_root, 'events', $event), 0, 'event file is zero bytes';
};

subtest 'candidate validation failure exits 2 without publishing' => sub {
    my (undef, $game_root) = _make_game_root();

    my ($exit, $stdout, $stderr) = _run_cli('publish-move', '--nonce', 'bad', $game_root, 'zz');

    is $exit, 2, 'out-of-bounds point exits validation failure';
    like $stdout, qr/^gobanftp\.publish-move=failed$/m, 'failed status is reported';
    like $stderr, qr/diagnostic .*code=parse_event.*error=move\.point_bounds/, 'parse diagnostic is reported';
    is_deeply [_event_names($game_root)], [], 'no event was written';
};

subtest 'pre-existing validation failure exits 2 without publishing' => sub {
    my (undef, $game_root) = _make_game_root();
    _write_text(File::Spec->catfile($game_root, 'events', 'm1.bad'), "ignored\n");

    my ($exit, $stdout, $stderr) = _run_cli('publish-move', '--nonce', 'b1', $game_root, 'aa');

    is $exit, 2, 'existing invalid listing exits validation failure';
    like $stdout, qr/^gobanftp\.publish-move=failed$/m, 'failed status is reported';
    like $stderr, qr/diagnostic .*code=parse_event/, 'existing validation diagnostic is reported';
    is_deeply [_event_names($game_root)], ['m1.bad'], 'no event was added';
};

subtest 'pre-existing fork exits 3 without publishing' => sub {
    my (undef, $game_root) = _make_game_root();
    my @forks = (
        scalar build_move_name(
            game_descriptor => $GAME,
            ply             => 1,
            color           => 'b',
            action          => 'play-aa',
            parent_id       => 'genesis',
            player          => 'alice',
            nonce           => 'f1',
        ),
        scalar build_move_name(
            game_descriptor => $GAME,
            ply             => 1,
            color           => 'b',
            action          => 'play-bb',
            parent_id       => 'genesis',
            player          => 'alice',
            nonce           => 'f2',
        ),
    );
    _write_text(File::Spec->catfile($game_root, 'events', $_), '') for @forks;

    my ($exit, $stdout, $stderr) = _run_cli('publish-move', '--nonce', 'b2', $game_root, 'cc');

    is $exit, 3, 'existing fork exits conflict';
    like $stdout, qr/^gobanftp\.publish-move=fork$/m, 'fork status is reported';
    like $stderr, qr/diagnostic .*code=fork/, 'fork diagnostic is reported';
    is_deeply [_event_names($game_root)], [sort @forks], 'no event was added to the fork';
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
