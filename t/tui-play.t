use v5.34;
use strict;
use warnings;

use FindBin;
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use IPC::Open3 qw(open3);
use JSON::PP;
use Symbol qw(gensym);
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::Auth::HMACKey qw(generate_hmac_key_record write_hmac_key_file);
use GobanFTP::Auth::PublishToken qw(sign_publish_token);
use GobanFTP::Board;
use GobanFTP::CLI;
use GobanFTP::MovePublisher qw(build_move_name);
use GobanFTP::TUI::Play qw(
    apply_tui_event
    board_layout
    feed_tui_input
    hit_test_board
    new_input_state
    point_for_cursor
    render_play_frame
    run_play_tui
);

my $root = "$FindBin::Bin/..";
my $module_path = "$root/lib/GobanFTP/TUI/Play.pm";
my $GAME = 'g1.id-tuitest.s9.r-chinese-area-v1.k7500.pb-alice.pw-bob';

subtest 'TUI adapter has no consensus imports' => sub {
    my $source = _slurp($module_path);
    my @gobanftp_uses = $source =~ /^\s*use\s+(GobanFTP::[A-Za-z0-9_:]+)\b/mg;

    is_deeply \@gobanftp_uses, [], 'TUI imports no GobanFTP consensus modules';
    unlike $source,
        qr/\b(?:replay|witness_for_listing|event_set_root_result|render_projection|publish_event_name|normalize_listing)\b/,
        'TUI source does not name consensus or store mutation entry points';
};

subtest 'keyboard and SGR mouse input are parsed incrementally' => sub {
    my $state = new_input_state();

    is_deeply [feed_tui_input($state, "\e[")], [], 'partial CSI waits';
    my @right = feed_tui_input($state, 'C');
    is_deeply \@right, [{ type => 'move_cursor', dx => 1, dy => 0 }],
        'split right arrow is parsed';

    my @plain = feed_tui_input($state, "j\npRq");
    is_deeply [map { $_->{type} } @plain], [qw(move_cursor submit action action quit)],
        'plain keys become cursor, submit, action, and quit events';
    is $plain[0]{dy}, 1, 'j moves down';
    is $plain[2]{action}, 'pass', 'p maps to pass';
    is $plain[3]{action}, 'resign', 'R maps to resign';

    my $mouse_state = new_input_state();
    is_deeply [feed_tui_input($mouse_state, "\e[<0;")], [], 'partial mouse sequence waits';
    my @mouse = feed_tui_input($mouse_state, '5;7M');
    is_deeply \@mouse, [{ type => 'mouse_press', button => 0, col => 5, row => 7 }],
        'split SGR mouse press is parsed';
    is_deeply [feed_tui_input(new_input_state(), "\e[<0;5;7m")], [],
        'mouse release is ignored';

    my $broken = new_input_state();
    is_deeply [feed_tui_input($broken, "\e[<0;")], [], 'broken mouse prefix initially waits';
    is_deeply [feed_tui_input($broken, 'q')], [{ type => 'quit' }],
        'plain command after broken mouse prefix is recovered';
};

subtest 'layout maps terminal coordinates to board points' => sub {
    my $layout = board_layout(
        size           => 9,
        first_cell_row => 10,
        first_cell_col => 3,
        cell_step      => 3,
    );

    is hit_test_board($layout, 3, 10), 'aa', 'upper-left point is aa';
    is hit_test_board($layout, 27, 10), 'ia', 'upper-right point is ia';
    is hit_test_board($layout, 27, 18), 'ii', 'lower-right point is ii';
    is hit_test_board($layout, 1, 10), undef, 'row label is not a point';
    is hit_test_board($layout, 30, 18), undef, 'outside board is not a point';
    is point_for_cursor([0, 1], 9), 'ba', 'cursor row and column use filename point order';
};

