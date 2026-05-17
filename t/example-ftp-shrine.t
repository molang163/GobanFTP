use v5.34;
use strict;
use warnings;

use File::Find qw(find);
use File::Path qw(make_path remove_tree);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::Listing qw(normalize_listing);
use GobanFTP::Projection qw(render_projection write_projection);
use GobanFTP::Replay qw(replay);
use GobanFTP::Store::Local;

my $game = 'g1.id-ftp-shrine.s9.r-chinese-area-v1.k7500.pb-daemon.pw-pilgrim';
my $fixture_parent = File::Spec->catdir(
    $FindBin::Bin, '..', 'examples', 'fixtures', 'ftp-shrine',
);
my $fixture_root = File::Spec->catdir($fixture_parent, $game);
my $events_dir = File::Spec->catdir($fixture_root, 'events');
my $sidecar_dir = File::Spec->catdir($fixture_root, 'sidecar');
my $projections_dir = File::Spec->catdir($fixture_root, 'projections');

my @events = _dir_names($events_dir);
my @expected_canonical_ids = qw(
    0agr68rv1sp5qi21
    k1kalhibnvic4mno
    p3ige9epnj7c6om0
    tndasisr9c6ihr0j
    eqc92l6ocvbm6mgd
    2m3u03ptk0oqdc91
);

subtest 'shrine fixture exposes protocol surfaces' => sub {
    is scalar(grep { /\Am1[.]/ } @events), 6, 'events contains six move names';
    is scalar(grep { /\Aa1[.]/ } @events), 1, 'events contains one ack name';
    is scalar(grep { $_ eq 'README.md' } @events), 0, 'events has no explanatory direct child';

    my @sidecars = _relative_files($sidecar_dir);
    is_deeply \@sidecars,
        [
            '0agr68rv1sp5qi21.json',
            '2m3u03ptk0oqdc91.json',
            '3vsjo1vqsend0f02.sig',
            'README.md',
        ],
        'sidecar has comments and signature placeholder';

    like _slurp(File::Spec->catfile($fixture_root, 'README.md')),
        qr/Authoritative names:/,
        'game README names the authoritative surface';
    like _slurp(File::Spec->catfile($sidecar_dir, '2m3u03ptk0oqdc91.json')),
        qr/"claimed_action": "play-aa"/,
        'sidecar includes deliberately stale marginalia';
};

subtest 'shrine replays from the events listing' => sub {
    my $result = _replay_from_local_layout($fixture_parent, $game);

    is_deeply [$result->diagnostics], [], 'event listing replays cleanly';
    is_deeply [$result->canonical_ids], \@expected_canonical_ids,
        'canonical line comes from move event names';
    is_deeply [$result->legal_ids], \@expected_canonical_ids,
        'ack is parsed but not counted as a move';

    my $names_by_id = $result->names_by_id;
    like $names_by_id->{'2m3u03ptk0oqdc91'}, qr/[.]play-fe[.]/,
        'filename action wins over stale sidecar action';
    unlike $names_by_id->{'2m3u03ptk0oqdc91'}, qr/play-aa/,
        'sidecar action is not replay input';
};

subtest 'committed projections rebuild from events only' => sub {
    like _slurp(File::Spec->catfile($projections_dir, 'README.md')),
        qr/projections, not truth/i,
        'projection directory declares non-authoritative status';

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

subtest 'sidecar mutation and deletion do not affect replay' => sub {
    my $baseline = replay(
        game_descriptor => $game,
        events          => \@events,
    );
    my $baseline_rendered = render_projection(
        game_descriptor => $game,
        events          => \@events,
        replay_result   => $baseline,
    );

    my $tmp = tempdir(CLEANUP => 1);
    my $tmp_game_root = File::Spec->catdir($tmp, $game);
    my $tmp_events_dir = File::Spec->catdir($tmp_game_root, 'events');
    my $tmp_sidecar_dir = File::Spec->catdir($tmp_game_root, 'sidecar');
    make_path($tmp_events_dir, $tmp_sidecar_dir);

    for my $event (@events) {
        _write_text(
            File::Spec->catfile($tmp_events_dir, $event),
            "poisoned event bytes still ignored\n",
        );
    }
    _write_text(
        File::Spec->catfile($tmp_sidecar_dir, '2m3u03ptk0oqdc91.json'),
        qq|{"claimed_action":"play-aa","consensus_input":true}\n|,
    );
    _write_text(
        File::Spec->catfile($tmp_sidecar_dir, 'unrelated-note.json'),
        qq|{"note":"sidecar directory is not listed for replay"}\n|,
    );

    my $poisoned = _replay_from_local_layout($tmp, $game);
    _same_replay($poisoned, $baseline, 'mutated sidecar replay matches baseline');
    _same_projection($poisoned, $baseline_rendered, 'mutated sidecar projection matches baseline');

    remove_tree($tmp_sidecar_dir);

    my $deleted = _replay_from_local_layout($tmp, $game);
    _same_replay($deleted, $baseline, 'deleted sidecar replay matches baseline');
    _same_projection($deleted, $baseline_rendered, 'deleted sidecar projection matches baseline');
};

done_testing;

sub _replay_from_local_layout {
    my ($root, $descriptor) = @_;

    my $store = GobanFTP::Store::Local->new(root => $root);
    my @listed = normalize_listing($store->list_names("$descriptor/events"));

    return replay(
        game_descriptor => $descriptor,
        events          => \@listed,
    );
}

sub _same_replay {
    my ($got, $expected, $label) = @_;

    is_deeply [$got->diagnostics],   [$expected->diagnostics],   "$label: diagnostics";
    is_deeply [$got->canonical_ids], [$expected->canonical_ids], "$label: canonical ids";
    is_deeply [$got->legal_ids],     [$expected->legal_ids],     "$label: legal ids";
}

sub _same_projection {
    my ($result, $expected_rendered, $label) = @_;

    my $rendered = render_projection(
        game_descriptor => $game,
        events          => \@events,
        replay_result   => $result,
    );

    is $rendered->{sgf_main}, $expected_rendered->{sgf_main}, "$label: main SGF";
    is $rendered->{board},    $expected_rendered->{board},    "$label: board";
    is $rendered->{verdict},  $expected_rendered->{verdict},  "$label: verdict";
    is $rendered->{listing},  $expected_rendered->{listing},  "$label: listing transcript";
}

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
