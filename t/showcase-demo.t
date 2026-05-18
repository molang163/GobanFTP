use v5.34;
use strict;
use warnings;

use FindBin;
use File::Spec;
use IPC::Open3;
use Symbol qw(gensym);
use Test::More;

my $root = File::Spec->catdir($FindBin::Bin, '..');
my $lib = File::Spec->catdir($root, 'lib');
my $script = File::Spec->catfile($root, 'script', 'gobanftp');
my $oracle = File::Spec->catfile($root, 'oracle', 'goban.pl');

my $shrine_root = File::Spec->catdir($root, qw(examples fixtures ftp-shrine));
my $shrine_game = 'g1.id-ftp-shrine.s9.r-chinese-area-v1.k7500.pb-daemon.pw-pilgrim';

my $race_root = File::Spec->catdir($root, qw(examples fixtures ftp-race-shrine));
my $race_game = 'g1.id-ftp-race-shrine.s9.r-chinese-area-v1.k7500.pb-daemon.pw-pilgrim';

my $v1_minimal = File::Spec->catdir($FindBin::Bin, qw(fixtures v1 cross-substrate minimal));

subtest 'shrine replay is the public clean path' => sub {
    my ($exit, $stdout, $stderr) = _run_gobanftp_with_root(
        $shrine_root,
        'replay',
        $shrine_game,
    );

    is $exit, 0, 'shrine replay exits success';
    is $stderr, '', 'shrine replay has no diagnostics';
    like $stdout, qr/^gobanftp\.replay=ok$/m, 'shrine replay reports ok';
    like $stdout, qr/^events=7$/m, 'shrine replay sees the fixture listing';
    like $stdout, qr/^event_set_count=7$/m, 'shrine replay prints the event-set count';
    like $stdout, qr/^event_set_root=12699daa3f344c6f65358bb36587933aed4657fbb9ddba7db8ff3909b9f451f4$/m,
        'shrine replay prints the stable event-set root';
    like $stdout, qr/^canonical_moves=6$/m, 'shrine replay reports six canonical moves';
    like $stdout, qr/^legal_moves=6$/m, 'shrine replay reports six legal moves';
    like $stdout,
        qr/^canonical_ids=0agr68rv1sp5qi21,k1kalhibnvic4mno,p3ige9epnj7c6om0,tndasisr9c6ihr0j,eqc92l6ocvbm6mgd,2m3u03ptk0oqdc91$/m,
        'shrine replay exposes the canonical prefix';
};

subtest 'shrine play --once renders the board without publishing' => sub {
    my ($exit, $stdout, $stderr) = _run_gobanftp_with_root(
        $shrine_root,
        'play',
        '--once',
        $shrine_game,
    );

    is $exit, 0, 'shrine play --once exits success';
    is $stderr, '', 'shrine play --once has no diagnostics';
    like $stdout, qr/^gobanftp\.play=ok$/m, 'play snapshot reports ok';
    like $stdout, qr/^worldline\.status=main$/m, 'play snapshot renders the main worldline';
    like $stdout, qr/^turn_color=b$/m, 'play snapshot reports the next color';
    like $stdout, qr/^turn_player=daemon$/m, 'play snapshot reports the next player';
    like $stdout, qr/^  a b c d e f g h i$/m, 'play snapshot renders board coordinates';
    like $stdout, qr/^6 \. \. \. B \. \. \. \. \.$/m, 'play snapshot renders black stones';
    like $stdout, qr/^4 \. \. \. B W W \. \. \.$/m, 'play snapshot renders white stones';
};

