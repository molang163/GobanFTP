use v5.34;
use strict;
use warnings;

use FindBin;
use File::Basename qw(dirname);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use JSON::PP;
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::Auth::HMACKey qw(generate_hmac_key_record write_hmac_key_file);
use GobanFTP::Auth::PublishToken qw(sign_publish_token);
use GobanFTP::CLI;
use GobanFTP::EventSetRoot qw(event_set_root_result);
use GobanFTP::Listing qw(normalize_listing);
use GobanFTP::MovePublisher qw(build_move_name);
use GobanFTP::Store::GitTree;

my $GIT = $ENV{GOBANFTP_TEST_GIT_BINARY} // 'git';
_require_git($GIT);

my $GAME = 'g1.id-git-tree-runtime.s9.r-chinese-area-v1.k7500.pb-alice.pw-bob';
my ($MOVE_B, $ID_B) = build_move_name(
    game_descriptor => $GAME,
    ply             => 1,
    color           => 'b',
    action          => 'play-dd',
    parent_id       => 'genesis',
    player          => 'alice',
    nonce           => 'gitb',
);
my ($MOVE_W, $ID_W) = build_move_name(
    game_descriptor => $GAME,
    ply             => 2,
    color           => 'w',
    action          => 'play-ee',
    parent_id       => $ID_B,
    player          => 'bob',
    nonce           => 'gitw',
);

subtest 'Git tree store enumerates direct public tree names only' => sub {
    my $repo = _repo_with_game();
    my $store = GobanFTP::Store::GitTree->new(repo => $repo, git => $GIT);

    ok((grep { $_ eq $GAME } $store->list_names('')), 'root listing exposes the game descriptor');
    is_deeply [ $store->list_names($GAME) ], [qw(events projections sidecar tmp)],
        'game listing exposes direct public children';

    my @raw_events = $store->list_names("$GAME/events");
    is_deeply [ normalize_listing(@raw_events) ], [sort ($MOVE_B, $MOVE_W)],
        'consensus sees only valid direct event basenames';
    ok((grep { $_ eq 'not-an-event' } @raw_events),
        'non-event direct tree children may be visible but are not accepted events');
    ok(!grep({ $_ =~ m{/} } @raw_events), 'recursive paths are not returned from events/');

    ok $store->exists_name('', $GAME), 'exists_name sees the game descriptor';
    ok $store->exists_name("$GAME/events", $MOVE_B), 'exists_name sees an event basename';
    ok !$store->exists_name("$GAME/events", 'missing-event'), 'exists_name rejects a missing child';

    like _dies(sub { $store->mkdir("$GAME/tmp") }), qr/read-only/,
        'mkdir is explicitly read-only';
    like _dies(sub { $store->publish_event_name($GAME, $MOVE_B) }), qr/read-only/,
        'publish is explicitly read-only';
    like _dies(sub { $store->list_names('../outside') }), qr/dot|relative|public alphabet/,
        'path traversal is rejected before invoking git';
};

subtest 'Git blob bytes and commit metadata do not change event-set truth' => sub {
    my $repo = _repo_with_game();
    my $store = GobanFTP::Store::GitTree->new(repo => $repo, git => $GIT);

    my @before = normalize_listing($store->list_names("$GAME/events"));
    my $before_root = event_set_root_result(
        game_descriptor => $GAME,
        names           => \@before,
    )->{event_set_root};

    _write($repo, "$GAME/events/$MOVE_B", "forged payload that replay must never read\n");
    _write($repo, "$GAME/sidecar/$ID_B.json", "{\"changed\":true}\n");
    _write($repo, "$GAME/projections/oracle/board.txt", "shadow board\n");
    _write($repo, "$GAME/tmp/upload.part", "temporary debris\n");
    _git_commit($repo, 'change ignored bytes and metadata',
        GIT_AUTHOR_DATE    => '2001-02-03T04:05:06+0000',
        GIT_COMMITTER_DATE => '2030-04-05T06:07:08+0000',
    );

    my $after = GobanFTP::Store::GitTree->new(repo => $repo, git => $GIT);
    my @after = normalize_listing($after->list_names("$GAME/events"));
    my $after_root = event_set_root_result(
        game_descriptor => $GAME,
        names           => \@after,
    )->{event_set_root};

    is_deeply \@after, \@before, 'event basenames are unchanged after blob and metadata poison';
    is $after_root, $before_root, 'event_set_root ignores blob bytes and commit metadata';
};

