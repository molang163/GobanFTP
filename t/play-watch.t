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
use GobanFTP::MovePublisher qw(build_move_name);
use GobanFTP::Store::Local ();

my $GAME = 'g1.id-playwatch.s9.r-chinese-area-v1.k7500.pb-alice.pw-bob';

subtest 'play --once renders a terminal snapshot without writing projections' => sub {
    my (undef, $game_root) = _make_game_root();

    my ($exit, $stdout, $stderr) = _run_cli('play', '--once', $game_root);

    is $exit, 0, 'play --once exits success';
    like $stdout, qr/^gobanftp\.play=ok$/m, 'play status is on stdout';
    like $stdout, qr/^events=0$/m, 'empty event listing is reported';
    like $stdout, qr/^event_set_count=0$/m, 'empty event-set count is reported';
    like $stdout, qr/^event_set_root=341de53d8c29e595f77a7cb0c923e23e308f96122c56211eaa68b191c22f1d80$/m,
        'empty event-set root is reported';
    like $stdout, qr/^turn_color=b$/m, 'black is first to play';
    like $stdout, qr/^turn_player=alice$/m, 'black player is reported';
    like $stdout, qr/^worldline\.status=main$/m, 'clean worldline is reported';
    like $stdout, qr/^size=9$/m, 'board size is rendered';
    like $stdout, qr/^terminal=0$/m, 'non-terminal state is rendered';
    is $stderr, '', 'play --once has no diagnostics';
    is_deeply [_event_names($game_root)], [], 'events are unchanged';
    ok !-e File::Spec->catdir($game_root, 'projections'), 'play --once does not write projections';
};

subtest 'play --move publishes one move and renders the updated board' => sub {
    my (undef, $game_root) = _make_game_root();

    my ($exit, $stdout, $stderr) = _run_cli('play', '--move', 'aa', '--nonce', 'p1', $game_root);

    is $exit, 0, 'play --move exits success';
    like $stdout, qr/^event=m1\.p000001\.b\.play-aa\.pa-genesis\.by-alice\.n-p1\.h-[0-9a-v]{16}$/m,
        'published event is reported';
    like $stdout, qr/^gobanftp\.play=ok$/m, 'snapshot status is reported';
    like $stdout, qr/^events=1$/m, 'snapshot sees one event';
    like $stdout, qr/^event_set_count=1$/m, 'snapshot reports one accepted event';
    like $stdout, qr/^event_set_root=9fc9fada3fe9667b515dc90d117c5bea9b3537337236059ffa526872cf62a75f$/m,
        'post-move event-set root is reported';
    like $stdout, qr/^canonical_moves=1$/m, 'one canonical move is shown';
    like $stdout, qr/^turn_color=w$/m, 'turn advances to white';
    like $stdout, qr/^turn_player=bob$/m, 'white player is reported';
    like $stdout, qr/^worldline\.status=main$/m, 'worldline remains clean';
    like $stdout, qr/^9 B \. \. \. \. \. \. \. \.$/m, 'board shows the black stone';
    is $stderr, '', 'play --move has no diagnostics';

    my ($event) = $stdout =~ /^event=(m1\..+)$/m;
    ok -f File::Spec->catfile($game_root, 'events', $event), 'event file was created';
    is -s File::Spec->catfile($game_root, 'events', $event), 0, 'event file is zero bytes';
    ok !-e File::Spec->catdir($game_root, 'projections'), 'play --move does not write projections';
};

