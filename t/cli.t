use v5.34;
use strict;
use warnings;

use FindBin;
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use IPC::Open3;
use Symbol qw(gensym);
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::CLI;

my $fixture_dir = "$FindBin::Bin/fixtures/cli";

subtest 'verify reads only the local events listing and writes nothing' => sub {
    my ($game_root) = _make_game('events.names');
    _write_text(File::Spec->catfile($game_root, 'events', 'README'), "ignored direct non-event\n");
    my @events_before = _dir_names(File::Spec->catdir($game_root, 'events'));

    my ($exit, $stdout, $stderr) = _run_cli('verify', $game_root);

    is $exit, 0, 'verify exits success';
    like $stdout, qr/^gobanftp\.verify=ok$/m, 'verify status is on stdout';
    like $stdout, qr/^events=3$/m, 'verify reports event listing count';
    like $stdout, qr/^event_set_count=3$/m, 'verify reports accepted event-set count';
    like $stdout, qr/^event_set_root=599c00f0614e400274a92ab1c96d09087a53d0d88bd8b0ecba481ac60a1f1461$/m,
        'verify reports the accepted event-set root';
    is $stderr, '', 'verify has no diagnostics';
    is_deeply [_dir_names(File::Spec->catdir($game_root, 'events'))], \@events_before, 'events are not modified';
    ok !-e File::Spec->catdir($game_root, 'projections'), 'verify does not write projections';
};

subtest 'replay prints a canonical line summary' => sub {
    my ($game_root) = _make_game('events.names');
    my ($exit, $stdout, $stderr) = _run_cli('replay', $game_root);

    is $exit, 0, 'replay exits success';
    like $stdout, qr/^gobanftp\.replay=ok$/m, 'replay status is on stdout';
    like $stdout, qr/^event_set_count=3$/m, 'replay reports accepted event-set count';
    like $stdout, qr/^event_set_root=599c00f0614e400274a92ab1c96d09087a53d0d88bd8b0ecba481ac60a1f1461$/m,
        'replay reports the accepted event-set root';
    like $stdout, qr/^canonical_moves=3$/m, 'replay reports canonical move count';
    like $stdout, qr/^canonical_ids=khjclcui7pejbv3m,bihb3re4k9hlucat,kcvtlonfje163p9q$/m,
        'replay reports canonical ids';
    is $stderr, '', 'replay has no diagnostics';
};

