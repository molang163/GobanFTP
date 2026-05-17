use v5.34;
use strict;
use warnings;

use File::Path qw(make_path remove_tree);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::Event qw(event_id from_name);
use GobanFTP::Listing qw(normalize_listing);
use GobanFTP::Projection qw(render_projection write_projection);
use GobanFTP::Replay qw(replay);
use GobanFTP::Store::Local;

my $game = 'g1.id-ftp-race-shrine.s9.r-chinese-area-v1.k7500.pb-daemon.pw-pilgrim';
my $fixture_parent = File::Spec->catdir(
    $FindBin::Bin, '..', 'examples', 'fixtures', 'ftp-race-shrine',
);
my $fixture_root = File::Spec->catdir($fixture_parent, $game);
my $events_dir = File::Spec->catdir($fixture_root, 'events');
my $sidecar_dir = File::Spec->catdir($fixture_root, 'sidecar');
my $projections_dir = File::Spec->catdir($fixture_root, 'projections');

my $root_id  = 'hihat4p8r6gaeuts';
my $left_id  = 'ps9v3kftvp5v1gl5';
my $right_id = 'o00qmn6v8j683ds6';
my $ack_id   = '7d3cjn514h885jq1';

my @events = _dir_names($events_dir);
my @expected_events = sort
    "m1.p000001.b.play-dd.pa-genesis.by-daemon.n-root1.h-$root_id",
    "m1.p000002.w.play-ee.pa-$root_id.by-pilgrim.n-raceleft.h-$left_id",
    "m1.p000002.w.play-ff.pa-$root_id.by-pilgrim.n-raceright.h-$right_id",
    "a1.t-$left_id.by-daemon.n-ackleft.h-$ack_id";

subtest 'race shrine exposes a fork in event basenames' => sub {
    is_deeply \@events, \@expected_events, 'events directory has only race event names';
    is scalar(grep { /\Am1[.]/ } @events), 3, 'events contains three move names';
    is scalar(grep { /\Aa1[.]/ } @events), 1, 'events contains one ack name';
    is scalar(grep { $_ eq 'README.md' } @events), 0, 'events has no explanatory direct child';

    for my $name (@events) {
        my ($event, $error) = from_name($name, game_descriptor => $game);
        is $error, undef, "event id verifies: $name";
        like $name, qr/[.]h-\Q@{[event_id($event)]}\E\z/, "visible id matches parser: $name";
    }

    like _slurp(File::Spec->catfile($fixture_root, 'README.md')),
        qr/Conservative replay stops/,
        'game README explains conservative fork behavior';
    like _slurp(File::Spec->catfile($sidecar_dir, 'README.md')),
        qr/not sidecar truth/i,
        'sidecar README keeps recovery advisory';
};

subtest 'conservative replay reports the race fork' => sub {
    my $result = _replay_from_local_layout($fixture_parent, $game);

    is_deeply [map { $_->{code} } $result->diagnostics], ['fork'], 'only diagnostic is fork';
    is_deeply [$result->canonical_ids], [$root_id], 'canonical line stops at common parent';
    is_deeply [$result->legal_ids], [$root_id, $right_id, $left_id], 'both race children remain legal moves';

    my $fork = $result->fork;
    is $fork->{parent_id}, $root_id, 'fork parent is the shared parent';
    is_deeply $fork->{child_ids}, [sort ($left_id, $right_id)], 'fork children are deterministic';

    my $names_by_id = $result->names_by_id;
    like $names_by_id->{$left_id},  qr/[.]play-ee[.]/, 'left race child is visible by name';
    like $names_by_id->{$right_id}, qr/[.]play-ff[.]/, 'right race child is visible by name';
};

subtest 'ack-assisted replay is explicit and chooses the acked child' => sub {
    my $result = replay(
        game_descriptor => $game,
        events          => \@events,
        policy          => 'ack-assisted',
    );

    is_deeply [$result->diagnostics], [], 'ack-assisted replay resolves the fork without diagnostics';
    is $result->fork, undef, 'resolved fork is not reported';
    is_deeply [$result->canonical_ids], [$root_id, $left_id], 'acked child becomes canonical only under explicit policy';
    is_deeply [$result->legal_ids], [$root_id, $right_id, $left_id], 'unacked child remains a legal branch';
    is_deeply [$result->ack_assisted_choices],
        [{
            parent_id => $root_id,
            child_id  => $left_id,
            ack_ids   => [$ack_id],
        }],
        'choice records the ack that resolved the fork';

    my $state = $result->final_state;
    is $state->{board}->stone_at('dd'), 1, 'common parent stone remains black';
    is $state->{board}->stone_at('ee'), 2, 'acked child stone is committed';
    is $state->{board}->stone_at('ff'), 0, 'unacked child is not committed';
};