subtest 'play --move renders the post-publish fork snapshot' => sub {
    my (undef, $game_root) = _make_game_root();
    my ($fork_event, $fork_id) = build_move_name(
        game_descriptor => $GAME,
        ply             => 1,
        color           => 'b',
        action          => 'play-bb',
        parent_id       => 'genesis',
        player          => 'alice',
        nonce           => 'race',
    );

    my $published_once = 0;
    my $original_publish = \&GobanFTP::Store::Local::publish_event_name;

    my ($exit, $stdout, $stderr);
    {
        no warnings 'redefine';
        local *GobanFTP::Store::Local::publish_event_name = sub {
            my ($self, $game_root_arg, $event_name) = @_;

            my $ok = $original_publish->(@_);
            if (!$published_once++) {
                $original_publish->($self, $game_root_arg, $fork_event);
            }
            return $ok;
        };

        ($exit, $stdout, $stderr) = _run_cli('play', '--move', 'aa', '--nonce', 'p1', $game_root);
    }

    is $exit, 3, 'post-publish fork exits conflict';
    like $stdout, qr/^event=m1\.p000001\.b\.play-aa\.pa-genesis\.by-alice\.n-p1\.h-([0-9a-v]{16})$/m,
        'published event is still reported';
    my ($published_id) = $stdout =~ /^event_id=([0-9a-v]{16})$/m;
    ok defined($published_id), 'published event id is reported';
    like $stdout, qr/^gobanftp\.play=fork$/m, 'fork snapshot status is reported';
    like $stdout, qr/^event_set_count=2$/m, 'post-publish fork reports two accepted events';
    like $stdout, qr/^event_set_root=b682bdd142c6c64bad29c53dc0642c2a0082abf02b9c135d42271be01f78f6d2$/m,
        'post-publish fork event-set root is reported';
    like $stdout, qr/^worldline\.status=fork$/m, 'post-publish worldline is rendered as fork';
    like $stdout, qr/^worldline\.fork\.parent_id=genesis$/m, 'fork parent is rendered';
    like $stdout, qr/^worldline\.fork\.child_ids=\Q@{[join ',', sort ($published_id, $fork_id)]}\E$/m,
        'both fork children are rendered in event-id order';
    like $stdout, qr/^9 \. \. \. \. \. \. \. \. \.$/m, 'fork snapshot renders the parent board';
    like $stderr, qr/diagnostic .*code=fork/, 'fork diagnostic is reported';
    is_deeply [_event_names($game_root)], [sort grep { defined } ($fork_event, ($stdout =~ /^event=(m1\..+)$/m))],
        'both published and racing fork events are visible';
};

subtest 'interactive play keeps running after an invalid candidate move' => sub {
    my (undef, $game_root) = _make_game_root();

    my ($exit, $stdout, $stderr) = _run_cli_stdin("zz\nq\n", 'play', $game_root);

    is $exit, 0, 'interactive play exits after q';
    like $stdout, qr/^gobanftp\.play=ok$/m, 'initial snapshot is rendered';
    like $stdout, qr/^gobanftp\.play=failed$/m, 'invalid candidate is reported';
    is scalar(() = $stdout =~ /^event_set_root=/mg), 1,
        'invalid candidate does not print an event-set root for the unpublished candidate';
    like $stdout, qr/^event=m1\.p000001\.b\.play-zz\.pa-genesis\.by-alice\.n-[a-z0-9_-]+\.h-[0-9a-v]{16}$/m,
        'candidate event name is reported without publishing';
    like $stderr, qr/diagnostic .*code=parse_event.*error=move\.point_bounds/, 'candidate diagnostic is reported';
    like $stderr, qr/move> .*move> /s, 'prompt returns after the candidate diagnostic';
    is_deeply [_event_names($game_root)], [], 'invalid candidate is not published';
};

subtest 'watch --max-polls renders a bounded listing-first snapshot' => sub {
    my (undef, $game_root) = _make_game_root();
    my ($event) = build_move_name(
        game_descriptor => $GAME,
        ply             => 1,
        color           => 'b',
        action          => 'play-aa',
        parent_id       => 'genesis',
        player          => 'alice',
        nonce           => 'w1',
    );
    _write_text(File::Spec->catfile($game_root, 'events', $event), 'ignored bytes');

    my ($exit, $stdout, $stderr) = _run_cli('watch', '--max-polls', '1', '--interval', '0', $game_root);

    is $exit, 0, 'bounded watch exits success';
    like $stdout, qr/^gobanftp\.watch=ok$/m, 'watch status is on stdout';
    like $stdout, qr/^snapshot=1$/m, 'snapshot number is reported';
    like $stdout, qr/^events=1$/m, 'watch sees the listing';
    like $stdout, qr/^event_set_count=1$/m, 'watch reports one accepted event';
    like $stdout, qr/^event_set_root=c09570907a06b5a77ef9539850e7b0050680af9d319ed9482c1d9feba0294434$/m,
        'watch reports the event-set root';
    like $stdout, qr/^turn_color=w$/m, 'watch renders the next turn';
    is $stderr, '', 'watch has no diagnostics';
    is_deeply [_event_names($game_root)], [$event], 'watch does not change events';
    ok !-e File::Spec->catdir($game_root, 'projections'), 'watch does not write projections';
};

