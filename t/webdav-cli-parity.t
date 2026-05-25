use v5.34;
use strict;
use warnings;

use FindBin;
use File::Spec;
use File::Temp qw(tempdir);
use JSON::PP;
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::Auth::HMACKey qw(generate_hmac_key_record write_hmac_key_file);
use GobanFTP::Auth::PublishToken qw(sign_publish_token);
use GobanFTP::CLI;
use GobanFTP::MovePublisher qw(build_move_name);

my $ROOT_URL = 'https://dav.example.test/webdav-cli-root';
my $ROOT_PATH = 'webdav-cli-root';
my $GAME = 'g1.id-webdav-cli-parity.s9.r-chinese-area-v1.k7500.pb-alice.pw-bob';
my $TOKEN = 'webdav-secret-token';

subtest 'WebDAV CLI parity uses PROPFIND for sgf play and watch' => sub {
    WebDAVCliParityHTTP->reset;

    local %ENV = %ENV;
    _webdav_env();

    my ($create_exit, $create_stdout, $create_stderr) = _run_cli('create-game', $GAME);
    is $create_exit, 0, 'create-game setup succeeds';
    like $create_stdout, qr/^store=webdav$/m, 'setup selects WebDAV store';
    is $create_stderr, '', 'setup has no diagnostics';

    my @play_once_calls = _assert_command_uses_webdav_listing(
        'play --once',
        sub {
            my ($exit, $stdout, $stderr) = _run_cli('play', '--once', $GAME);
            is $exit, 0, 'play --once exits success';
            like $stdout, qr/^gobanftp\.play=ok$/m, 'play --once reports ok';
            like $stdout, qr/^events=0$/m, 'play --once sees the empty WebDAV event listing';
            like $stdout, qr/^event_set_count=0$/m, 'play --once reports empty event-set count';
            like $stdout, qr/^event_set_root=[0-9a-f]{64}$/m, 'play --once reports an event-set root';
            like $stdout, qr/^worldline\.status=main$/m, 'play --once renders a main worldline';
            is $stderr, '', 'play --once has no diagnostics';
            unlike $stdout . $stderr, qr/\Q$TOKEN\E/, 'token is not printed';
        },
    );
    _assert_no_webdav_writes('play --once does not write through WebDAV', \@play_once_calls);

    my ($left_event, $left_id);
    my @play_move_calls = _assert_command_uses_webdav_listing(
        'play --move',
        sub {
            my ($exit, $stdout, $stderr) = _run_cli('play', '--move', 'aa', '--nonce', 'p1', $GAME);
            is $exit, 0, 'play --move exits success';
            like $stdout, qr/^gobanftp\.play=ok$/m, 'play --move reports ok';
            like $stdout, qr/^events=1$/m, 'play --move reloads the WebDAV listing after publish';
            like $stdout, qr/^event_set_count=1$/m, 'play --move reports one accepted event';
            like $stdout, qr/^canonical_moves=1$/m, 'play --move renders one canonical move';
            like $stdout, qr/^turn_player=bob$/m, 'play --move advances the turn';
            is $stderr, '', 'play --move has no diagnostics';

            ($left_event) = $stdout =~ /^event=(m1\..+)$/m;
            ($left_id) = $stdout =~ /^event_id=([0-9a-v]{16})$/m;
            like $left_event // '', qr/\Am1\.p000001\.b\.play-aa\.pa-genesis\.by-alice\.n-p1\.h-[0-9a-v]{16}\z/,
                'play --move reports the published event basename';
            like $left_id // '', qr/\A[0-9a-v]{16}\z/, 'play --move reports the published event id';
            unlike $stdout . $stderr, qr/\Q$TOKEN\E/, 'token is still not printed';
        },
    );
    _assert_move_publish('play --move publishes through WebDAV MOVE mode', \@play_move_calls);

    ok WebDAVCliParityHTTP->has_event($ROOT_PATH, $GAME, $left_event),
        'play --move published into WebDAV events/';

    my @verify_calls = _assert_command_uses_webdav_listing(
        'verify',
        sub {
            my ($exit, $stdout, $stderr) = _run_cli('verify', $GAME);
            is $exit, 0, 'verify exits success';
            like $stdout, qr/^gobanftp\.verify=ok$/m, 'verify reports ok';
            like $stdout, qr/^events=1$/m, 'verify sees the WebDAV event listing';
            like $stdout, qr/^event_set_count=1$/m, 'verify reports one accepted event';
            like $stdout, qr/^event_set_root=[0-9a-f]{64}$/m, 'verify reports an event-set root';
            like $stdout, qr/^canonical_moves=1$/m, 'verify reports one canonical move';
            is $stderr, '', 'verify has no diagnostics';
        },
    );
    _assert_no_webdav_writes('verify does not write through WebDAV', \@verify_calls);

    my @replay_calls = _assert_command_uses_webdav_listing(
        'replay',
        sub {
            my ($exit, $stdout, $stderr) = _run_cli('replay', $GAME);
            is $exit, 0, 'replay exits success';
            like $stdout, qr/^gobanftp\.replay=ok$/m, 'replay reports ok';
            like $stdout, qr/^events=1$/m, 'replay sees the WebDAV event listing';
            like $stdout, qr/^canonical_ids=\Q$left_id\E$/m, 'replay reports the canonical id';
            is $stderr, '', 'replay has no diagnostics';
        },
    );
    _assert_no_webdav_writes('replay does not write through WebDAV', \@replay_calls);

    my @watch_calls = _assert_command_uses_webdav_listing(
        'watch --once --interval 0',
        sub {
            my ($exit, $stdout, $stderr) = _run_cli('watch', '--once', '--interval', '0', $GAME);
            is $exit, 0, 'watch --once --interval 0 exits success';
            like $stdout, qr/^gobanftp\.watch=ok$/m, 'watch reports ok';
            like $stdout, qr/^snapshot=1$/m, 'watch reports the bounded snapshot';
            like $stdout, qr/^events=1$/m, 'watch sees the WebDAV event listing';
            like $stdout, qr/^worldline\.status=main$/m, 'watch renders the main worldline';
            is $stderr, '', 'watch has no diagnostics';
        },
    );
    _assert_no_webdav_writes('watch --once does not write through WebDAV', \@watch_calls);

    my @sgf_calls = _assert_command_uses_webdav_listing(
        'sgf',
        sub {
            my ($exit, $stdout, $stderr) = _run_cli('sgf', $GAME);
            is $exit, 0, 'sgf exits success';
            like $stdout, qr/\A\(;/, 'sgf prints an SGF collection';
            like $stdout, qr/;B\[aa\]/, 'sgf renders the WebDAV-listed move';
            unlike $stdout, qr/^event_set_root=/m, 'sgf stdout is not polluted by event-set root';
            is $stderr, '', 'sgf has no diagnostics';
        },
    );
    _assert_no_webdav_writes('sgf does not write through WebDAV', \@sgf_calls);

    my $before_project_reject = WebDAVCliParityHTTP->call_count;
    my ($project_exit, $project_stdout, $project_stderr) = _run_cli('project', $GAME);
    is $project_exit, 4, 'project rejects WebDAV projection writes';
    is $project_stdout, '', 'project writes no stdout when WebDAV is rejected';
    like $project_stderr, qr/^storage: project writes local projection files/m,
        'project reports the local-only storage boundary';
    is_deeply [ WebDAVCliParityHTTP->calls_since($before_project_reject) ], [],
        'project rejection does not construct or contact WebDAV';

    my $before_sgf_write_reject = WebDAVCliParityHTTP->call_count;
    my ($sgf_write_exit, $sgf_write_stdout, $sgf_write_stderr) = _run_cli('sgf', '--write', $GAME);
    is $sgf_write_exit, 4, 'sgf --write rejects WebDAV projection writes';
    is $sgf_write_stdout, '', 'sgf --write writes no stdout when WebDAV is rejected';
    like $sgf_write_stderr, qr/^storage: sgf --write writes local projection files/m,
        'sgf --write reports the local-only storage boundary';
    is_deeply [ WebDAVCliParityHTTP->calls_since($before_sgf_write_reject) ], [],
        'sgf --write rejection does not construct or contact WebDAV';

    my ($white_event);
    my @publish_move_calls = _assert_command_uses_webdav_listing(
        'publish-move',
        sub {
            my ($exit, $stdout, $stderr) = _run_cli('publish-move', '--nonce', 'p2', $GAME, 'bb');
            is $exit, 0, 'publish-move exits success';
            like $stdout, qr/^gobanftp\.publish-move=ok$/m, 'publish-move reports ok';
            like $stdout, qr/^events=2$/m, 'publish-move reloads the WebDAV listing after publish';
            like $stdout, qr/^event_set_count=2$/m, 'publish-move reports two accepted events';
            like $stdout, qr/^canonical_moves=2$/m, 'publish-move reports two canonical moves';
            is $stderr, '', 'publish-move has no diagnostics';

            ($white_event) = $stdout =~ /^event=(m1\..+)$/m;
            like $white_event // '',
                qr/\Am1\.p000002\.w\.play-bb\.pa-\Q$left_id\E\.by-bob\.n-p2\.h-[0-9a-v]{16}\z/,
                'publish-move reports the WebDAV white event basename';
        },
    );
    _assert_move_publish('publish-move publishes through WebDAV MOVE mode', \@publish_move_calls);
    ok WebDAVCliParityHTTP->has_event($ROOT_PATH, $GAME, $white_event),
        'publish-move published into WebDAV events/';

    ok !WebDAVCliParityHTTP->has_path("$ROOT_PATH/$GAME/projections"),
        'play/watch/sgf/publish parity does not create WebDAV projections';
    _assert_no_forbidden_webdav_reads('read-only parity plus play --move stays listing-first');
};

subtest 'WebDAV publish-ack fork exit and play --ack recovery match local CLI behavior' => sub {
    WebDAVCliParityHTTP->reset;

    local %ENV = %ENV;
    _webdav_env();

    my ($create_exit, $create_stdout, $create_stderr) = _run_cli('create-game', $GAME);
    is $create_exit, 0, 'ack setup create-game succeeds';
    like $create_stdout, qr/^store=webdav$/m, 'ack setup selects WebDAV store';
    is $create_stderr, '', 'ack setup has no diagnostics';

    my ($left_id);
    my @first_move_calls = _assert_command_uses_webdav_listing(
        'play --move before fork',
        sub {
            my ($exit, $stdout, $stderr) = _run_cli('play', '--move', 'aa', '--nonce', 'left', $GAME);
            is $exit, 0, 'initial play --move exits success';
            like $stdout, qr/^gobanftp\.play=ok$/m, 'initial play --move reports ok';
            is $stderr, '', 'initial play --move has no diagnostics';
            ($left_id) = $stdout =~ /^event_id=([0-9a-v]{16})$/m;
            like $left_id // '', qr/\A[0-9a-v]{16}\z/, 'initial play --move reports an event id';
        },
    );
    _assert_move_publish('initial play --move publishes through WebDAV MOVE mode', \@first_move_calls);

    my ($right_event, $right_id) = build_move_name(
        game_descriptor => $GAME,
        ply             => 1,
        color           => 'b',
        action          => 'play-bb',
        parent_id       => 'genesis',
        player          => 'alice',
        nonce           => 'right',
    );
    WebDAVCliParityHTTP->create_file("$ROOT_PATH/$GAME/events/$right_event");

    my @publish_ack_calls = _assert_command_uses_webdav_listing(
        'publish-ack',
        sub {
            my ($exit, $stdout, $stderr) = _run_cli('publish-ack', '--nonce', 'ackleft', $GAME, $left_id);
            is $exit, 3, 'publish-ack preserves the expected conservative fork exit';
            like $stdout, qr/^gobanftp\.publish-ack=fork$/m, 'publish-ack reports fork status';
            like $stdout, qr/^events=3$/m, 'publish-ack reloads both fork moves and the ack';
            like $stdout, qr/^event_set_count=3$/m, 'publish-ack reports three accepted WebDAV events';
            like $stdout, qr/^event_set_root=[0-9a-f]{64}$/m, 'publish-ack reports the WebDAV event-set root';
            like $stdout, qr/^event=a1\.t-\Q$left_id\E\.by-bob\.n-ackleft\.h-[0-9a-v]{16}$/m,
                'publish-ack reports the WebDAV ack event basename';
            like $stderr, qr/diagnostic .*code=fork/, 'publish-ack emits the conservative fork diagnostic';
        },
    );
    _assert_move_publish('publish-ack publishes through WebDAV MOVE mode', \@publish_ack_calls);

    my @play_ack_calls = _assert_command_uses_webdav_listing(
        'play --ack',
        sub {
            my ($exit, $stdout, $stderr) = _run_cli('play', '--ack', $left_id, '--nonce', 'playack', $GAME);
            is $exit, 0, 'play --ack exits success after ack-assisted recovery';
            like $stdout, qr/^event=a1\.t-\Q$left_id\E\.by-bob\.n-playack\.h-[0-9a-v]{16}$/m,
                'play --ack reports the WebDAV ack event basename';
            like $stdout, qr/^gobanftp\.play=ok$/m, 'play --ack reports ok';
            like $stdout, qr/^events=4$/m, 'play --ack reloads the WebDAV listing after publishing';
            like $stdout, qr/^event_set_count=4$/m, 'play --ack reports four accepted WebDAV events';
            like $stdout, qr/^canonical_moves=1$/m, 'play --ack chooses one canonical fork child';
            like $stdout, qr/^worldline\.status=main$/m, 'play --ack renders a recovered worldline';
            like $stdout, qr/^worldline\.canonical_ids=\Q$left_id\E$/m, 'play --ack chooses the acked child';
            unlike $stdout, qr/^worldline\.canonical_ids=\Q$right_id\E$/m, 'play --ack does not choose the unacked child';
            is $stderr, '', 'play --ack has no diagnostics after recovery';
        },
    );
    _assert_move_publish('play --ack publishes through WebDAV MOVE mode', \@play_ack_calls);

    is scalar(grep { /\Aa1\./ } WebDAVCliParityHTTP->event_names($ROOT_PATH, $GAME)), 2,
        'publish-ack and play --ack both publish ack events through WebDAV';
    ok !WebDAVCliParityHTTP->has_path("$ROOT_PATH/$GAME/projections"),
        'ack parity commands do not create WebDAV projections';
    _assert_no_forbidden_webdav_reads('ack parity stays listing-first');
};

subtest 'WebDAV publish-move confirms a lost MOVE response through fresh PROPFIND' => sub {
    WebDAVCliParityHTTP->reset;

    local %ENV = %ENV;
    _webdav_env();

    my ($create_exit, $create_stdout, $create_stderr) = _run_cli('create-game', $GAME);
    is $create_exit, 0, 'delayed setup create-game succeeds';
    like $create_stdout, qr/^store=webdav$/m, 'delayed setup selects WebDAV store';
    is $create_stderr, '', 'delayed setup has no diagnostics';

    WebDAVCliParityHTTP->delay_next_move_confirm(after_propfinds => 2);

    my ($event);
    my @publish_calls = _assert_command_uses_webdav_listing(
        'publish-move delayed MOVE confirm',
        sub {
            my ($exit, $stdout, $stderr) = _run_cli('publish-move', '--nonce', 'delayed', $GAME, 'aa');
            is $exit, 0, 'publish-move succeeds after delayed WebDAV visibility';
            like $stdout, qr/^gobanftp\.publish-move=ok$/m, 'publish-move reports ok';
            like $stdout, qr/^events=1$/m, 'publish-move reloads the delayed final event';
            like $stdout, qr/^event_set_count=1$/m, 'publish-move accepts one event after delayed confirm';
            like $stdout, qr/^canonical_moves=1$/m, 'publish-move renders one canonical move';
            is $stderr, '', 'delayed confirm has no diagnostics';
            unlike $stdout . $stderr, qr/\Q$TOKEN\E/, 'delayed confirm does not print the WebDAV token';

            ($event) = $stdout =~ /^event=(m1\..+)$/m;
            like $event // '',
                qr/\Am1\.p000001\.b\.play-aa\.pa-genesis\.by-alice\.n-delayed\.h-[0-9a-v]{16}\z/,
                'publish-move reports the delayed WebDAV event basename';
        },
    );

    _assert_move_publish('publish-move delayed confirm uses WebDAV MOVE mode', \@publish_calls);
    is scalar(grep { $_->[0] eq 'MOVE' } @publish_calls), 1,
        'lost MOVE response is not retried after fresh PROPFIND finds the target';
    ok WebDAVCliParityHTTP->has_event($ROOT_PATH, $GAME, $event),
        'delayed final event is visible through WebDAV listing';
    _assert_no_forbidden_webdav_reads('delayed publish-move confirm stays listing-first', \@publish_calls);
};

subtest 'WebDAV publish-move MKCOL mode matches CLI parity without upload' => sub {
    WebDAVCliParityHTTP->reset;

    local %ENV = %ENV;
    _webdav_env(publish_mode => 'mkcol');

    my ($create_exit, $create_stdout, $create_stderr) = _run_cli('create-game', $GAME);
    is $create_exit, 0, 'MKCOL setup create-game succeeds';
    like $create_stdout, qr/^store=webdav$/m, 'MKCOL setup selects WebDAV store';
    is $create_stderr, '', 'MKCOL setup has no diagnostics';

    my ($event);
    my @publish_calls = _assert_command_uses_webdav_listing(
        'publish-move MKCOL mode',
        sub {
            my ($exit, $stdout, $stderr) = _run_cli('publish-move', '--nonce', 'mkcol', $GAME, 'aa');
            is $exit, 0, 'publish-move MKCOL mode exits success';
            like $stdout, qr/^gobanftp\.publish-move=ok$/m, 'publish-move MKCOL mode reports ok';
            like $stdout, qr/^events=1$/m, 'publish-move MKCOL mode reloads the WebDAV listing';
            like $stdout, qr/^event_set_count=1$/m, 'publish-move MKCOL mode accepts one event';
            like $stdout, qr/^canonical_moves=1$/m, 'publish-move MKCOL mode renders one canonical move';
            is $stderr, '', 'publish-move MKCOL mode has no diagnostics';
            unlike $stdout . $stderr, qr/\Q$TOKEN\E/, 'publish-move MKCOL mode does not print the WebDAV token';

            ($event) = $stdout =~ /^event=(m1\..+)$/m;
            like $event // '',
                qr/\Am1\.p000001\.b\.play-aa\.pa-genesis\.by-alice\.n-mkcol\.h-[0-9a-v]{16}\z/,
                'publish-move MKCOL mode reports the WebDAV event basename';
        },
    );

    _assert_mkcol_publish('publish-move MKCOL mode publishes through WebDAV MKCOL mode', \@publish_calls, $event);
    ok WebDAVCliParityHTTP->has_event($ROOT_PATH, $GAME, $event),
        'publish-move MKCOL mode published into WebDAV events/';
    is WebDAVCliParityHTTP->entry_type("$ROOT_PATH/$GAME/events/$event"), 'dir',
        'publish-move MKCOL mode creates a directory-shaped event';
    _assert_no_forbidden_webdav_reads('publish-move MKCOL mode stays listing-first', \@publish_calls);
};

subtest 'WebDAV publish-move MKCOL mode confirms ambiguous target failure' => sub {
    WebDAVCliParityHTTP->reset;

    local %ENV = %ENV;
    _webdav_env(publish_mode => 'mkcol');

    my ($create_exit, $create_stdout, $create_stderr) = _run_cli('create-game', $GAME);
    is $create_exit, 0, 'MKCOL delayed setup create-game succeeds';
    like $create_stdout, qr/^store=webdav$/m, 'MKCOL delayed setup selects WebDAV store';
    is $create_stderr, '', 'MKCOL delayed setup has no diagnostics';

    WebDAVCliParityHTTP->delay_next_mkcol_confirm(
        status => 500,
        reason => 'MKCOL response lost',
        after_propfinds => 2,
    );

    my ($event);
    my @publish_calls = _assert_command_uses_webdav_listing(
        'publish-move MKCOL ambiguous delayed confirm',
        sub {
            my ($exit, $stdout, $stderr) = _run_cli('publish-move', '--nonce', 'mkcoldelay', $GAME, 'aa');
            is $exit, 0, 'publish-move MKCOL succeeds after delayed WebDAV visibility';
            like $stdout, qr/^gobanftp\.publish-move=ok$/m, 'publish-move MKCOL delayed confirm reports ok';
            like $stdout, qr/^events=1$/m, 'publish-move MKCOL delayed confirm reloads the WebDAV listing';
            like $stdout, qr/^event_set_count=1$/m, 'publish-move MKCOL delayed confirm accepts one event';
            like $stdout, qr/^canonical_moves=1$/m, 'publish-move MKCOL delayed confirm renders one canonical move';
            is $stderr, '', 'publish-move MKCOL delayed confirm has no diagnostics';
            unlike $stdout . $stderr, qr/\Q$TOKEN\E/, 'publish-move MKCOL delayed confirm does not print the WebDAV token';

            ($event) = $stdout =~ /^event=(m1\..+)$/m;
            like $event // '',
                qr/\Am1\.p000001\.b\.play-aa\.pa-genesis\.by-alice\.n-mkcoldelay\.h-[0-9a-v]{16}\z/,
                'publish-move MKCOL delayed confirm reports the WebDAV event basename';
        },
    );

    _assert_mkcol_publish('publish-move MKCOL delayed confirm uses WebDAV MKCOL mode', \@publish_calls, $event);
    is scalar(grep { $_->[0] eq 'MKCOL' && $_->[1] eq "$ROOT_URL/$GAME/events/$event/" } @publish_calls), 1,
        'ambiguous MKCOL target failure is not retried after fresh PROPFIND finds the target';
    ok WebDAVCliParityHTTP->has_event($ROOT_PATH, $GAME, $event),
        'MKCOL delayed final event is visible through WebDAV listing';
    is WebDAVCliParityHTTP->entry_type("$ROOT_PATH/$GAME/events/$event"), 'dir',
        'MKCOL delayed confirm creates a directory-shaped event';
    _assert_no_forbidden_webdav_reads('publish-move MKCOL delayed confirm stays listing-first', \@publish_calls);
};

subtest 'WebDAV publish-move reports hard MOVE failures without leaking auth' => sub {
    WebDAVCliParityHTTP->reset;

    local %ENV = %ENV;
    _webdav_env();

    my ($create_exit, $create_stdout, $create_stderr) = _run_cli('create-game', $GAME);
    is $create_exit, 0, 'hard failure setup create-game succeeds';
    like $create_stdout, qr/^store=webdav$/m, 'hard failure setup selects WebDAV store';
    is $create_stderr, '', 'hard failure setup has no diagnostics';

    my ($event) = build_move_name(
        game_descriptor => $GAME,
        ply             => 1,
        color           => 'b',
        action          => 'play-aa',
        parent_id       => 'genesis',
        player          => 'alice',
        nonce           => 'hardlock',
    );
    my ($event_id) = $event =~ /\.h-([0-9a-v]{16})(?:\z|\.)/;
    my $tmp_path = "$GAME/tmp/alice-hardlock-$event_id.part";
    my $target_path = "$GAME/events/$event";

    WebDAVCliParityHTTP->fail_moves(423, 'Locked');

    my @publish_calls = _assert_command_uses_webdav_listing(
        'publish-move hard MOVE failure',
        sub {
            my ($exit, $stdout, $stderr) = _run_cli('publish-move', '--nonce', 'hardlock', $GAME, 'aa');
            is $exit, 4, 'publish-move exits storage failure on permanent MOVE failure';
            is $stdout, '', 'hard MOVE failure does not print stdout';
            like $stderr,
                qr/^storage: move \Q$tmp_path\E to \Q$target_path\E failed: HTTP 423 Locked$/m,
                'hard MOVE failure reports the fixed temp and target paths';
            unlike $stdout . $stderr, qr/\Q$TOKEN\E/, 'hard MOVE failure does not print the WebDAV token';
        },
    );

    my @puts = grep { $_->[0] eq 'PUT' } @publish_calls;
    my @moves = grep { $_->[0] eq 'MOVE' } @publish_calls;
    is scalar(@puts), 1, 'hard MOVE failure uploads one temporary resource';
    is_deeply [ map { length($_->[2]{content} // '') } @puts ], [0],
        'hard MOVE failure temporary upload is zero bytes';
    is scalar(@moves), 2, 'hard MOVE failure uses the bounded default retry count';
    is_deeply [ map { $_->[1] } @moves ], [ ("$ROOT_URL/$tmp_path") x 2 ],
        'hard MOVE failure retries the same temporary path';
    is_deeply [ map { $_->[2]{headers}{Destination} } @moves ],
        [ ("$ROOT_URL/$target_path") x 2 ],
        'hard MOVE failure retries the same event target';
    ok !WebDAVCliParityHTTP->has_event($ROOT_PATH, $GAME, $event),
        'hard MOVE failure does not create a final event';
    ok WebDAVCliParityHTTP->has_path("$ROOT_PATH/$tmp_path"),
        'hard MOVE failure may leave temporary debris outside witness truth';
    _assert_no_forbidden_webdav_reads('hard MOVE failure stays listing-first', \@publish_calls);
};

subtest 'WebDAV denied publish preflight does not PUT or MOVE' => sub {
    WebDAVCliParityHTTP->reset;

    local %ENV = %ENV;
    _webdav_env();

    my $dir = tempdir(CLEANUP => 1);
    my ($key_path, $key) = _write_key($dir);
    my ($event, $event_id) = build_move_name(
        game_descriptor => $GAME,
        ply             => 1,
        color           => 'b',
        action          => 'play-aa',
        parent_id       => 'genesis',
        player          => 'alice',
        nonce           => 'authdeny',
    );
    my $token_path = _write_token($dir, $key, $event, $event_id);

    my ($create_exit, undef, $create_stderr) = _run_cli('create-game', $GAME);
    is $create_exit, 0, 'denied setup create-game succeeds';
    is $create_stderr, '', 'denied setup has no diagnostics';

    my @calls = _assert_command_uses_webdav_listing(
        'publish-move denied preflight',
        sub {
            my ($exit, $stdout, $stderr) = _run_cli(
                'publish-move',
                '--nonce', 'authdeny',
                '--publish-auth-token', $token_path,
                '--publish-auth-trusted-hmac-key-file', $key_path,
                '--publish-auth-trusted-hmac-status', "$key->{key_id}=rotated",
                $GAME,
                'aa',
            );
            is $exit, 2, 'denied preflight exits validation';
            like $stdout, qr/^gobanftp[.]publish-move=failed$/m,
                'denied preflight reports failed';
            like $stdout, qr/^publish_auth[.]status=denied$/m,
                'denied preflight reports auth denial';
            like $stderr, qr/diagnostic .*code=untrusted_signature.*reason=key[.]rotated/,
                'denied preflight reports lifecycle reason';
            unlike $stdout . $stderr, qr/\Q$key->{secret_hex}\E|secret_hex|\Q$TOKEN\E/,
                'denied preflight does not leak HMAC secret or WebDAV token';
        },
    );

    _assert_no_webdav_writes('denied preflight does not PUT or MOVE', \@calls);
    ok !WebDAVCliParityHTTP->has_event($ROOT_PATH, $GAME, $event),
        'denied preflight creates no WebDAV event';
};

done_testing;

sub _webdav_env {
    my (%args) = @_;

    delete @ENV{ grep { /\AGOBANFTP_WEBDAV_/ } keys %ENV };
    $ENV{GOBANFTP_STORE} = 'webdav';
    $ENV{GOBANFTP_WEBDAV_URL} = $ROOT_URL;
    $ENV{GOBANFTP_WEBDAV_CLASS} = 'WebDAVCliParityHTTP';
    $ENV{GOBANFTP_WEBDAV_TOKEN} = $TOKEN;
    $ENV{GOBANFTP_WEBDAV_PUBLISH_MODE} = $args{publish_mode}
        if defined $args{publish_mode};
    return;
}

sub _assert_command_uses_webdav_listing {
    my ($label, $code) = @_;

    my $before = WebDAVCliParityHTTP->call_count;
    $code->();
    my @calls = WebDAVCliParityHTTP->calls_since($before);

    ok((grep {
        $_->[0] eq 'PROPFIND'
            && $_->[1] eq "$ROOT_URL/$GAME/events/"
            && ($_->[2]{headers}{Depth} // '') eq '1'
    } @calls), "$label reads the WebDAV events collection with PROPFIND Depth: 1");
    _assert_no_forbidden_webdav_reads("$label does not use non-listing WebDAV reads", \@calls);

    return @calls;
}

sub _assert_no_forbidden_webdav_reads {
    my ($label, $calls) = @_;

    my @calls = defined $calls ? @$calls : WebDAVCliParityHTTP->calls;
    my @forbidden = grep { $_->[0] !~ /\A(?:new|PROPFIND|MKCOL|PUT|MOVE)\z/ } @calls;
    is_deeply \@forbidden, [], $label;
}

sub _assert_no_webdav_writes {
    my ($label, $calls) = @_;

    my @writes = grep { $_->[0] =~ /\A(?:MKCOL|PUT|MOVE)\z/ } @$calls;
    is_deeply \@writes, [], $label;
}

sub _assert_move_publish {
    my ($label, $calls) = @_;

    my @puts = grep { $_->[0] eq 'PUT' } @$calls;
    ok(@puts, "$label uploads a temporary event");
    is_deeply [ map { length($_->[2]{content} // '') } @puts ], [ (0) x @puts ],
        "$label uploads zero-byte temporary resources";
    ok((grep { $_->[0] eq 'MOVE' } @$calls), "$label moves the temporary event into events/");
}

sub _assert_mkcol_publish {
    my ($label, $calls, $event) = @_;

    my $target_url = "$ROOT_URL/$GAME/events/" . ($event // '') . '/';
    my @mkcols = grep { $_->[0] eq 'MKCOL' } @$calls;
    ok(@mkcols, "$label creates WebDAV collections");
    ok((grep { $_->[1] eq $target_url } @mkcols), "$label creates the event collection");
    is_deeply [ grep { $_->[0] =~ /\A(?:PUT|MOVE)\z/ } @$calls ],
        [],
        "$label does not upload or move";
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

sub _write_key {
    my ($dir) = @_;

    my $key = generate_hmac_key_record(secret => ('w' x 32));
    my $path = File::Spec->catfile($dir, 'player.hmac-key');
    write_hmac_key_file($path, $key);

    return ($path, $key);
}

sub _write_token {
    my ($dir, $key, $event, $event_id) = @_;

    my $token = sign_publish_token(
        profile         => 'signed-hmac-goftp1',
        game_descriptor => $GAME,
        event_basename  => $event,
        event_id        => $event_id,
        key_id          => $key->{key_id},
        key             => $key->{secret},
    );
    my $path = File::Spec->catfile($dir, 'publish-token.jsonl');
    open my $fh, '>:encoding(UTF-8)', $path or die "write $path: $!";
    print {$fh} JSON::PP->new->canonical(1)->encode($token), "\n";
    close $fh or die "close $path: $!";

    return $path;
}

package WebDAVCliParityHTTP;

use v5.34;
use strict;
use warnings;

our $STATE;

sub new {
    my ($class, %args) = @_;

    $STATE //= _fresh_state();
    my $self = bless $STATE, $class;
    $self->_record('new', $args{timeout} // '');

    return $self;
}

sub reset {
    $STATE = _fresh_state();
    return;
}

sub calls {
    $STATE //= _fresh_state();
    return @{ $STATE->{calls} };
}

sub call_count {
    $STATE //= _fresh_state();
    return scalar @{ $STATE->{calls} };
}

sub calls_since {
    my ($class, $index) = @_;

    $STATE //= _fresh_state();
    my @calls = @{ $STATE->{calls} };
    return () if $index > $#calls;
    return @calls[$index .. $#calls];
}

sub has_event {
    my ($class, $root, $game, $event) = @_;

    return 0 if !defined $event || $event eq '';
    $STATE //= _fresh_state();
    return exists $STATE->{entries}{ _canon("$root/$game/events/$event") } ? 1 : 0;
}

sub has_path {
    my ($class, $path) = @_;

    $STATE //= _fresh_state();
    return exists $STATE->{entries}{ _canon($path) } ? 1 : 0;
}

sub entry_type {
    my ($class, $path) = @_;

    $STATE //= _fresh_state();
    return $STATE->{entries}{ _canon($path) };
}

sub create_file {
    my ($class, $path) = @_;

    $STATE //= _fresh_state();
    return bless($STATE, $class)->_create_file($path);
}

sub delay_next_move_confirm {
    my ($class, %args) = @_;

    $STATE //= _fresh_state();
    $STATE->{move_hook} = sub {
        my ($self, $source, $target) = @_;
        $self->schedule_create_file($target, after_propfinds => $args{after_propfinds} // 1);
        return _response(500, 'MOVE response lost');
    };
    return;
}

sub delay_next_mkcol_confirm {
    my ($class, %args) = @_;

    $STATE //= _fresh_state();
    $STATE->{mkcol_hook} = sub {
        my ($self, $path) = @_;
        return undef if $path !~ m{\A\Q$ROOT_PATH/$GAME/events\E/[^/]+\z};

        $self->schedule_create_dir($path, after_propfinds => $args{after_propfinds} // 1);
        $self->{mkcol_hook} = undef;
        return _response($args{status} // 500, $args{reason} // 'MKCOL response lost');
    };
    return;
}

sub fail_moves {
    my ($class, $status, $reason) = @_;

    $STATE //= _fresh_state();
    $STATE->{move_hook} = sub {
        return _response($status, $reason);
    };
    return;
}

sub event_names {
    my ($class, $root, $game) = @_;

    $STATE //= _fresh_state();
    my $parent = _canon("$root/$game/events");
    return sort
        map { _basename($_) }
        grep { $_ ne '' && _parent($_) eq $parent }
        keys %{ $STATE->{entries} };
}

sub request {
    my ($self, $method, $url, $opts) = @_;
    $opts //= {};

    my $call_opts = {
        headers => { %{ $opts->{headers} // {} } },
        exists($opts->{content}) ? (content => $opts->{content}) : (),
    };
    $self->_record($method, $url, $call_opts);

    my $path = _path_from_url($url);

    return $self->_propfind($path, $opts) if $method eq 'PROPFIND';
    return $self->_mkcol($path) if $method eq 'MKCOL';
    return $self->_put($path, $opts) if $method eq 'PUT';
    return $self->_move($path, $opts) if $method eq 'MOVE';

    return _response(405, 'Method Not Allowed');
}

sub _propfind {
    my ($self, $path, $opts) = @_;

    return _response(400, 'Bad Depth') if ($opts->{headers}{Depth} // '') ne '1';
    $self->_apply_scheduled_creates($path);
    return _response(404, 'Not Found') if ($self->{entries}{$path} // '') ne 'dir';

    my @children = sort
        grep { $_ ne '' && _parent($_) eq $path }
        keys %{ $self->{entries} };
    my @hrefs = (_href_for_path($path), map { _href_for_path($_) } @children);
    my $xml = '<?xml version="1.0" encoding="utf-8"?><D:multistatus xmlns:D="DAV:">'
        . join('', map {
            '<D:response><D:href>' . _xml_escape($_) . '</D:href>'
                . '<D:propstat><D:status>HTTP/1.1 200 OK</D:status></D:propstat>'
                . '</D:response>'
        } @hrefs)
        . '</D:multistatus>';

    return _response(207, 'Multi-Status', content => $xml);
}

sub _mkcol {
    my ($self, $path) = @_;

    if (my $hook = $self->{mkcol_hook}) {
        my $response = $hook->($self, $path);
        return $response if defined $response;
    }

    return _response(405, 'Method Not Allowed') if ($self->{entries}{$path} // '') eq 'dir';
    return _response(409, 'Conflict') if ($self->{entries}{ _parent($path) } // '') ne 'dir';

    $self->{entries}{$path} = 'dir';
    return _response(201, 'Created');
}

sub _put {
    my ($self, $path, $opts) = @_;

    return _response(409, 'Conflict') if ($self->{entries}{ _parent($path) } // '') ne 'dir';
    $self->{entries}{$path} = 'file';
    return _response(201, 'Created');
}

sub _move {
    my ($self, $source, $opts) = @_;

    my $target = _path_from_url($opts->{headers}{Destination} // '');
    if (my $hook = $self->{move_hook}) {
        return $hook->($self, $source, $target);
    }

    return _response(404, 'Source Missing') if !exists $self->{entries}{$source};
    return _response(412, 'Precondition Failed')
        if ($opts->{headers}{Overwrite} // '') eq 'F' && exists $self->{entries}{$target};
    return _response(409, 'Conflict') if ($self->{entries}{ _parent($target) } // '') ne 'dir';

    $self->{entries}{$target} = delete $self->{entries}{$source};
    return _response(201, 'Created');
}

sub _fresh_state {
    return {
        entries => {
            '' => 'dir',
            $ROOT_PATH => 'dir',
        },
        calls => [],
        scheduled_creates => [],
    };
}

sub _record {
    my ($self, @call) = @_;
    push @{ $self->{calls} }, \@call;
    return;
}

sub _create_file {
    my ($self, $path) = @_;

    $path = _canon($path);
    my $parent = _parent($path);
    $self->_mkdir_internal($parent) if !exists $self->{entries}{$parent};
    $self->{entries}{$path} = 'file';
    return 1;
}

sub schedule_create_file {
    my ($self, $path, %args) = @_;

    push @{ $self->{scheduled_creates} }, {
        path      => _canon($path),
        parent    => _parent($path),
        remaining => $args{after_propfinds} // 1,
        type      => 'file',
    };
    return 1;
}

sub schedule_create_dir {
    my ($self, $path, %args) = @_;

    push @{ $self->{scheduled_creates} }, {
        path      => _canon($path),
        parent    => _parent($path),
        remaining => $args{after_propfinds} // 1,
        type      => 'dir',
    };
    return 1;
}

sub _apply_scheduled_creates {
    my ($self, $listed_path) = @_;

    my @remaining;
    for my $item (@{ $self->{scheduled_creates} }) {
        if ($item->{parent} eq $listed_path) {
            $item->{remaining}--;
            if ($item->{remaining} <= 0) {
                if (($item->{type} // 'file') eq 'dir') {
                    $self->_mkdir_internal($item->{path});
                }
                else {
                    $self->_create_file($item->{path});
                }
                next;
            }
        }
        push @remaining, $item;
    }
    $self->{scheduled_creates} = \@remaining;
    return 1;
}

sub _mkdir_internal {
    my ($self, $path) = @_;

    $path = _canon($path);
    return if $path eq '';

    my $current = '';
    for my $component (split m{/+}, $path) {
        $current = $current eq '' ? $component : "$current/$component";
        $self->{entries}{$current} = 'dir';
    }

    return;
}

sub _path_from_url {
    my ($url) = @_;
    $url =~ s{\Ahttps?://[^/]*}{}i;
    $url =~ s/[?#].*\z//;
    return _canon(_percent_decode($url));
}

sub _href_for_path {
    my ($path) = @_;
    my $href = join '/', map { _url_encode($_) } grep { $_ ne '' } split m{/+}, _canon($path);
    return "/$href";
}

sub _canon {
    my ($path) = @_;
    $path //= '';
    $path =~ s{\A/+}{};
    $path =~ s{/+\z}{};
    return $path;
}

sub _parent {
    my ($path) = @_;
    $path = _canon($path);
    return '' if $path !~ m{/};
    $path =~ s{/[^/]+\z}{};
    return $path;
}

sub _basename {
    my ($path) = @_;

    $path = _canon($path);
    $path =~ s{\A.*/}{};
    return $path;
}

sub _url_encode {
    my ($value) = @_;
    $value =~ s{([^A-Za-z0-9._~-])}{sprintf '%%%02X', ord($1)}eg;
    return $value;
}

sub _percent_decode {
    my ($value) = @_;
    $value =~ s/%([0-9A-Fa-f]{2})/chr hex $1/eg;
    return $value;
}

sub _xml_escape {
    my ($value) = @_;
    $value =~ s/&/&amp;/g;
    $value =~ s/</&lt;/g;
    $value =~ s/>/&gt;/g;
    return $value;
}

sub _response {
    my ($status, $reason, %args) = @_;
    return {
        status  => $status,
        reason  => $reason,
        success => $status >= 200 && $status < 300 ? 1 : 0,
        headers => $args{headers} // {},
        content => $args{content} // '',
    };
}