subtest 'event reducer produces one canonical action intent' => sub {
    my $cursor = [0, 0];
    my $decision = apply_tui_event(
        event  => { type => 'move_cursor', dx => 1, dy => 0 },
        cursor => $cursor,
        size   => 9,
    );
    is_deeply $decision, { type => 'cursor', cursor => [0, 1] },
        'right movement clamps into a new cursor';

    $decision = apply_tui_event(
        event  => { type => 'submit' },
        cursor => $decision->{cursor},
        size   => 9,
    );
    is_deeply $decision, { type => 'action', action => 'ba', cursor => [0, 1] },
        'submit yields the selected point action';

    my $layout = board_layout(size => 9, first_cell_row => 10, first_cell_col => 3);
    $decision = apply_tui_event(
        event  => { type => 'mouse_press', col => 6, row => 11 },
        cursor => [0, 0],
        size   => 9,
        layout => $layout,
    );
    is_deeply $decision, { type => 'action', action => 'bb', cursor => [1, 1] },
        'mouse click yields the hit-tested point action and moves the cursor there';
};

subtest 'renderer exposes board state without deriving truth' => sub {
    my $board = GobanFTP::Board->new(9);
    $board->set(0, 0, 1);
    $board->set(1, 0, 2);

    my ($frame, $layout) = render_play_frame(
        context => _fake_context($board),
        cursor  => [0, 1],
        message => "candidate\nrejected",
        ansi    => 0,
    );

    like $frame, qr/\AGOBANFTP-PLAY-TUI\/1\n/, 'frame has a version header';
    like $frame, qr/Truth: event filenames only/, 'frame names the truth boundary';
    like $frame, qr/Witness: clean [|] Fork: none [|] State: SELECT/,
        'frame includes readable witness and state lines';
    like $frame, qr/Black to play: alice [|] Selected: BA/,
        'frame includes a readable turn line';
    like $frame, qr/Move cursor or click a point; Enter selects BA/,
        'frame includes a readable input line';
    like $frame, qr/^publish_state=select$/m, 'frame starts in select mode';
    like $frame, qr/^Status: ok  Events: 1  Accepted: 1  Main line: 1$/m,
        'frame summarizes supplied replay and event-set fields';
    like $frame, qr/^Turn: black\(alice\)  Cursor: BA$/m, 'frame displays the selected point';
    like $frame, qr/^Message: candidate rejected$/m, 'message is single-line sanitized';
    like $frame, qr/^9 \x{25CF}  \x{25CB}  \x{00B7}  \x{00B7}/m,
        'board stones are rendered as a visual goban';
    is $layout->{first_cell_row} > 1, 1, 'renderer returns a terminal hit-test layout';
    my @frame_lines = split /\n/, $frame;
    my ($first_board_line) = grep { $frame_lines[$_ - 1] =~ /\A9 / } 1 .. @frame_lines;
    is $layout->{first_cell_row}, $first_board_line,
        'returned hit-test row matches the actual rendered first board row';

    my ($confirm_frame) = render_play_frame(
        context        => _fake_context($board),
        cursor         => [0, 1],
        pending_action => 'ba',
        publish_state  => 'confirm',
        ansi           => 0,
    );
    like $confirm_frame, qr/^publish_state=confirm pending_action=ba$/m,
        'confirm frame names the pending action';
    like $confirm_frame, qr/Selected BA; press Enter\/click again to publish/,
        'confirm frame requires a second action before publishing';
};

subtest 'renderer uses diagnostics registry text for validation state' => sub {
    my $board = GobanFTP::Board->new(9);
    my $context = _fake_context($board);
    $context->{replay_result}{diagnostics} = [
        {
            code      => 'illegal_move',
            event_id  => 'deadbeefdeadbeef',
            parent_id => 'genesis',
            reason    => 'occupied',
        },
    ];

    my ($frame) = render_play_frame(
        context => $context,
        cursor  => [0, 0],
        ansi    => 0,
    );

    like $frame, qr/^Status: validation  Events: 1  Accepted: 1  Main line: 1$/m,
        'validation state comes from the shared diagnostics replay status';
    like $frame,
        qr/Witness: blocked [|] Fork: blocked [|] State: SELECT/,
        'validation status is promoted into the top panel';
    like $frame,
        qr/^Diagnostics: illegal_move: The rules engine rejected the move[.]$/m,
        'diagnostics line uses registry explanation text';
};

