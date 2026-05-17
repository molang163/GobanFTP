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
use GobanFTP::Replay qw(replay);

my $fixture_dir = "$FindBin::Bin/fixtures/e2e";

subtest 'local create publish replay project chain' => sub {
    my $root = tempdir(CLEANUP => 1);
    my $game = _read_single(File::Spec->catfile($fixture_dir, 'game.name'));
    my @events = _read_names(File::Spec->catfile($fixture_dir, 'events.names'));
    my @ids = map { /\Ah-([0-9a-v]{16})\z/ ? $1 : /\.h-([0-9a-v]{16})\z/ ? $1 : die "bad fixture event: $_" } @events;

    my $game_root = File::Spec->catdir($root, $game);
    local %ENV = %ENV;
    delete $ENV{GOBANFTP_STORE};
    $ENV{GOBANFTP_ROOT} = $root;

    my ($create_exit, $create_stdout, $create_stderr) = _run_cli('create-game', $game);
    is $create_exit, 0, 'CLI create-game exits success';
    like $create_stdout, qr/^gobanftp\.create-game=ok$/m, 'CLI create-game reports ok';
    like $create_stdout, qr/^store=local$/m, 'CLI create-game uses local store';
    is $create_stderr, '', 'CLI create-game has no diagnostics';

    ok -d File::Spec->catdir($game_root, 'events'), 'events directory was created';
    ok -d File::Spec->catdir($game_root, 'tmp'), 'tmp directory was created';

    make_path(File::Spec->catdir($game_root, 'sidecar'));
    _write_text(File::Spec->catfile($game_root, 'sidecar', 'debug.txt'), "password=hunter2\n");
    _write_text(File::Spec->catfile($game_root, 'tmp', 'pending.part'), "GOBANFTP_FTP_PASSWORD=super-secret\n");

    my @moves = (
        ['first',  'aa'],
        ['second', 'bb'],
        ['third',  'pass'],
    );
    my @published;
    for my $index (0 .. $#moves) {
        my ($nonce, $action) = @{ $moves[$index] };
        my ($exit, $stdout, $stderr) = _run_cli('publish-move', '--nonce', $nonce, $game, $action);

        is $exit, 0, "CLI publish-move $action exits success";
        like $stdout, qr/^gobanftp\.publish-move=ok$/m, "CLI publish-move $action reports ok";
        is $stderr, '', "CLI publish-move $action has no diagnostics";

        my ($event) = $stdout =~ /^event=(m1\..+)$/m;
        is $event, $events[$index], "CLI publish-move $action produced the expected event name";
        push @published, $event;
    }

    is_deeply
        [ _event_names($game_root) ],
        [ sort @events ],
        'events listing contains only the published public basenames';

    for my $index (0 .. $#published) {
        _write_text(
            File::Spec->catfile($game_root, 'events', $published[$index]),
            "event-byte-secret-$index\n",
        );
    }

    my @listed = _event_names($game_root);
    my $result = replay(game_descriptor => $game, events => \@listed);
    is_deeply [ $result->diagnostics ], [], 'module replay has no diagnostics';
    is_deeply [ $result->canonical_ids ], \@ids, 'module replay reconstructs the canonical chain';

    my ($replay_exit, $replay_stdout, $replay_stderr) = _run_cli('replay', $game);
    is $replay_exit, 0, 'CLI replay exits success';
    like $replay_stdout, qr/^gobanftp\.replay=ok$/m, 'CLI replay reports ok';
    like $replay_stdout, qr/^canonical_ids=\Q@{[join ',', @ids]}\E$/m, 'CLI replay reports canonical ids';
    is $replay_stderr, '', 'CLI replay has no diagnostics';

    my ($project_exit, $project_stdout, $project_stderr) = _run_cli('project', $game);
    is $project_exit, 0, 'CLI project exits success';
    like $project_stdout, qr/^gobanftp\.project=ok$/m, 'CLI project reports ok';
    like $project_stdout, qr/^listing=.*projections.*listing\.txt$/m,
        'CLI project reports listing transcript path';
    is $project_stderr, '', 'CLI project has no diagnostics';

    ok -f File::Spec->catfile($game_root, qw(projections sgf main.sgf)), 'SGF projection exists';
    ok -f File::Spec->catfile($game_root, qw(projections oracle board.txt)), 'board projection exists';
    ok -f File::Spec->catfile($game_root, qw(projections oracle verdict.txt)), 'verdict projection exists';
    ok -f File::Spec->catfile($game_root, qw(projections oracle listing.txt)), 'listing transcript projection exists';
    ok -d File::Spec->catdir($game_root, qw(projections board)), 'board directory projection exists';
    ok -d File::Spec->catdir($game_root, qw(projections graveyard)), 'graveyard directory projection exists';

    my $listing = _slurp(File::Spec->catfile($game_root, qw(projections oracle listing.txt)));
    like $listing, qr/\nNLST events\/\n150 Opening data connection for events\/\.\n/,
        'listing transcript records the NLST events/ read';
    is_deeply [_listing_transcript_events($listing)], [sort @events],
        'listing transcript comes from sorted events listing';
    unlike $listing, qr/event-byte-secret|hunter2|super-secret|GOBANFTP_FTP_PASSWORD/,
        'listing transcript does not include event bytes sidecar or tmp bytes';
    _assert_listing_not_sent_contract($listing);

    is_deeply
        [ _event_names($game_root) ],
        [ sort @events ],
        'project does not mutate event names';

    my $combined_output = $replay_stdout . $replay_stderr . $project_stdout . $project_stderr . $listing;
    unlike $combined_output, qr/hunter2|super-secret|GOBANFTP_FTP_PASSWORD/,
        'sidecar and tmp secret-looking bytes are not replay or projection diagnostics';
};

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