subtest 'watch --compact keeps live observation recordable without rendering a board' => sub {
    my (undef, $game_root) = _make_game_root();
    my ($event) = build_move_name(
        game_descriptor => $GAME,
        ply             => 1,
        color           => 'b',
        action          => 'play-aa',
        parent_id       => 'genesis',
        player          => 'alice',
        nonce           => 'compact1',
    );
    _write_text(File::Spec->catfile($game_root, 'events', $event), 'body bytes ignored');
    _write_text(File::Spec->catfile($game_root, 'tmp', 'poison'), 'tmp ignored');
    _write_text(File::Spec->catfile($game_root, 'sidecar', 'poison.json'), '{"ignored":true}');

    my ($exit, $stdout, $stderr) = _run_cli(
        'watch',
        '--live',
        '--compact',
        '--max-polls',
        '1',
        '--interval',
        '0',
        $game_root,
    );

    is $exit, 0, 'compact live watch exits success';
    like $stdout, qr/^gobanftp\.watch=ok$/m, 'compact watch reports status';
    like $stdout, qr/^live=1$/m, 'compact watch keeps live marker';
    like $stdout, qr/^compact=1$/m, 'compact watch marks compact output';
    like $stdout, qr/^observer\.delta_events=1$/m, 'compact watch reports event delta';
    like $stdout, qr/^observer\.event_set_root_changed=0$/m, 'first compact snapshot has no previous root change';
    like $stdout, qr/^event_set_count=1$/m, 'compact watch reports event-set count';
    like $stdout, qr/^worldline\.status=main$/m, 'compact watch still reports worldline';
    unlike $stdout, qr/^  a b c d e f g h i$/m, 'compact watch omits board rendering';
    unlike $stdout, qr/body bytes ignored|tmp ignored|poison/, 'compact watch does not read sidecar tmp or body bytes';
    is $stderr, '', 'compact watch has no diagnostics';
};

subtest 'watch exits on a fork by default' => sub {
    my (undef, $game_root) = _make_game_root();
    my ($left, $left_id) = build_move_name(
        game_descriptor => $GAME,
        ply             => 1,
        color           => 'b',
        action          => 'play-aa',
        parent_id       => 'genesis',
        player          => 'alice',
        nonce           => 'wf1',
    );
    my ($right, $right_id) = build_move_name(
        game_descriptor => $GAME,
        ply             => 1,
        color           => 'b',
        action          => 'play-bb',
        parent_id       => 'genesis',
        player          => 'alice',
        nonce           => 'wf2',
    );
    _write_text(File::Spec->catfile($game_root, 'events', $left), '');
    _write_text(File::Spec->catfile($game_root, 'events', $right), '');

    my ($exit, $stdout, $stderr) = _run_cli('watch', '--max-polls', '2', '--interval', '0', $game_root);

    is $exit, 3, 'plain watch exits on fork';
    like $stdout, qr/^gobanftp\.watch=fork$/m, 'fork status is rendered';
    like $stdout, qr/^snapshot=1$/m, 'first snapshot is rendered';
    unlike $stdout, qr/^snapshot=2$/m, 'plain watch stops before the next snapshot';
    like $stdout, qr/^worldline\.fork\.child_ids=\Q@{[join ',', sort ($left_id, $right_id)]}\E$/m,
        'fork children are visible';
    like $stderr, qr/diagnostic .*code=fork/, 'fork diagnostic is reported';
};