subtest 'scripted TUI run selects before publishing' => sub {
    my $board = GobanFTP::Board->new(9);
    my $context = _fake_context($board);
    my (@actions, $stdout);
    open my $out_fh, '>', \$stdout or die "open scalar stdout: $!";

    my $session = run_play_tui(
        load_context => sub {
            return $context;
        },
        publish_action => sub {
            my ($action) = @_;
            push @actions, $action;
            die "unexpected publish for $action";
        },
        output_fh => $out_fh,
        script    => "\e[C\rq",
        ansi      => 0,
    );

    is_deeply \@actions, [], 'right arrow plus one Enter selects but does not publish';
    is $session->{stage}, 'quit', 'quit exits after a pending selection';
    like $stdout, qr/^publish_state=confirm pending_action=ba$/m,
        'pending selection is rendered for confirmation';
    unlike $stdout, qr/^publish_state=publishing_locked/m,
        'one accidental key press never enters the publishing lock';
};

subtest 'scripted TUI run confirms, locks, and publishes' => sub {
    my $board = GobanFTP::Board->new(9);
    my $context = _fake_context($board);
    my (@actions, $loads, $stdout);
    open my $out_fh, '>', \$stdout or die "open scalar stdout: $!";

    my $session = run_play_tui(
        load_context => sub {
            $loads++;
            return $context;
        },
        publish_action => sub {
            my ($action) = @_;
            push @actions, $action;
            return {
                exit       => 0,
                stage      => 'published',
                context    => $context,
                event_name => 'm1.t-root.by-alice.x-ba.h-deadbeefdeadbeef',
                event_id   => 'deadbeefdeadbeef',
            };
        },
        output_fh => $out_fh,
        script    => "\e[C\r\r\r",
        ansi      => 0,
    );

    is_deeply \@actions, ['ba'], 'right arrow plus two Enters publishes exactly one selected point';
    is $session->{stage}, 'published', 'published move ends the TUI session';
    is $session->{publish}{event_id}, 'deadbeefdeadbeef', 'publish result is returned to CLI';
    ok $loads >= 2, 'cursor movement redraws from the supplied loader';
    like $stdout, qr/GOBANFTP-PLAY-TUI\/1/, 'scripted session renders frames';
    like $stdout, qr/^publish_state=confirm pending_action=ba$/m,
        'first submit renders the confirmation stage';
    like $stdout, qr/^publish_state=publishing_locked pending_action=ba$/m,
        'confirmed submit renders the publishing lock';
    like $stdout, qr/^publish_state=published pending_action=ba$/m,
        'published result renders the final stage';
};

subtest 'scripted mouse click also requires confirmation' => sub {
    my $board = GobanFTP::Board->new(9);
    my $context = _fake_context($board);
    my (@actions, $stdout);
    open my $out_fh, '>', \$stdout or die "open scalar stdout: $!";

    my (undef, $layout) = render_play_frame(
        context => $context,
        cursor  => [0, 0],
        ansi    => 0,
    );
    my $col = $layout->{first_cell_col} + $layout->{cell_step};
    my $row = $layout->{first_cell_row} + 1;

    my $session = run_play_tui(
        load_context => sub {
            return $context;
        },
        publish_action => sub {
            my ($action) = @_;
            push @actions, $action;
            return {
                exit       => 0,
                stage      => 'published',
                context    => $context,
                event_name => 'm1.t-root.by-alice.x-bb.h-feedfacefeedface',
                event_id   => 'feedfacefeedface',
            };
        },
        output_fh => $out_fh,
        script    => "\e[<0;$col;${row}Mq",
        ansi      => 0,
    );

    is_deeply \@actions, [], 'one mouse click selects but does not publish';
    is $session->{stage}, 'quit', 'mouse selection can be abandoned';
    like $stdout, qr/^publish_state=confirm pending_action=bb$/m,
        'mouse selection is rendered for confirmation';
};

