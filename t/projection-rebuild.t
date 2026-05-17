use v5.34;
use strict;
use warnings;

use FindBin;
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::Projection qw(render_projection write_projection write_sgf_projection);
use GobanFTP::Replay qw(replay);

my $fixture_dir = "$FindBin::Bin/fixtures/projection";
my $visual_fixture_dir = "$FindBin::Bin/fixtures/projection-visual";

subtest 'render_projection builds SGF board and verdict from replay' => sub {
    my ($game_root, $game, $events) = _make_game($fixture_dir, 'events.names');
    my $result = replay(game_descriptor => $game, events => $events);

    is_deeply $result->{diagnostics}, [], 'fixture replay is clean';

    my $rendered = render_projection(
        game_descriptor => $game,
        events          => $events,
        replay_result   => $result,
    );

    like $rendered->{sgf}, qr/\A\(;/, 'SGF starts with a collection';
    like $rendered->{sgf}, qr/SZ\[3\]/, 'SGF records board size';
    like $rendered->{sgf}, qr/;B\[aa\]/, 'SGF records black play';
    like $rendered->{sgf}, qr/;W\[bb\]/, 'SGF records white play';
    like $rendered->{sgf}, qr/;B\[\]/, 'SGF records pass';
    is $rendered->{sgf}, $rendered->{sgf_main}, 'compat SGF field is the main line';
    like $rendered->{sgf_variations}, qr/;B\[aa\].*;W\[bb\].*;B\[\]/s,
        'variations SGF records the legal line';

    is $rendered->{board}, <<'BOARD', 'oracle board text is deterministic';
game=g1.id-replay.s3.r-chinese-area-v1.k0.pb-alice.pw-bob
size=3
next_color=w
terminal=0
  a b c
3 B . .
2 . W .
1 . . .
BOARD

    is $rendered->{verdict}, <<'VERDICT', 'verdict text is deterministic';
game=g1.id-replay.s3.r-chinese-area-v1.k0.pb-alice.pw-bob
status=ok
canonical_moves=3
legal_moves=3
diagnostics=0
canonical_ids=khjclcui7pejbv3m,bihb3re4k9hlucat,kcvtlonfje163p9q
legal_ids=khjclcui7pejbv3m,bihb3re4k9hlucat,kcvtlonfje163p9q
next_color=w
terminal=0
VERDICT

    like $rendered->{listing}, qr/\AGOFTP\/1 FTP LISTING TRANSCRIPT\n/,
        'listing transcript has a stable header';
    like $rendered->{listing}, qr/\nGame descriptor basename:\n\Q$game\E\n/,
        'listing transcript records the authoritative game descriptor basename';
    like $rendered->{listing}, qr/\nNLST events\/\n150 Opening data connection for events\/\.\n/,
        'listing transcript models an NLST events/ read';
    is_deeply [_listing_transcript_events($rendered->{listing})], [sort @$events],
        'listing transcript prints sorted event basenames';
    _assert_listing_not_sent_contract($rendered->{listing});

    my @reversed_events = reverse @$events;
    my $reversed_rendered = render_projection(
        game_descriptor => $game,
        events          => \@reversed_events,
        replay_result   => $result,
    );
    is_deeply [_listing_transcript_events($reversed_rendered->{listing})], [sort @$events],
        'listing transcript sorts basenames independently of input order';
};

subtest 'write_projection rebuilds projection files without editing events' => sub {
    my ($game_root, $game, $events) = _make_game($fixture_dir, 'events.names');
    my $events_dir = File::Spec->catdir($game_root, 'events');
    my @event_names_before = _dir_names($events_dir);
    my %event_bytes_before = map { $_ => _slurp(File::Spec->catfile($events_dir, $_)) } @event_names_before;

    my $result = replay(game_descriptor => $game, events => $events);
    my $written = write_projection(
        game_root       => $game_root,
        game_descriptor => $game,
        events          => $events,
        replay_result   => $result,
    );

    ok -d $written->{paths}{board_dir}, 'board projection directory is created';
    ok -d $written->{paths}{board_points_dir}, 'board points projection directory is created';
    ok -d $written->{paths}{graveyard_dir}, 'graveyard projection directory is created';
    ok -f $written->{paths}{sgf}, 'main SGF is written';
    ok -f $written->{paths}{variations_sgf}, 'variations SGF is written';
    ok -f $written->{paths}{board_current}, 'board current file is written';
    ok -f $written->{paths}{graveyard_captures}, 'graveyard captures file is written';
    ok -f $written->{paths}{board}, 'oracle board is written';
    ok -f $written->{paths}{verdict}, 'oracle verdict is written';
    ok -f $written->{paths}{listing}, 'oracle listing transcript is written';

    like _slurp($written->{paths}{sgf}), qr/;B\[aa\].*;W\[bb\]/s, 'SGF file contains the canonical line';
    like _slurp($written->{paths}{variations_sgf}), qr/;B\[aa\].*;W\[bb\]/s,
        'variations SGF file contains the legal line';
    like _slurp($written->{paths}{board}), qr/^3 B \. \.$/m, 'board file contains final board';
    is _slurp($written->{paths}{board_current}), _slurp($written->{paths}{board}),
        'board/current.txt matches oracle board projection';
    is _slurp(File::Spec->catfile($written->{paths}{board_points_dir}, 'aa.txt')), <<'POINT',
game=g1.id-replay.s3.r-chinese-area-v1.k0.pb-alice.pw-bob
point=aa
x=0
y=0
row=3
column=a
stone=black
POINT
        'board point file is stable';
    is _slurp($written->{paths}{graveyard_captures}), <<'CAPTURES', 'empty captures file is stable';
game=g1.id-replay.s3.r-chinese-area-v1.k0.pb-alice.pw-bob
captures=0
CAPTURES
    like _slurp($written->{paths}{verdict}), qr/^status=ok$/m, 'verdict file is ok';
    is _slurp($written->{paths}{listing}), $written->{rendered}{listing},
        'listing file matches rendered listing projection';

    is_deeply [_dir_names($events_dir)], \@event_names_before, 'event names are unchanged';
    for my $name (@event_names_before) {
        is _slurp(File::Spec->catfile($events_dir, $name)), $event_bytes_before{$name}, "event bytes unchanged: $name";
    }
};

subtest 'write_sgf_projection writes only the SGF projection' => sub {
    my ($game_root, $game, $events) = _make_game($fixture_dir, 'events.names', stale_projection => 0);
    my $result = replay(game_descriptor => $game, events => $events);

    my $written = write_sgf_projection(
        game_root       => $game_root,
        game_descriptor => $game,
        events          => $events,
        replay_result   => $result,
    );

    ok -f $written->{path}, 'SGF file is written';
    ok !-e File::Spec->catfile($game_root, qw(projections oracle board.txt)), 'board file is not written';
    ok !-e File::Spec->catfile($game_root, qw(projections oracle verdict.txt)), 'verdict file is not written';
};

subtest 'write_projection records board points and captures from canonical steps' => sub {
    my ($game_root, $game, $events) = _make_game($visual_fixture_dir, 'capture-events.names');
    my $result = replay(game_descriptor => $game, events => $events);

    is_deeply $result->{diagnostics}, [], 'capture fixture replay is clean';

    my $written = write_projection(
        game_root       => $game_root,
        game_descriptor => $game,
        events          => $events,
        replay_result   => $result,
    );

    is _slurp($written->{paths}{board_current}), <<'BOARD', 'board/current.txt is deterministic';
game=g1.id-visual.s3.r-chinese-area-v1.k0.pb-alice.pw-bob
size=3
next_color=w
terminal=0
  a b c
3 . B .
2 B B .
1 . . W
BOARD

    is _slurp(File::Spec->catfile($written->{paths}{board_points_dir}, 'aa.txt')), <<'AA', 'captured point is empty';
game=g1.id-visual.s3.r-chinese-area-v1.k0.pb-alice.pw-bob
point=aa
x=0
y=0
row=3
column=a
stone=empty
AA

    is _slurp(File::Spec->catfile($written->{paths}{board_points_dir}, 'cc.txt')), <<'CC', 'occupied point is stable';
game=g1.id-visual.s3.r-chinese-area-v1.k0.pb-alice.pw-bob
point=cc
x=2
y=2
row=1
column=c
stone=white
CC

    is _slurp($written->{paths}{graveyard_captures}), <<'CAPTURES', 'captures come from canonical_steps captures';
game=g1.id-visual.s3.r-chinese-area-v1.k0.pb-alice.pw-bob
captures=1
capture.1.event_id=99p9ikhrgmg8s5h4
capture.1.ply=000005
capture.1.move_color=b
capture.1.captured_color=w
capture.1.point=aa
CAPTURES
};

subtest 'write_projection writes fork projections without editing events' => sub {
    my ($game_root, $game, $events) = _make_game($visual_fixture_dir, 'fork-events.names');
    my $events_dir = File::Spec->catdir($game_root, 'events');
    my @event_names_before = _dir_names($events_dir);
    my %event_bytes_before = map { $_ => _slurp(File::Spec->catfile($events_dir, $_)) } @event_names_before;
    my $result = replay(game_descriptor => $game, events => $events);

    is $result->{fork}{parent_id}, 'bmna9t12upir37k0', 'fixture forks after the root move';

    my $written = write_projection(
        game_root       => $game_root,
        game_descriptor => $game,
        events          => $events,
        replay_result   => $result,
    );

    like _slurp($written->{paths}{main_sgf}), qr/;B\[aa\]\)\n\z/, 'main SGF stops at the fork parent';
    unlike _slurp($written->{paths}{main_sgf}), qr/;W\[(?:bb|cc)\]/, 'main SGF does not choose a fork child';
    like _slurp($written->{paths}{variations_sgf}), qr/;B\[aa\].*;W\[cc\].*;W\[bb\]/s,
        'variations SGF contains both fork children in event-id order';
    like _slurp($written->{paths}{verdict}), qr/^status=fork$/m, 'verdict reports fork status';

    is_deeply [_dir_names($events_dir)], \@event_names_before, 'fork event names are unchanged';
    for my $name (@event_names_before) {
        is _slurp(File::Spec->catfile($events_dir, $name)), $event_bytes_before{$name},
            "fork event bytes unchanged: $name";
    }
};

