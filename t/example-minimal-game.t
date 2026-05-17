use v5.34;
use strict;
use warnings;

use File::Find qw(find);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::Projection qw(render_projection write_projection);
use GobanFTP::Replay qw(replay);

my $game = 'g1.id-minimal.s9.r-chinese-area-v1.k7500.pb-alice.pw-bob';
my $fixture_root = File::Spec->catdir(
    $FindBin::Bin, '..', 'examples', 'fixtures', 'minimal-game', $game,
);
my $events_dir      = File::Spec->catdir($fixture_root, 'events');
my $projections_dir = File::Spec->catdir($fixture_root, 'projections');

my @events = _dir_names($events_dir);

subtest 'minimal example replays from events listing' => sub {
    is scalar(@events), 3, 'fixture has two moves and one ack';

    my $result = replay(
        game_descriptor => $game,
        events          => \@events,
    );

    is_deeply [$result->diagnostics], [], 'event listing replays cleanly';
    is_deeply [$result->canonical_ids],
        [qw(f98qai37nace5spg 5ivvsvtid3j6u1pg)],
        'canonical line comes from move event names';
    is_deeply [$result->legal_ids],
        [qw(f98qai37nace5spg 5ivvsvtid3j6u1pg)],
        'ack is available to replay but not a move';
};

subtest 'committed projections are rebuildable from events' => sub {
    like _slurp(File::Spec->catfile($projections_dir, 'README.md')),
        qr/rebuildable projections/i,
        'projection directory declares rebuildable status';

    my $result = replay(
        game_descriptor => $game,
        events          => \@events,
    );
    my $rendered = render_projection(
        game_descriptor => $game,
        events          => \@events,
        replay_result   => $result,
    );

    is _slurp(File::Spec->catfile($projections_dir, qw(sgf main.sgf))),
        $rendered->{sgf_main},
        'main SGF matches rendered projection';
    is _slurp(File::Spec->catfile($projections_dir, qw(sgf variations.sgf))),
        $rendered->{sgf_variations},
        'variation SGF matches rendered projection';
    is _slurp(File::Spec->catfile($projections_dir, qw(oracle board.txt))),
        $rendered->{board},
        'oracle board matches rendered projection';
    is _slurp(File::Spec->catfile($projections_dir, qw(oracle verdict.txt))),
        $rendered->{verdict},
        'oracle verdict matches rendered projection';
    is _slurp(File::Spec->catfile($projections_dir, qw(oracle listing.txt))),
        $rendered->{listing},
        'oracle listing transcript matches rendered projection';

    my $tmp = tempdir(CLEANUP => 1);
    my $tmp_game_root = File::Spec->catdir($tmp, $game);
    my $tmp_events_dir = File::Spec->catdir($tmp_game_root, 'events');
    make_path($tmp_events_dir);
    for my $event (@events) {
        _write_text(
            File::Spec->catfile($tmp_events_dir, $event),
            "different ignored event bytes\n",
        );
    }

    my $written = write_projection(
        game_root       => $tmp_game_root,
        game_descriptor => $game,
        events          => \@events,
        replay_result   => $result,
    );

    ok -f $written->{paths}{main_sgf}, 'projection writer creates main SGF';
    ok -f $written->{paths}{board_current}, 'projection writer creates board/current.txt';
    ok -f $written->{paths}{graveyard_captures}, 'projection writer creates captures projection';
    ok -f $written->{paths}{listing}, 'projection writer creates oracle listing transcript';

    my @fixture_projection_files = grep { $_ ne 'README.md' } _relative_files($projections_dir);
    my @generated_projection_files = _relative_files(File::Spec->catdir($tmp_game_root, 'projections'));

    is_deeply \@generated_projection_files, \@fixture_projection_files,
        'generated projection file set matches committed fixture projections';

    for my $relative (@fixture_projection_files) {
        is _slurp(File::Spec->catfile($tmp_game_root, 'projections', $relative)),
            _slurp(File::Spec->catfile($projections_dir, $relative)),
            "projection content is rebuildable: $relative";
    }
};

done_testing;

sub _dir_names {
    my ($dir) = @_;

    opendir my $dh, $dir or die "opendir $dir: $!";
    my @names = sort grep { $_ ne '.' && $_ ne '..' } readdir $dh;
    closedir $dh or die "closedir $dir: $!";

    return @names;
}

sub _relative_files {
    my ($root) = @_;

    my @files;
    find(
        {
            wanted => sub {
                return if !-f $_;
                push @files, File::Spec->abs2rel($File::Find::name, $root);
            },
            no_chdir => 1,
        },
        $root,
    );

    return sort @files;
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