subtest 'sgf prints to stdout by default' => sub {
    my ($game_root) = _make_game('events.names');
    my ($exit, $stdout, $stderr) = _run_cli('sgf', $game_root);

    is $exit, 0, 'sgf exits success';
    like $stdout, qr/\A\(;/, 'sgf writes an SGF collection';
    like $stdout, qr/;B\[aa\]/, 'sgf includes black move';
    like $stdout, qr/;W\[bb\]/, 'sgf includes white move';
    unlike $stdout, qr/^event_set_root=/m, 'plain sgf stdout is not polluted by event-set witness fields';
    is $stderr, '', 'sgf has no diagnostics';
    ok !-e File::Spec->catdir($game_root, 'projections'), 'plain sgf does not write projections';
};

subtest 'sgf --write writes only projections/sgf/main.sgf' => sub {
    my ($game_root) = _make_game('events.names');
    my ($exit, $stdout, $stderr) = _run_cli('sgf', '--write', $game_root);

    is $exit, 0, 'sgf --write exits success';
    like $stdout, qr/^gobanftp\.sgf=ok$/m, 'sgf --write reports status';
    is $stderr, '', 'sgf --write has no diagnostics';

    ok -f File::Spec->catfile($game_root, qw(projections sgf main.sgf)), 'SGF projection is written';
    ok !-e File::Spec->catfile($game_root, qw(projections oracle board.txt)), 'oracle board is not written';
    ok !-e File::Spec->catfile($game_root, qw(projections oracle verdict.txt)), 'oracle verdict is not written';
};

subtest 'sgf --variations prints fork trees from local and FTP listings' => sub {
    my ($game_root, $game, $events) = _make_game('fork-events.names');
    my $expected = _slurp(File::Spec->catfile($fixture_dir, 'fork-variations.sgf'));

    my ($exit, $stdout, $stderr) = _run_cli('sgf', '--variations', $game_root);

    is $exit, 3, 'local sgf --variations preserves fork exit';
    is $stdout, $expected, 'local sgf --variations prints the variation tree';
    unlike $stdout, qr/^event_set_root=/m, 'local sgf --variations stdout is pure SGF';
    like $stderr, qr/diagnostic .*code=fork/, 'local sgf --variations reports fork diagnostic';
    ok !-e File::Spec->catdir($game_root, 'projections'), 'plain sgf --variations does not write projections';

    local %ENV = %ENV;
    $ENV{GOBANFTP_STORE} = 'ftp';
    $ENV{GOBANFTP_FTP_HOST} = 'mock.example';
    $ENV{GOBANFTP_FTP_USER} = 'tester';
    $ENV{GOBANFTP_FTP_PASSWORD} = 'secret';
    $ENV{GOBANFTP_FTP_ROOT} = 'games';
    $ENV{GOBANFTP_FTP_CLASS} = 'CliSgfFTP';
    $CliSgfFTP::GAME = $game;
    @CliSgfFTP::EVENTS = @$events;
    $CliSgfFTP::LAST = undef;

    my ($ftp_exit, $ftp_stdout, $ftp_stderr) = _run_cli('sgf', '--variations', $game);

    is $ftp_exit, 3, 'FTP sgf --variations preserves fork exit';
    is $ftp_stdout, $expected, 'FTP sgf --variations prints from the event listing';
    unlike $ftp_stdout, qr/^event_set_root=/m, 'FTP sgf --variations stdout is pure SGF';
    like $ftp_stderr, qr/diagnostic .*code=fork/, 'FTP sgf --variations reports fork diagnostic';
    is_deeply $CliSgfFTP::LAST->{listed}, ["games/$game/events"], 'FTP sgf --variations only lists events';
};

subtest 'FTP projection writes fail before event replay' => sub {
    my $game = _read_single(File::Spec->catfile($fixture_dir, 'game.name'));

    local %ENV = %ENV;
    $ENV{GOBANFTP_STORE} = 'ftp';
    $ENV{GOBANFTP_FTP_HOST} = 'mock.example';
    $ENV{GOBANFTP_FTP_USER} = 'tester';
    $ENV{GOBANFTP_FTP_PASSWORD} = 'secret';
    $ENV{GOBANFTP_FTP_ROOT} = 'games';
    $ENV{GOBANFTP_FTP_CLASS} = 'CliSgfFTP';
    $CliSgfFTP::GAME = $game;
    @CliSgfFTP::EVENTS = ('m1.bad');
    $CliSgfFTP::LAST = undef;

    my ($project_exit, $project_stdout, $project_stderr) = _run_cli('project', $game);
    is $project_exit, 4, 'FTP project exits storage before replay';
    is $project_stdout, '', 'FTP project writes no stdout summary';
    like $project_stderr, qr/^storage: project writes local projection files/m,
        'FTP project reports local-only storage boundary';
    is $CliSgfFTP::LAST, undef, 'FTP project does not construct FTP context';

    $CliSgfFTP::LAST = undef;
    my ($sgf_exit, $sgf_stdout, $sgf_stderr) = _run_cli('sgf', '--write', $game);
    is $sgf_exit, 4, 'FTP sgf --write exits storage before replay';
    is $sgf_stdout, '', 'FTP sgf --write writes no stdout summary';
    like $sgf_stderr, qr/^storage: sgf --write writes local projection files/m,
        'FTP sgf --write reports local-only storage boundary';
    is $CliSgfFTP::LAST, undef, 'FTP sgf --write does not construct FTP context';
};

subtest 'FTP projection writes fail before FTP context construction' => sub {
    my $game = _read_single(File::Spec->catfile($fixture_dir, 'game.name'));

    local %ENV = %ENV;
    $ENV{GOBANFTP_STORE} = 'ftp';
    delete @ENV{qw(GOBANFTP_FTP_HOST GOBANFTP_FTP_CLASS)};
    $CliSgfFTP::LAST = undef;

    my ($project_exit, $project_stdout, $project_stderr) = _run_cli('project', $game);
    is $project_exit, 4, 'FTP project exits local-only storage without host config';
    is $project_stdout, '', 'FTP project writes no stdout when rejected before context';
    like $project_stderr, qr/^storage: project writes local projection files/m,
        'FTP project reports local-only boundary before FTP config errors';
    is $CliSgfFTP::LAST, undef, 'FTP project does not construct FTP context';

    my ($sgf_exit, $sgf_stdout, $sgf_stderr) = _run_cli('sgf', '--write', $game);
    is $sgf_exit, 4, 'FTP sgf --write exits local-only storage without host config';
    is $sgf_stdout, '', 'FTP sgf --write writes no stdout when rejected before context';
    like $sgf_stderr, qr/^storage: sgf --write writes local projection files/m,
        'FTP sgf --write reports local-only boundary before FTP config errors';
    is $CliSgfFTP::LAST, undef, 'FTP sgf --write does not construct FTP context';
};

subtest 'project writes rebuildable projection files without changing events' => sub {
    my ($game_root) = _make_game('events.names');
    my $events_dir = File::Spec->catdir($game_root, 'events');
    _write_text(File::Spec->catfile($events_dir, 'README'), "ignored direct non-event\n");
    for my $name (_dir_names($events_dir)) {
        next if $name eq 'README';
        _write_text(File::Spec->catfile($events_dir, $name), "event-byte-secret-for-$name\n");
    }
    _write_text(File::Spec->catfile($game_root, 'sidecar', 'secret.txt'), "sidecar-secret\n");
    _write_text(File::Spec->catfile($game_root, 'tmp', 'secret.part'), "tmp-secret\n");

    my @entries_before = _dir_names($events_dir);
    my @event_names_before = grep { /\A(?:m[0-9]+|a[0-9]+)\./ } @entries_before;
    my %bytes_before = map { $_ => _slurp(File::Spec->catfile($events_dir, $_)) } @entries_before;

    my ($exit, $stdout, $stderr) = _run_cli('project', $game_root);

    is $exit, 0, 'project exits success';
    like $stdout, qr/^gobanftp\.project=ok$/m, 'project reports status';
    like $stdout, qr/^event_set_count=3$/m, 'project reports accepted event-set count';
    like $stdout, qr/^event_set_root=599c00f0614e400274a92ab1c96d09087a53d0d88bd8b0ecba481ac60a1f1461$/m,
        'project reports the accepted event-set root';
    like $stdout, qr/^listing=.*projections.*listing\.txt$/m, 'project reports listing transcript path';
    is $stderr, '', 'project has no diagnostics';
    ok -d File::Spec->catdir($game_root, qw(projections board)), 'board directory is created';
    ok -d File::Spec->catdir($game_root, qw(projections graveyard)), 'graveyard directory is created';
    ok -f File::Spec->catfile($game_root, qw(projections sgf main.sgf)), 'SGF projection is written';
    ok -f File::Spec->catfile($game_root, qw(projections oracle board.txt)), 'oracle board is written';
    ok -f File::Spec->catfile($game_root, qw(projections oracle verdict.txt)), 'oracle verdict is written';
    ok -f File::Spec->catfile($game_root, qw(projections oracle listing.txt)), 'oracle listing transcript is written';

    my $listing = _slurp(File::Spec->catfile($game_root, qw(projections oracle listing.txt)));
    like $listing, qr/\nNLST events\/\n150 Opening data connection for events\/\.\n/,
        'listing projection records the NLST events/ read';
    is_deeply [_listing_transcript_events($listing)], \@event_names_before,
        'listing projection contains sorted event basenames from the events listing';
    unlike $listing, qr/^README$/m, 'listing projection omits direct non-event entries';
    unlike $listing, qr/event-byte-secret|sidecar-secret|tmp-secret/,
        'listing projection does not include event bytes sidecar or tmp bytes';
    _assert_listing_not_sent_contract($listing);

    is_deeply [_dir_names($events_dir)], \@entries_before, 'event directory entries are unchanged';
    for my $name (@entries_before) {
        is _slurp(File::Spec->catfile($events_dir, $name)), $bytes_before{$name}, "event bytes unchanged: $name";
    }
};

subtest 'project writes fork projections then exits conflict' => sub {
    my ($game_root) = _make_game('fork-events.names');
    my $events_dir = File::Spec->catdir($game_root, 'events');
    my @events_before = _dir_names($events_dir);
    my %bytes_before = map { $_ => _slurp(File::Spec->catfile($events_dir, $_)) } @events_before;
    my $expected_variations = _slurp(File::Spec->catfile($fixture_dir, 'fork-variations.sgf'));

    my ($exit, $stdout, $stderr) = _run_cli('project', $game_root);

    is $exit, 3, 'project exits conflict after writing fork projections';
    like $stdout, qr/^gobanftp\.project=fork$/m, 'project reports fork status';
    like $stdout, qr/^event_set_root=02dac396696a1a3806d89819aadf672d02399426106b25bbbd4f36d9dd178b76$/m,
        'project reports the fork event-set root';
    like $stdout, qr/^sgf=.*projections.*main\.sgf$/m, 'project still reports SGF path';
    like $stdout, qr/^board=.*projections.*board\.txt$/m, 'project still reports board path';
    like $stdout, qr/^verdict=.*projections.*verdict\.txt$/m, 'project still reports verdict path';
    like $stdout, qr/^listing=.*projections.*listing\.txt$/m, 'project still reports listing transcript path';
    like $stderr, qr/diagnostic .*code=fork/, 'project reports fork diagnostic';
    is _slurp(File::Spec->catfile($game_root, qw(projections sgf variations.sgf))),
        $expected_variations,
        'variations projection is written for the fork';
    like _slurp(File::Spec->catfile($game_root, qw(projections oracle verdict.txt))),
        qr/^status=fork$/m,
        'verdict projection records fork status';

    is_deeply [_dir_names($events_dir)], \@events_before, 'fork event names are unchanged';
    for my $name (@events_before) {
        is _slurp(File::Spec->catfile($events_dir, $name)), $bytes_before{$name},
            "fork event bytes unchanged: $name";
    }
};

subtest 'validation failures and forks use stable exit codes' => sub {
    my ($invalid_root) = _make_game('invalid-events.names');
    my ($bad_exit, $bad_stdout, $bad_stderr) = _run_cli('verify', $invalid_root);

    is $bad_exit, 2, 'invalid event exits validation failure';
    like $bad_stdout, qr/^gobanftp\.verify=failed$/m, 'invalid verify status is failed';
    like $bad_stdout, qr/^events=2$/m, 'invalid verify reports event-looking listing count';
    like $bad_stdout, qr/^event_set_count=1$/m, 'invalid verify counts only accepted event basenames';
    like $bad_stdout, qr/^event_set_root=ea12e445c106e3de17ae4e124c800f8433f04a0d7e37ab1de4e70a37e1b15d97$/m,
        'invalid verify reports the accepted event-set root';
    like $bad_stderr, qr/diagnostic .*code=parse_event.*name=m1\.bad/, 'parse diagnostic is on stderr';

    my ($project_bad_root) = _make_game('invalid-events.names');
    my ($project_bad_exit, $project_bad_stdout, $project_bad_stderr) = _run_cli('project', $project_bad_root);

    is $project_bad_exit, 2, 'invalid project exits validation failure';
    like $project_bad_stdout, qr/^gobanftp\.project=failed$/m, 'invalid project status is failed';
    like $project_bad_stdout, qr/^event_set_count=1$/m, 'invalid project reports accepted event-set count';
    like $project_bad_stderr, qr/diagnostic .*code=parse_event.*name=m1\.bad/, 'project parse diagnostic is on stderr';
    ok !-e File::Spec->catdir($project_bad_root, 'projections'), 'invalid project does not write projections';

    my ($fork_root) = _make_game('fork-events.names');
    my ($fork_exit, $fork_stdout, $fork_stderr) = _run_cli('verify', $fork_root);

    is $fork_exit, 3, 'fork exits conflict';
    like $fork_stdout, qr/^gobanftp\.verify=fork$/m, 'fork status is reported';
    like $fork_stdout, qr/^event_set_root=02dac396696a1a3806d89819aadf672d02399426106b25bbbd4f36d9dd178b76$/m,
        'fork verify reports the fork event-set root';
    like $fork_stderr, qr/diagnostic .*code=fork/, 'fork diagnostic is on stderr';
};

subtest 'usage storage and script help are stable' => sub {
    local $ENV{GOBANFTP_TEST_SECRET} = 'root';

    my ($no_arg_exit, $no_arg_stdout, $no_arg_stderr) = _run_cli();
    is $no_arg_exit, 1, 'missing command exits usage';
    is $no_arg_stdout, '', 'missing command does not write usage to stdout';
    like $no_arg_stderr, qr/^usage: gobanftp/m, 'missing command usage is on stderr';

    my ($usage_exit, $usage_stdout, $usage_stderr) = _run_cli('bogus');
    is $usage_exit, 1, 'unknown command exits usage';
    is $usage_stdout, '', 'usage diagnostics do not go to stdout for errors';
    like $usage_stderr, qr/^unknown command: bogus/m, 'unknown command is diagnosed';

    my ($storage_exit, undef, $storage_stderr) = _run_cli('verify', File::Spec->catdir(tempdir(CLEANUP => 1), 'missing'));
    is $storage_exit, 4, 'missing game root exits storage failure';
    like $storage_stderr, qr/^storage: game root does not exist:/m, 'storage failure is on stderr';

    my ($blocked_root) = _make_game('events.names');
    _write_text(File::Spec->catfile($blocked_root, 'projections'), "not a directory\n");
    my ($project_exit, undef, $project_stderr) = _run_cli('project', $blocked_root);
    is $project_exit, 4, 'projection write failure exits storage failure';
    like $project_stderr, qr/^storage: mkdir /m, 'projection write failure is a storage diagnostic';

    my ($combo_root) = _make_game('events.names');
    my ($combo_exit, $combo_stdout, $combo_stderr) = _run_cli('sgf', '--write', '--variations', $combo_root);
    is $combo_exit, 1, 'sgf --write --variations exits usage';
    is $combo_stdout, '', 'unsupported sgf write variation does not write stdout';
    like $combo_stderr, qr/^usage: sgf .*--variations/m, 'unsupported sgf write variation explains usage';
    ok !-e File::Spec->catdir($combo_root, 'projections'), 'unsupported sgf write variation writes no projections';

    my ($help_exit, $help_stdout, $help_stderr) = _run_script('--help');
    is $help_exit, 0, 'script help exits success';
    like $help_stdout, qr/^usage: gobanftp/m, 'script help prints usage';
    is $help_stderr, '', 'script help has no diagnostics';
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

sub _run_script {
    my (@args) = @_;

    my $err = gensym;
    my $pid = open3(
        my $in,
        my $out,
        $err,
        $^X,
        "-I$FindBin::Bin/../lib",
        "$FindBin::Bin/../script/gobanftp",
        @args,
    );
    close $in or die "close script stdin: $!";

    my $stdout = do { local $/; <$out> // '' };
    my $stderr = do { local $/; <$err> // '' };
    waitpid $pid, 0;

    return ($? >> 8, $stdout, $stderr);
}

sub _make_game {
    my ($event_file) = @_;

    my $root = tempdir(CLEANUP => 1);
    my $game = _read_single(File::Spec->catfile($fixture_dir, 'game.name'));
    my @events = _read_names(File::Spec->catfile($fixture_dir, $event_file));
    my $game_root = File::Spec->catdir($root, $game);
    my $events_dir = File::Spec->catdir($game_root, 'events');

    make_path($events_dir);
    for my $event (@events) {
        _write_text(File::Spec->catfile($events_dir, $event), "ignored event bytes\n");
    }

    make_path(
        File::Spec->catdir($game_root, 'sidecar'),
        File::Spec->catdir($game_root, 'tmp'),
    );
    _write_text(File::Spec->catfile($game_root, 'sidecar', 'ignored.json'), "{not consensus}\n");
    _write_text(File::Spec->catfile($game_root, 'tmp', 'pending.part'), "ignored tmp\n");

    return ($game_root, $game, \@events);
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

sub _dir_names {
    my ($dir) = @_;

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

sub _write_text {
    my ($path, $text) = @_;

    open my $fh, '>:encoding(UTF-8)', $path or die "write $path: $!";
    print {$fh} $text;
    close $fh or die "close $path: $!";
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

package CliSgfFTP;

use v5.34;
use strict;
use warnings;

our ($GAME, @EVENTS, $LAST);

sub new {
    my ($class) = @_;
    $LAST = bless {
        listed  => [],
        message => '',
    }, $class;
    return $LAST;
}

sub login { return 1 }

sub ls {
    my ($self, $path) = @_;

    $path = _canon($path);
    push @{ $self->{listed} }, $path;

    return map { "$path/$_" } @EVENTS
        if defined($GAME) && $path eq "games/$GAME/events";
    return ();
}

sub message {
    my ($self) = @_;
    return $self->{message};
}

sub _canon {
    my ($path) = @_;

    $path //= '';
    $path =~ s{\A/+}{};
    $path =~ s{/+\z}{};
    return $path;
}