subtest 'CLI reads a real Git tree through GOBANFTP_STORE=git-tree' => sub {
    my $repo = _repo_with_game();
    my @direct_events = normalize_listing(
        GobanFTP::Store::GitTree->new(repo => $repo, git => $GIT)->list_names("$GAME/events"),
    );
    is_deeply \@direct_events, [sort ($MOVE_B, $MOVE_W)],
        'direct git-tree store sees the same events used by CLI parity';

    my $root = event_set_root_result(
        game_descriptor => $GAME,
        names           => [$MOVE_B, $MOVE_W],
    )->{event_set_root};

    local %ENV = %ENV;
    $ENV{GOBANFTP_STORE} = 'git-tree';
    $ENV{GOBANFTP_GIT_REPO} = $repo;
    $ENV{GOBANFTP_GIT_TREEISH} = 'HEAD';
    $ENV{GOBANFTP_GIT_BINARY} = $GIT;

    my ($verify_exit, $verify_stdout, $verify_stderr) = _run_cli('verify', $GAME);
    is $verify_exit, 0, 'verify exits success through git-tree';
    like $verify_stdout, qr/^gobanftp\.verify=ok$/m, 'verify reports ok';
    like $verify_stdout, qr/^events=2$/m, 'verify sees two accepted events';
    like $verify_stdout, qr/^event_set_root=\Q$root\E$/m, 'verify reports the local-equivalent root';
    is $verify_stderr, '', 'verify has no diagnostics';

    my ($replay_exit, $replay_stdout, $replay_stderr) = _run_cli('replay', $GAME);
    is $replay_exit, 0, 'replay exits success through git-tree';
    like $replay_stdout, qr/^canonical_ids=\Q$ID_B,$ID_W\E$/m,
        'replay reports the same canonical chain';
    is $replay_stderr, '', 'replay has no diagnostics';

    my ($sgf_exit, $sgf_stdout, $sgf_stderr) = _run_cli('sgf', $GAME);
    is $sgf_exit, 0, 'sgf exits success through git-tree';
    like $sgf_stdout, qr/;B\[dd\]/, 'sgf renders the black move';
    like $sgf_stdout, qr/;W\[ee\]/, 'sgf renders the white move';
    is $sgf_stderr, '', 'sgf has no diagnostics';

    my ($publish_exit, $publish_stdout, $publish_stderr)
        = _run_cli('publish-move', '--nonce', 'nope', $GAME, 'ff');
    is $publish_exit, 4, 'publish-move rejects the read-only git tree store';
    is $publish_stdout, '', 'read-only publish writes no stdout';
    like $publish_stderr, qr/^storage: git tree store is read-only/m,
        'read-only publish reports the storage boundary';
};

subtest 'Git tree publish auth preflight is separate from read-only publish support' => sub {
    my $repo = _repo_with_game();
    my $auth_dir = tempdir(CLEANUP => 1);
    my ($key_path, $key) = _write_publish_key($auth_dir);
    my ($event, $event_id) = _candidate_publish_move('authgate');
    my $token_path = _write_publish_token($auth_dir, 'publish-token.jsonl',
        $key, $event, $event_id);

    local %ENV = %ENV;
    $ENV{GOBANFTP_STORE} = 'git-tree';
    $ENV{GOBANFTP_GIT_REPO} = $repo;
    $ENV{GOBANFTP_GIT_TREEISH} = 'HEAD';
    $ENV{GOBANFTP_GIT_BINARY} = $GIT;

    my ($denied_exit, $denied_stdout, $denied_stderr) = _run_cli(
        'publish-move',
        '--nonce', 'authgate',
        '--publish-auth-token', $token_path,
        '--publish-auth-trusted-hmac-key-file', $key_path,
        '--publish-auth-trusted-hmac-status', "$key->{key_id}=rotated",
        $GAME,
        'ff',
    );
    is $denied_exit, 2, 'denied publish token exits validation before git-tree publish';
    like $denied_stdout, qr/^gobanftp[.]publish-move=failed$/m,
        'denied token reports publish failure';
    like $denied_stdout, qr/^publish_auth[.]status=denied$/m,
        'denied token reports auth denial';
    like $denied_stderr, qr/diagnostic .*code=untrusted_signature.*reason=key[.]rotated/,
        'denied token reports lifecycle denial';
    unlike $denied_stderr, qr/^storage: .*read-only/m,
        'denied token does not reach the git-tree read-only publish boundary';

    my ($authorized_exit, $authorized_stdout, $authorized_stderr) = _run_cli(
        'publish-move',
        '--nonce', 'authgate',
        '--publish-auth-token', $token_path,
        '--publish-auth-trusted-hmac-key-file', $key_path,
        $GAME,
        'ff',
    );
    is $authorized_exit, 4, 'authorized token still exits storage failure for git-tree';
    unlike $authorized_stdout, qr/^gobanftp[.]publish-move=ok$/m,
        'authorized token does not turn git-tree into a publish-capable store';
    like $authorized_stderr, qr/^storage: git tree store is read-only/m,
        'authorized token still reports the git-tree storage boundary';
};