subtest 'scripted repeated mouse click publishes through the lock' => sub {
    my $board = GobanFTP::Board->new(9);
    my $context = _fake_context($board);
    my (@actions, $stdout);
    open my $out_fh, '>', \$stdout or die "open scalar stdout: $!";

    my (undef, $layout) = render_play_frame(
        context => $context,
        cursor  => [0, 0],
        ansi    => 0,
    );
    my $col = $layout->{first_cell_col} + $layout->{cell_step};
    my $row = $layout->{first_cell_row} + 1;

    my $session = run_play_tui(
        load_context => sub {
            return $context;
        },
        publish_action => sub {
            my ($action) = @_;
            push @actions, $action;
            return {
                exit       => 0,
                stage      => 'published',
                context    => $context,
                event_name => 'm1.t-root.by-alice.x-bb.h-feedfacefeedface',
                event_id   => 'feedfacefeedface',
            };
        },
        output_fh => $out_fh,
        script    => "\e[<0;$col;${row}M\e[<0;$col;${row}M\e[<0;$col;${row}M",
        ansi      => 0,
    );

    is_deeply \@actions, ['bb'], 'repeated mouse click publishes exactly one hit-tested point';
    is $session->{stage}, 'published', 'mouse publish ends the TUI session';
    is $session->{publish}{event_id}, 'feedfacefeedface', 'mouse publish result is returned';
    like $stdout, qr/^publish_state=publishing_locked pending_action=bb$/m,
        'mouse confirmation renders the publishing lock';
};

subtest 'CLI play --tui refuses non-terminal stdio before loading a store' => sub {
    my (undef, $game_root) = _make_game_root();
    my ($exit, $stdout, $stderr) = _run_cli('play', '--tui', $game_root);

    is $exit, 4, 'non-terminal TUI exits as storage/environment failure';
    is $stdout, '', 'non-terminal TUI writes no snapshot';
    like $stderr, qr/^storage: play --tui requires an interactive terminal$/m,
        'non-terminal TUI has a clear diagnostic';
};