subtest 'race shrine exposes the conservative fork path' => sub {
    my ($exit, $stdout, $stderr) = _run_gobanftp_with_root(
        $race_root,
        'replay',
        $race_game,
    );

    is $exit, 3, 'race replay exits conflict';
    like $stdout, qr/^gobanftp\.replay=fork$/m, 'race replay reports fork';
    like $stdout, qr/^events=4$/m, 'race replay sees all visible event names';
    like $stdout, qr/^event_set_count=4$/m, 'race replay prints the event-set count';
    like $stdout, qr/^event_set_root=5c82563a8f1df92e667098ad687254a39514704b681c823bdf66b3aa51418e59$/m,
        'race replay prints the stable event-set root';
    like $stdout, qr/^canonical_moves=1$/m, 'race replay stops at the common parent';
    like $stdout, qr/^legal_moves=3$/m, 'race replay keeps both legal race children visible';
    like $stdout, qr/^canonical_ids=hihat4p8r6gaeuts$/m, 'race replay exposes the canonical prefix';
    like $stderr, qr/^diagnostic .*code=fork\b.*\bparent_id=hihat4p8r6gaeuts\b/m,
        'race replay prints the fork diagnostic';
    like $stderr, qr/\bchild_ids=o00qmn6v8j683ds6,ps9v3kftvp5v1gl5\b/,
        'race replay prints deterministic child ids';
};

subtest 'source-art oracle remains executable smoke only' => sub {
    my ($compile_exit, $compile_out, $compile_err) = _run_cmd($^X, '-I', $lib, '-c', $oracle);
    is $compile_exit, 0, 'oracle source-art passes perl -c';
    is $compile_out, '', 'oracle compile writes no stdout';
    like $compile_err, qr/\bgoban\.pl syntax OK\b/, 'oracle compile reports syntax OK';

    my ($smoke_exit, $smoke_out, $smoke_err) = _run_cmd($^X, '-I', $lib, $oracle, '--smoke');
    is $smoke_exit, 0, 'oracle source-art smoke exits success';
    is $smoke_err, '', 'oracle smoke has no diagnostics';
    like $smoke_out, qr/^gobanftp\.oracle=ok$/m, 'oracle smoke reports ok';
    like $smoke_out, qr/^game\.size=9$/m, 'oracle smoke reaches the game descriptor path';
    like $smoke_out, qr/^event\.id=[0-9a-v]{16}$/m, 'oracle smoke reaches event id calculation';
    like $smoke_out, qr/^rules\.move=ok$/m, 'oracle smoke reaches the rules module';
    like $smoke_out, qr/^inline_c=(?:missing|skip|ok value=361)$/m, 'Inline::C remains optional';
};

subtest 'v1 witness is visible from the same command surface' => sub {
    my ($exit, $stdout, $stderr) = _run_gobanftp(
        'v1',
        'witness',
        '--profile',
        'local-goftp1',
        '--fixture',
        $v1_minimal,
    );

    is $exit, 0, 'v1 witness exits success';
    is $stderr, '', 'v1 witness has no diagnostics';
    like $stdout, qr/^gobanftp\.v1\.witness=ok$/m, 'v1 witness reports ok';
    like $stdout, qr/^profile_id=local-goftp1$/m, 'v1 witness prints the profile id';
    like $stdout, qr/^adapter_id=local-listing-goftp1$/m, 'v1 witness prints the adapter id';
    like $stdout, qr/^accepted_count=3$/m, 'v1 witness accepts the minimal fixture events';
    like $stdout, qr/^rejected_count=0$/m, 'v1 witness rejects no minimal fixture events';
    like $stdout, qr/^event_set_root=599c00f0614e400274a92ab1c96d09087a53d0d88bd8b0ecba481ac60a1f1461$/m,
        'v1 witness prints the stable cross-substrate root';
    like $stdout, qr/^replay_status=ok$/m, 'v1 witness reports clean replay';
    like $stdout, qr/^signature\.status=unsigned$/m, 'v1 witness keeps unsigned profile explicit';
};

done_testing;

sub _run_gobanftp_with_root {
    my ($store_root, @args) = @_;

    local $ENV{GOBANFTP_STORE} = 'local';
    local $ENV{GOBANFTP_ROOT} = $store_root;

    return _run_gobanftp(@args);
}

sub _run_gobanftp {
    my (@args) = @_;
    return _run_cmd($^X, '-I', $lib, $script, @args);
}

sub _run_cmd {
    my (@cmd) = @_;

    my $err = gensym;
    my $pid = open3(my $in, my $out, $err, @cmd);
    close $in or die "close stdin for @cmd: $!";

    my $stdout = do { local $/; <$out> // '' };
    my $stderr = do { local $/; <$err> // '' };

    waitpid $pid, 0;
    return ($? >> 8, $stdout, $stderr);
}