done_testing;

sub _repo_with_game {
    my $repo = tempdir(CLEANUP => 1);

    _git($repo, 'init', '-q');
    _git($repo, 'config', 'user.email', 'gobanftp@example.invalid');
    _git($repo, 'config', 'user.name', 'GobanFTP Test');

    _write($repo, "$GAME/events/$MOVE_W", "white bytes are not consensus\n");
    _write($repo, "$GAME/events/$MOVE_B", "black bytes are not consensus\n");
    _write($repo, "$GAME/events/not-an-event/child", "recursive poison\n");
    _write($repo, "$GAME/sidecar/$ID_B.json", "{\"shadow\":true}\n");
    _write($repo, "$GAME/projections/oracle/board.txt", "projection shadow\n");
    _write($repo, "$GAME/tmp/pending.part", "tmp shadow\n");
    _write($repo, 'g1.id-other.s9.r-chinese-area-v1.k7500.pb-alice.pw-bob/events/m1.fake',
        "wrong game\n");
    _write($repo, "$GAME/events/Uppercase-Poison", "outside public alphabet\n");

    _git($repo, 'add', '.');
    _git_commit($repo, 'initial git tree game');

    return $repo;
}

sub _write {
    my ($repo, $relative, $content) = @_;

    my $path = File::Spec->catfile($repo, split m{/}, $relative);
    make_path(dirname($path));

    open my $fh, '>:raw', $path or die "open $path: $!";
    print {$fh} $content;
    close $fh or die "close $path: $!";

    return 1;
}

sub _write_publish_key {
    my ($dir) = @_;

    my $key = generate_hmac_key_record(secret => ('g' x 32));
    my $path = File::Spec->catfile($dir, 'player.hmac-key');
    write_hmac_key_file($path, $key);

    return ($path, $key);
}

sub _candidate_publish_move {
    my ($nonce) = @_;

    return build_move_name(
        game_descriptor => $GAME,
        ply             => 3,
        color           => 'b',
        action          => 'play-ff',
        parent_id       => $ID_W,
        player          => 'alice',
        nonce           => $nonce,
    );
}

sub _write_publish_token {
    my ($dir, $name, $key, $event, $event_id) = @_;

    my $token = sign_publish_token(
        profile         => 'signed-hmac-goftp1',
        game_descriptor => $GAME,
        event_basename  => $event,
        event_id        => $event_id,
        key_id          => $key->{key_id},
        key             => $key->{secret},
    );

    my $path = File::Spec->catfile($dir, $name);
    open my $fh, '>:encoding(UTF-8)', $path or die "open $path: $!";
    print {$fh} JSON::PP->new->canonical(1)->encode($token), "\n";
    close $fh or die "close $path: $!";

    return $path;
}

sub _git_commit {
    my ($repo, $message, %env) = @_;

    local %ENV = (%ENV, %env);
    _git($repo, 'add', '.');
    _git($repo, 'commit', '-q', '-m', $message);
}

sub _git {
    my ($repo, @args) = @_;

    my $status = system $GIT, '-C', $repo, @args;
    die "git @args failed with status $status" if $status != 0;

    return 1;
}

sub _require_git {
    my ($git) = @_;

    open my $fh, '-|', $git, '--version'
        or plan skip_all => 'git executable is required for Store::GitTree tests';
    my $version = <$fh>;
    close $fh
        or plan skip_all => 'git executable is required for Store::GitTree tests';

    plan skip_all => 'git executable is required for Store::GitTree tests'
        if !defined($version) || $version !~ /\Agit version /;

    return 1;
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

sub _dies {
    my ($code) = @_;

    my $error = '';
    eval { $code->(); 1 } or $error = $@;
    return $error;
}