subtest 'CLI play --tui has a real pty smoke path when script(1) is available' => sub {
    my $script_bin = _which('script');
    plan skip_all => 'script(1) is not available' if !defined $script_bin;
    plan skip_all => 'script(1) does not support GNU -c command mode'
        if !_script_supports_command($script_bin);

    my (undef, $quit_game) = _make_game_root();
    my ($quit_exit, $quit_stdout, $quit_stderr) = _run_pty_cli('q', 'play', '--tui', $quit_game);
    is $quit_exit, 0, 'pty q exits successfully';
    like $quit_stdout, qr/GOBANFTP-PLAY-TUI\/1/, 'pty q renders the TUI frame';
    like $quit_stdout, qr/\e\[ [?]1006l\e\[ [?]1000l\e\[ [?]25h\e\[ [?]1049l/x,
        'pty q restores mouse, cursor, and alternate screen modes';
    is_deeply [_event_names($quit_game)], [], 'pty q publishes no event';
    is $quit_stderr, '', 'pty q has no stderr';

    my (undef, $keyboard_game) = _make_game_root();
    my ($key_exit, $key_stdout, $key_stderr) = _run_pty_cli("\e[C\r\r", 'play', '--tui', $keyboard_game);
    is $key_exit, 0, 'pty keyboard publish exits successfully';
    like $key_stdout, qr/event=m1[.].*play-ba/, 'pty keyboard publishes the selected ba point';
    is scalar(_event_names($keyboard_game)), 1, 'pty keyboard publishes exactly one event';
    like $key_stdout, qr/^publish_state=publishing_locked pending_action=ba$/m,
        'pty keyboard path renders the publishing lock';
    is $key_stderr, '', 'pty keyboard publish has no stderr';

    my (undef, $mouse_game) = _make_game_root();
    my (undef, $mouse_layout) = render_play_frame(
        context => _fake_context(GobanFTP::Board->new(9)),
        cursor  => [0, 0],
        ansi    => 0,
    );
    my $mouse_col = $mouse_layout->{first_cell_col} + $mouse_layout->{cell_step};
    my $mouse_row = $mouse_layout->{first_cell_row} + 1;
    my ($mouse_exit, $mouse_stdout, $mouse_stderr) =
        _run_pty_cli("\e[<0;$mouse_col;${mouse_row}M\e[<0;$mouse_col;${mouse_row}M", 'play', '--tui', $mouse_game);
    is $mouse_exit, 0, 'pty mouse publish exits successfully';
    like $mouse_stdout, qr/event=m1[.].*play-bb/, 'pty mouse publishes the hit-tested bb point';
    is scalar(_event_names($mouse_game)), 1, 'pty mouse publishes exactly one event';
    is $mouse_stderr, '', 'pty mouse publish has no stderr';

    my ($auth_root, $auth_game) = _make_game_root();
    my ($key_path, $key) = _write_hmac_key($auth_root);
    my ($event, $event_id) = _move_name(action => 'play-ba', nonce => 'authdeny');
    my $token_path = _write_publish_token($auth_root, $key, $event, $event_id);
    my ($auth_exit, $auth_stdout, $auth_stderr) = _run_pty_cli(
        "\e[C\r\r",
        'play',
        '--tui',
        '--nonce', 'authdeny',
        '--publish-auth-token', $token_path,
        '--publish-auth-trusted-hmac-key-file', $key_path,
        '--publish-auth-trusted-hmac-status', "$key->{key_id}=rotated",
        $auth_game,
    );
    is $auth_exit, 2, 'pty denied publish-auth exits validation';
    like $auth_stdout, qr/GOBANFTP-PLAY-TUI\/1/, 'pty denied publish-auth renders the TUI frame';
    like $auth_stdout, qr/\e\[ [?]1006l\e\[ [?]1000l\e\[ [?]25h\e\[ [?]1049l/x,
        'pty denied publish-auth restores mouse, cursor, and alternate screen modes';
    like $auth_stdout, qr/gobanftp[.]play=failed\n/, 'pty denied publish-auth reports failed';
    like $auth_stdout, qr/^event=\Q$event\E$/m, 'pty denied publish-auth reports the candidate event';
    like $auth_stdout, qr/^event_id=\Q$event_id\E$/m, 'pty denied publish-auth reports the candidate id';
    like $auth_stdout, qr/^publish_auth[.]status=denied$/m,
        'pty denied publish-auth reports denied status';
    like $auth_stdout, qr/diagnostic .*code=untrusted_signature.*reason=key[.]rotated/,
        'pty denied publish-auth reports lifecycle denial';
    is_deeply [_event_names($auth_game)], [], 'pty denied publish-auth writes no event';
    unlike $auth_stdout . $auth_stderr,
        qr/\Q$key->{secret_hex}\E|\Q$key->{secret}\E|GOFTP-HMAC-KEY|secret_hex/,
        'pty denied publish-auth does not leak HMAC secret material';
    is $auth_stderr, '', 'pty denied publish-auth has no script stderr';
};

done_testing;

sub _fake_context {
    my ($board) = @_;

    return {
        game_descriptor => $GAME,
        events          => ['m1.t-root.by-alice.x-aa.h-deadbeefdeadbeef'],
        event_set       => {
            event_set_root => 'root-sha256',
            event_count    => 1,
        },
        replay_result => {
            final_state => {
                board      => $board,
                next_color => 'b',
                terminal   => 0,
            },
            game => {
                black => 'alice',
                white => 'bob',
            },
            diagnostics   => [],
            canonical_ids => ['deadbeefdeadbeef'],
        },
    };
}

sub _make_game_root {
    my $root = tempdir(CLEANUP => 1);
    my $game_root = File::Spec->catdir($root, $GAME);
    make_path(File::Spec->catdir($game_root, 'events'));
    make_path(File::Spec->catdir($game_root, 'tmp'));
    make_path(File::Spec->catdir($game_root, 'sidecar'));
    return ($root, $game_root);
}

sub _run_cli {
    my (@args) = @_;

    my ($stdout, $stderr) = ('', '');
    open my $in_fh, '<', \my $stdin or die "open stdin scalar: $!";
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

sub _run_pty_cli {
    my ($stdin, @args) = @_;

    my $script_bin = _which('script') // die 'script(1) missing';
    my $cmd = join ' ', map { _shell_quote($_) }
        ($^X, '-Ilib', File::Spec->catfile($root, 'script', 'gobanftp'), @args);

    my $err = gensym;
    my $pid = open3(my $in, my $out, $err, $script_bin, '-q', '-e', '-c', $cmd, '/dev/null');
    print {$in} $stdin;
    close $in or die "close pty stdin: $!";

    my $stdout = do { local $/; <$out> // '' };
    my $stderr = do { local $/; <$err> // '' };
    waitpid $pid, 0;
    my $exit = $? >> 8;

    $stdout =~ s/\r\n/\n/g;
    $stderr =~ s/\r\n/\n/g;
    return ($exit, $stdout, $stderr);
}

sub _script_supports_command {
    my ($script_bin) = @_;

    my $err = gensym;
    my $pid = open3(my $in, my $out, $err, $script_bin, '-q', '-e', '-c', 'true', File::Spec->devnull);
    close $in or return 0;
    my $stdout = do { local $/; <$out> // '' };
    my $stderr = do { local $/; <$err> // '' };
    waitpid $pid, 0;

    return ($? >> 8) == 0 && $stderr !~ /illegal option|usage:/i ? 1 : 0;
}

sub _event_names {
    my ($game_root) = @_;

    my $dir = File::Spec->catdir($game_root, 'events');
    opendir my $dh, $dir or die "opendir $dir: $!";
    my @names = sort grep { $_ ne '.' && $_ ne '..' } readdir $dh;
    closedir $dh or die "closedir $dir: $!";

    return @names;
}

sub _write_hmac_key {
    my ($root) = @_;

    my $key = generate_hmac_key_record(secret => ('t' x 32));
    my $path = File::Spec->catfile($root, 'player.hmac-key');
    write_hmac_key_file($path, $key);

    return ($path, $key);
}

sub _move_name {
    my (%args) = @_;

    return build_move_name(
        game_descriptor => $GAME,
        ply             => 1,
        color           => 'b',
        action          => $args{action},
        parent_id       => 'genesis',
        player          => 'alice',
        nonce           => $args{nonce},
    );
}

sub _write_publish_token {
    my ($root, $key, $event, $event_id) = @_;

    my $token = sign_publish_token(
        profile         => 'signed-hmac-goftp1',
        game_descriptor => $GAME,
        event_basename  => $event,
        event_id        => $event_id,
        key_id          => $key->{key_id},
        key             => $key->{secret},
    );
    my $path = File::Spec->catfile($root, 'publish-token.jsonl');
    open my $fh, '>:encoding(UTF-8)', $path or die "write $path: $!";
    print {$fh} JSON::PP->new->canonical(1)->encode($token), "\n";
    close $fh or die "close $path: $!";

    return $path;
}

sub _which {
    my ($name) = @_;

    for my $dir (File::Spec->path) {
        my $path = File::Spec->catfile($dir, $name);
        return $path if -x $path && !-d $path;
    }
    return undef;
}

sub _shell_quote {
    my ($value) = @_;
    $value //= '';
    $value =~ s/'/'\\''/g;
    return "'$value'";
}

sub _slurp {
    my ($path) = @_;

    open my $fh, '<:encoding(UTF-8)', $path or die "open $path: $!";
    my $text = do { local $/; <$fh> };
    close $fh or die "close $path: $!";
    return $text // '';
}