subtest 'watch --live keeps polling after a visible fork' => sub {
    my (undef, $game_root) = _make_game_root();
    my ($left, $left_id) = build_move_name(
        game_descriptor => $GAME,
        ply             => 1,
        color           => 'b',
        action          => 'play-aa',
        parent_id       => 'genesis',
        player          => 'alice',
        nonce           => 'liveleft',
    );
    my ($right, $right_id) = build_move_name(
        game_descriptor => $GAME,
        ply             => 1,
        color           => 'b',
        action          => 'play-bb',
        parent_id       => 'genesis',
        player          => 'alice',
        nonce           => 'liveright',
    );
    _write_text(File::Spec->catfile($game_root, 'events', $left), '');
    _write_text(File::Spec->catfile($game_root, 'events', $right), '');

    my ($exit, $stdout, $stderr) = _run_cli('watch', '--live', '--max-polls', '2', '--interval', '0', $game_root);

    is $exit, 0, 'live watch exits success after bounded polls';
    is scalar(() = $stdout =~ /^gobanftp\.watch=fork$/mg), 2, 'fork status is rendered for both snapshots';
    is scalar(() = $stdout =~ /^live=1$/mg), 2, 'live mode is explicit in every snapshot';
    like $stdout, qr/^snapshot=1$/m, 'first snapshot is rendered';
    like $stdout, qr/^snapshot=2$/m, 'second snapshot is rendered after the fork';
    like $stdout, qr/^worldline\.fork\.child_ids=\Q@{[join ',', sort ($left_id, $right_id)]}\E$/m,
        'live watch keeps fork children visible';
    is scalar(() = $stderr =~ /diagnostic .*code=fork/g), 2, 'fork diagnostic is reported for both snapshots';
    is_deeply [_event_names($game_root)], [sort ($left, $right)], 'live watch does not change events';
    ok !-e File::Spec->catdir($game_root, 'projections'), 'live watch does not write projections';
};

subtest 'play --live is a read-only live-over-listing observer' => sub {
    my (undef, $game_root) = _make_game_root();
    my ($event) = build_move_name(
        game_descriptor => $GAME,
        ply             => 1,
        color           => 'b',
        action          => 'play-aa',
        parent_id       => 'genesis',
        player          => 'alice',
        nonce           => 'plive',
    );
    _write_text(File::Spec->catfile($game_root, 'events', $event), '');

    my ($exit, $stdout, $stderr) = _run_cli('play', '--live', '--max-polls', '1', '--interval', '0', $game_root);

    is $exit, 0, 'play --live exits success after a bounded poll';
    like $stdout, qr/^gobanftp\.play=ok$/m, 'play live uses play snapshots';
    like $stdout, qr/^snapshot=1$/m, 'play live reports the snapshot number';
    like $stdout, qr/^live=1$/m, 'play live marks live mode';
    like $stdout, qr/^events=1$/m, 'play live sees the listing';
    like $stdout, qr/^turn_color=w$/m, 'play live renders the next turn';
    is $stderr, '', 'play live has no diagnostics on a clean listing';
    is_deeply [_event_names($game_root)], [$event], 'play live does not publish';
    ok !-e File::Spec->catdir($game_root, 'projections'), 'play live does not write projections';
};

subtest 'play --once reports forks as worldline state' => sub {
    my (undef, $game_root) = _make_game_root();
    my ($left, $left_id) = build_move_name(
        game_descriptor => $GAME,
        ply             => 1,
        color           => 'b',
        action          => 'play-aa',
        parent_id       => 'genesis',
        player          => 'alice',
        nonce           => 'f1',
    );
    my ($right, $right_id) = build_move_name(
        game_descriptor => $GAME,
        ply             => 1,
        color           => 'b',
        action          => 'play-bb',
        parent_id       => 'genesis',
        player          => 'alice',
        nonce           => 'f2',
    );
    _write_text(File::Spec->catfile($game_root, 'events', $left), '');
    _write_text(File::Spec->catfile($game_root, 'events', $right), '');

    my ($exit, $stdout, $stderr) = _run_cli('play', '--once', $game_root);

    is $exit, 3, 'fork exits conflict';
    like $stdout, qr/^gobanftp\.play=fork$/m, 'fork status is reported';
    like $stdout, qr/^event_set_count=2$/m, 'fork reports two accepted events';
    like $stdout, qr/^event_set_root=8c11f06c0e3be5507f7a62c2837fac1c7e75366ee1a60699c929635288b457ea$/m,
        'fork event-set root is reported';
    like $stdout, qr/^worldline\.status=fork$/m, 'worldline fork status is reported';
    like $stdout, qr/^worldline\.fork\.parent_id=genesis$/m, 'fork parent is reported';
    like $stdout, qr/^worldline\.fork\.child_ids=\Q@{[join ',', sort ($left_id, $right_id)]}\E$/m,
        'fork children are reported in event-id order';
    like $stderr, qr/diagnostic .*code=fork/, 'fork diagnostic is reported';
    is_deeply [_event_names($game_root)], [sort ($left, $right)], 'fork event names are unchanged';
};