subtest 'verdict treats fork plus validation failures as validation' => sub {
    my $game = _read_single(File::Spec->catfile($fixture_dir, 'game.name'));
    my $rendered = render_projection(
        game_descriptor => $game,
        events          => [],
        replay_result   => {
            canonical_ids => [],
            legal_ids     => [],
            diagnostics   => [
                { code => 'illegal_move' },
                { code => 'fork' },
            ],
            fork => {
                code      => 'fork',
                parent_id => 'genesis',
                child_ids => [qw(a b)],
            },
        },
    );

    like $rendered->{verdict}, qr/^status=validation$/m, 'validation errors take precedence over fork status';
};

done_testing;

sub _make_game {
    my ($dir, $event_file, %opts) = @_;

    my $root = tempdir(CLEANUP => 1);
    my $game = _read_single(File::Spec->catfile($dir, 'game.name'));
    my @events = _read_names(File::Spec->catfile($dir, $event_file));
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
    if ($opts{stale_projection} // 1) {
        make_path(File::Spec->catdir($game_root, qw(projections oracle)));
        _write_text(File::Spec->catfile($game_root, qw(projections oracle board.txt)), "stale\n");
    }

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

    like $text, qr/\n\Q$not_sent\E\n/, 'SIZE/MDTM/RETR are recorded only as not-sent commands';

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