sub _read_single {
    my ($path) = @_;

    open my $fh, '<:encoding(UTF-8)', $path or die "open $path: $!";
    my $line = <$fh>;
    close $fh or die "close $path: $!";
    die "$path is empty" if !defined $line;
    chomp $line;
    return $line;
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

sub _event_names {
    my ($game_root) = @_;

    my $dir = File::Spec->catdir($game_root, 'events');
    opendir my $dh, $dir or die "opendir $dir: $!";
    my @names = sort grep { $_ ne '.' && $_ ne '..' } readdir $dh;
    closedir $dh or die "closedir $dir: $!";

    return @names;
}

sub _slurp {
    my ($path) = @_;

    open my $fh, '<:encoding(UTF-8)', $path or die "open $path: $!";
    my $text = do { local $/; <$fh> };
    close $fh or die "close $path: $!";

    return $text;
}

sub _listing_transcript_events {
    my ($text) = @_;

    my @events;
    my $in_listing = 0;
    for my $line (split /\n/, $text) {
        if ($line eq '150 Opening data connection for events/.') {
            $in_listing = 1;
            next;
        }
        last if $in_listing && $line eq '226 NLST complete.';
        push @events, $line if $in_listing;
    }

    return @events;
}

sub _assert_listing_not_sent_contract {
    my ($text) = @_;

    my $not_sent = join "\n",
        'Commands not sent by GOFTP/1 replay:',
        '',
        'SIZE events/<event-basename>',
        'MDTM events/<event-basename>',
        'RETR events/<event-basename>',
        '';

    like $text, qr/\n\Q$not_sent\E\n/, 'SIZE/MDTM/RETR are listed under commands not sent';

    for my $command (qw(SIZE MDTM RETR)) {
        my @command_lines = $text =~ /^($command .*)$/mg;
        is_deeply \@command_lines, ["$command events/<event-basename>"],
            "$command is not emitted as an event-specific replay command";
    }
}

sub _write_text {
    my ($path, $text) = @_;

    open my $fh, '>:encoding(UTF-8)', $path or die "write $path: $!";
    print {$fh} $text;
    close $fh or die "close $path: $!";
}