subtest 'play --ack publishes an ack and renders an ack-assisted snapshot' => sub {
    my (undef, $game_root) = _make_game_root();
    my ($left, $left_id) = build_move_name(
        game_descriptor => $GAME,
        ply             => 1,
        color           => 'b',
        action          => 'play-aa',
        parent_id       => 'genesis',
        player          => 'alice',
        nonce           => 'left',
    );
    my ($right, $right_id) = build_move_name(
        game_descriptor => $GAME,
        ply             => 1,
        color           => 'b',
        action          => 'play-bb',
        parent_id       => 'genesis',
        player          => 'alice',
        nonce           => 'right',
    );
    _write_text(File::Spec->catfile($game_root, 'events', $left), '');
    _write_text(File::Spec->catfile($game_root, 'events', $right), '');

    my ($exit, $stdout, $stderr) = _run_cli('play', '--ack', $left_id, '--nonce', 'ackleft', $game_root);

    is $exit, 0, 'play --ack exits success when the ack resolves the fork';
    like $stdout, qr/^event=a1\.t-\Q$left_id\E\.by-bob\.n-ackleft\.h-[0-9a-v]{16}$/m,
        'published ack event is reported';
    like $stdout, qr/^gobanftp\.play=ok$/m, 'ack-assisted snapshot status is ok';
    like $stdout, qr/^events=3$/m, 'snapshot sees both fork moves and the ack';
    like $stdout, qr/^event_set_count=3$/m, 'ack-assisted snapshot reports three accepted events';
    like $stdout, qr/^event_set_root=ec8872c7091745f06d760e4f971a2d87af244fcbda04d19bc7957a48c3bb8445$/m,
        'ack-assisted snapshot reports the event-set root';
    like $stdout, qr/^canonical_moves=1$/m, 'ack-assisted snapshot chooses one canonical move';
    like $stdout, qr/^turn_color=w$/m, 'turn advances after the chosen black move';
    like $stdout, qr/^turn_player=bob$/m, 'white player is reported after recovery';
    like $stdout, qr/^worldline\.status=main$/m, 'ack-assisted worldline is recovered';
    like $stdout, qr/^worldline\.canonical_ids=\Q$left_id\E$/m, 'chosen child is canonical';
    like $stdout, qr/^9 B \. \. \. \. \. \. \. \.$/m, 'board renders the acked fork child';
    is $stderr, '', 'resolved ack-assisted snapshot has no diagnostics';

    my ($ack) = $stdout =~ /^event=(a1\..+)$/m;
    is_deeply [_event_names($game_root)], [sort ($left, $right, $ack)], 'ack event is published beside fork moves';
    ok !-e File::Spec->catdir($game_root, 'projections'), 'play --ack does not write projections';

    my ($once_exit, $once_stdout, $once_stderr) = _run_cli('play', '--once', $game_root);
    is $once_exit, 3, 'plain play --once remains conservative on the same listing';
    like $once_stdout, qr/^event_set_root=ec8872c7091745f06d760e4f971a2d87af244fcbda04d19bc7957a48c3bb8445$/m,
        'plain conservative replay sees the same event-set root';
    like $once_stdout, qr/^worldline\.status=fork$/m, 'plain play still reports the fork';
    like $once_stderr, qr/diagnostic .*code=fork/, 'plain play emits fork diagnostic';
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
    return _run_cli_stdin('', @args);
}

sub _run_cli_stdin {
    my ($stdin, @args) = @_;

    my ($stdout, $stderr) = ('', '');
    open my $in_fh, '<', \$stdin or die "open stdin scalar: $!";
    open my $out_fh, '>', \$stdout or die "open stdout scalar: $!";
    open my $err_fh, '>', \$stderr or die "open stderr scalar: $!";

    my $exit;
    {
        local *STDIN  = $in_fh;
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