subtest 'committed conservative projections are rebuildable from events' => sub {
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
        'main SGF matches conservative projection';
    like $rendered->{sgf_main}, qr/;B\[dd\]\)\n\z/, 'main SGF stops at fork parent';
    unlike $rendered->{sgf_main}, qr/;W\[(?:ee|ff)\]/, 'main SGF does not choose a fork child';

    is _slurp(File::Spec->catfile($projections_dir, qw(sgf variations.sgf))),
        $rendered->{sgf_variations},
        'variations SGF matches conservative projection';
    like $rendered->{sgf_variations}, qr/;B\[dd\].*;W\[ff\].*;W\[ee\]/s,
        'variations SGF contains both race children';

    is _slurp(File::Spec->catfile($projections_dir, qw(oracle board.txt))),
        $rendered->{board},
        'oracle board matches rendered projection';
    is _slurp(File::Spec->catfile($projections_dir, qw(oracle verdict.txt))),
        $rendered->{verdict},
        'oracle verdict matches rendered projection';
    like $rendered->{verdict}, qr/^status=fork$/m, 'verdict remains conservative fork';
    is _slurp(File::Spec->catfile($projections_dir, qw(oracle listing.txt))),
        $rendered->{listing},
        'oracle listing transcript matches rendered projection';
    is_deeply [_listing_transcript_events($rendered->{listing})], \@events,
        'listing transcript prints sorted event basenames';
    _assert_listing_not_sent_contract($rendered->{listing});
    is _slurp(File::Spec->catfile($projections_dir, qw(graveyard captures.txt))),
        $rendered->{graveyard_captures},
        'graveyard projection matches rendered projection';
    is _slurp(File::Spec->catfile($projections_dir, qw(board current.txt))),
        $rendered->{board_current},
        'board/current.txt matches rendered board';

    ok !-e File::Spec->catfile($projections_dir, qw(oracle ack-assisted.txt)),
        'race shrine does not add an ack-assisted projection';

    my $tmp = tempdir(CLEANUP => 1);
    my $tmp_game_root = File::Spec->catdir($tmp, $game);
    my $tmp_events_dir = File::Spec->catdir($tmp_game_root, 'events');
    make_path($tmp_events_dir);
    for my $event (@events) {
        _write_text(File::Spec->catfile($tmp_events_dir, $event), "different ignored event bytes\n");
    }

    my $written = write_projection(
        game_root       => $tmp_game_root,
        game_descriptor => $game,
        events          => \@events,
        replay_result   => $result,
    );

    for my $key (qw(main_sgf variations_sgf board_current graveyard_captures board verdict listing)) {
        ok -f $written->{paths}{$key}, "projection writer creates $key";
    }
    ok !-e File::Spec->catfile($tmp_game_root, qw(projections oracle ack-assisted.txt)),
        'projection writer does not create ack-assisted projection';
};

subtest 'mutating sidecar projections tmp and file bytes does not affect replay' => sub {
    my $baseline = replay(
        game_descriptor => $game,
        events          => \@events,
    );
    my $baseline_ack = replay(
        game_descriptor => $game,
        events          => \@events,
        policy          => 'ack-assisted',
    );

    my $tmp = tempdir(CLEANUP => 1);
    my $tmp_game_root = File::Spec->catdir($tmp, $game);
    my $tmp_events_dir = File::Spec->catdir($tmp_game_root, 'events');
    make_path(
        $tmp_events_dir,
        File::Spec->catdir($tmp_game_root, 'sidecar'),
        File::Spec->catdir($tmp_game_root, 'projections', 'oracle'),
        File::Spec->catdir($tmp_game_root, 'tmp'),
    );

    for my $event (@events) {
        _write_text(File::Spec->catfile($tmp_events_dir, $event), "poisoned bytes ignored\n");
    }
    _write_text(File::Spec->catfile($tmp_game_root, 'sidecar', 'claim.json'), qq|{"winner":"right"}\n|);
    _write_text(File::Spec->catfile($tmp_game_root, qw(projections oracle verdict.txt)), "status=ok\n");
    _write_text(File::Spec->catfile($tmp_game_root, 'tmp', 'race.part'), "right child arrived last\n");

    my $poisoned = _replay_from_local_layout($tmp, $game);
    _same_replay($poisoned, $baseline, 'poisoned non-consensus surfaces keep conservative fork');

    my @listed = _listed_events($tmp, $game);
    my $poisoned_ack = replay(
        game_descriptor => $game,
        events          => \@listed,
        policy          => 'ack-assisted',
    );
    _same_replay($poisoned_ack, $baseline_ack, 'poisoned non-consensus surfaces keep ack-assisted choice');

    remove_tree(File::Spec->catdir($tmp_game_root, 'sidecar'));
    remove_tree(File::Spec->catdir($tmp_game_root, 'projections'));
    remove_tree(File::Spec->catdir($tmp_game_root, 'tmp'));

    my $deleted = _replay_from_local_layout($tmp, $game);
    _same_replay($deleted, $baseline, 'deleted non-consensus surfaces keep conservative fork');
};

done_testing;

sub _replay_from_local_layout {
    my ($root, $descriptor) = @_;
    my @listed = _listed_events($root, $descriptor);

    return replay(
        game_descriptor => $descriptor,
        events          => \@listed,
    );
}

sub _listed_events {
    my ($root, $descriptor) = @_;

    my $store = GobanFTP::Store::Local->new(root => $root);
    return normalize_listing($store->list_names("$descriptor/events"));
}

sub _same_replay {
    my ($got, $expected, $label) = @_;

    is_deeply [$got->diagnostics],   [$expected->diagnostics],   "$label: diagnostics";
    is_deeply [$got->canonical_ids], [$expected->canonical_ids], "$label: canonical ids";
    is_deeply [$got->legal_ids],     [$expected->legal_ids],     "$label: legal ids";
    is_deeply $got->fork,            $expected->fork,            "$label: fork";
}

sub _listing_transcript_events {
    my ($listing) = @_;

    my @events;
    for my $line (split /\n/, $listing) {
        push @events, $line if $line =~ /\A(?:m1|a1)[.]/;
    }
    return @events;
}

sub _assert_listing_not_sent_contract {
    my ($listing) = @_;

    like $listing, qr/\nCommands not sent by GOFTP\/1 replay:\n\nSIZE events\/<event-basename>\nMDTM events\/<event-basename>\nRETR events\/<event-basename>\n/,
        'listing transcript declares SIZE MDTM RETR as not sent by replay';
    unlike $listing, qr/\n(?:213|150 Opening data connection\.)/s,
        'listing transcript does not include metadata or RETR command responses outside NLST';
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
