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

my $fixture_dir = "$FindBin::Bin/fixtures/v1/cross-substrate";
my $ruleset_fixture_digest = '7fff59777950a614b901c305dba319cbb1090ef5a17515d949e249611bcec432';
my $ruleset_seal = '085b851293e7cac4000baea532c4b975d1d830d6bea539ae51f50eea29c1034f';

subtest 'v1 compare-roots proves minimal roots across fixture profiles' => sub {
    my ($exit, $stdout, $stderr) = _run_cli(
        'v1', 'compare-roots',
        '--fixture', File::Spec->catdir($fixture_dir, 'minimal'),
    );

    is $exit, 0, 'matching roots exit success';
    is $stderr, '', 'matching roots have no diagnostics';
    like $stdout, qr/^gobanftp\.v1\.compare-roots=ok$/m, 'status is ok';
    like $stdout, qr/^comparison_scope=fixture-read-normalizer$/m, 'scope is explicit';
    like $stdout, qr/^fixture_id=minimal$/m, 'prints safe fixture id';
    like $stdout, qr/^profile_count=5$/m, 'compares all fixture profiles';
    like $stdout, qr/^baseline_profile=local-goftp1$/m, 'local profile is baseline';
    like $stdout, qr/^compared_fields=event_set_root$/m, 'compares only roots';
    like $stdout, qr/^mismatch_count=0$/m, 'has no mismatches';
    like $stdout, qr/^mismatch_fields=$/m, 'has no mismatched fields';
    like $stdout, qr/^accepted_count=3$/m, 'prints common accepted count';
    like $stdout,
        qr/^accepted_events=m1\.p000001\.b\.play-aa\.pa-genesis\.by-alice\.n-chain1\.h-khjclcui7pejbv3m,m1\.p000002\.w\.play-bb\.pa-khjclcui7pejbv3m\.by-bob\.n-chain2\.h-bihb3re4k9hlucat,m1\.p000003\.b\.pass\.pa-bihb3re4k9hlucat\.by-alice\.n-chain3\.h-kcvtlonfje163p9q$/m,
        'prints common accepted events';
    like $stdout, qr/^rejected_count=0$/m, 'prints common rejected count';
    like $stdout,
        qr/^event_set_root=599c00f0614e400274a92ab1c96d09087a53d0d88bd8b0ecba481ac60a1f1461$/m,
        'prints common root';
    like $stdout, qr/^profile_roots=.*local-goftp1:599c00f0614e400274a92ab1c96d09087a53d0d88bd8b0ecba481ac60a1f1461/m,
        'prints per-profile roots';
};

subtest 'v1 compare-replay proves fork replay equality' => sub {
    my ($exit, $stdout, $stderr) = _run_cli(
        'v1', 'compare-replay',
        '--fixture', File::Spec->catdir($fixture_dir, 'fork'),
    );

    is $exit, 0, 'matching fork witnesses exit success';
    is $stderr, '', 'matching fork witnesses have no diagnostics';
    like $stdout, qr/^gobanftp\.v1\.compare-replay=ok$/m, 'status is ok';
    like $stdout, qr/^compared_fields=ruleset_id,ruleset_semver,ruleset_seal_version,ruleset_fixture_digest,ruleset_seal,.*diagnostic_count/m,
        'ruleset fields and diagnostic count are compared';
    like $stdout, qr/^ruleset_id=chinese-area-v1$/m, 'prints common ruleset id';
    like $stdout, qr/^ruleset_semver=1\.0\.0$/m, 'prints common ruleset semantic version';
    like $stdout, qr/^ruleset_seal_version=GOFTP-RULESET-SEAL\/1$/m,
        'prints common ruleset seal version';
    like $stdout, qr/^ruleset_fixture_digest=\Q$ruleset_fixture_digest\E$/m,
        'prints common ruleset fixture digest';
    like $stdout, qr/^ruleset_seal=\Q$ruleset_seal\E$/m, 'prints common ruleset seal';
    like $stdout, qr/^replay_status=fork$/m, 'common replay status is fork';
    like $stdout, qr/^diagnostic_classes=fork$/m, 'common diagnostic class is fork';
    like $stdout, qr/^diagnostic_count=1$/m, 'prints common diagnostic count';
    like $stdout, qr/^mismatch_fields=$/m, 'has no mismatched replay fields';
    like $stdout, qr/^profile_replay_statuses=.*local-goftp1:fork/m,
        'prints per-profile replay statuses';
};

subtest 'v1 compare-replay treats equal validation as a successful comparison' => sub {
    my ($exit, $stdout, $stderr) = _run_cli(
        'v1', 'compare-replay',
        '--fixture', File::Spec->catdir($fixture_dir, 'bad-event-id'),
    );

    is $exit, 0, 'matching validation witnesses exit success';
    is $stderr, '', 'matching validation witnesses have no diagnostics';
    like $stdout, qr/^gobanftp\.v1\.compare-replay=ok$/m, 'status is ok';
    like $stdout, qr/^replay_status=validation$/m, 'common replay status is validation';
    like $stdout, qr/^diagnostic_classes=event-id$/m, 'common diagnostic class is event-id';
    like $stdout, qr/^rejected_classes=event-id$/m, 'common rejection class is event-id';
};

subtest 'v1 compare-replay reports ruleset seal mismatch' => sub {
    my $orig = \&GobanFTP::CLI::witness_for_listing;

    no warnings 'redefine';
    local *GobanFTP::CLI::witness_for_listing = sub {
        my %args = @_ == 1 && ref($_[0]) eq 'HASH' ? %{ $_[0] } : @_;
        my $witness = $orig->(@_);
        $witness->{ruleset_seal} = 'f' x 64
            if ($args{profile_id} // '') eq 'ftp-goftp1';
        return $witness;
    };

    my ($exit, $stdout, $stderr) = _run_cli(
        'v1', 'compare-replay',
        '--fixture', File::Spec->catdir($fixture_dir, 'minimal'),
        '--profiles', 'local-goftp1,ftp-goftp1',
    );

    is $exit, 2, 'ruleset seal mismatch exits validation failure';
    is $stderr, '', 'mismatch is reported on stdout';
    like $stdout, qr/^gobanftp\.v1\.compare-replay=failed$/m, 'status is failed';
    like $stdout, qr/^mismatch_count=1$/m, 'reports one mismatched field';
    like $stdout, qr/^mismatch_fields=ruleset_seal$/m, 'reports ruleset seal mismatch';
    like $stdout, qr/^mismatch_profiles=ftp-goftp1$/m, 'reports mismatched profile';
};

subtest 'v1 compare-roots reports fixture profile mismatch' => sub {
    my $root = tempdir(CLEANUP => 1);
    my $fixture = File::Spec->catdir($root, 'mismatch');
    make_path(
        File::Spec->catdir($fixture, 'local-goftp1'),
        File::Spec->catdir($fixture, 'ftp-goftp1'),
    );

    my $minimal = File::Spec->catdir($fixture_dir, 'minimal');
    _write_text(
        File::Spec->catfile($fixture, 'game.name'),
        _read_text(File::Spec->catfile($minimal, 'game.name')),
    );
    _write_text(
        File::Spec->catfile($fixture, 'local-goftp1', 'listing.names'),
        _read_text(File::Spec->catfile($minimal, 'local-goftp1', 'listing.names')),
    );
    _write_text(
        File::Spec->catfile($fixture, 'ftp-goftp1', 'listing.names'),
        "events/m1.p000001.b.play-aa.pa-genesis.by-alice.n-chain1.h-khjclcui7pejbv3m\n",
    );

    my ($exit, $stdout, $stderr) = _run_cli(
        'v1', 'compare-roots',
        '--fixture', $fixture,
    );

    is $exit, 2, 'mismatched roots exit validation failure';
    is $stderr, '', 'mismatch is reported on stdout';
    like $stdout, qr/^gobanftp\.v1\.compare-roots=failed$/m, 'status is failed';
    like $stdout, qr/^mismatch_count=1$/m, 'reports one mismatched field';
    like $stdout, qr/^mismatch_fields=event_set_root$/m, 'reports root mismatch';
    like $stdout, qr/^mismatch_profiles=ftp-goftp1$/m, 'reports mismatched profile';
};

subtest 'v1 compare commands support explicit profile subsets and usage failures' => sub {
    my ($exit, $stdout, $stderr) = _run_cli(
        'v1', 'compare-roots',
        '--fixture', File::Spec->catdir($fixture_dir, 'minimal'),
        '--profiles', 'local-goftp1,ftp-goftp1',
    );

    is $exit, 0, 'profile subset exits success';
    like $stdout, qr/^profiles=local-goftp1,ftp-goftp1$/m, 'uses explicit profile order';
    like $stdout, qr/^profile_count=2$/m, 'compares subset profile count';

    ($exit, $stdout, $stderr) = _run_cli('v1', 'compare-replay');
    is $exit, 1, 'missing fixture exits usage';
    is $stdout, '', 'usage failure writes no stdout';
    like $stderr, qr/^usage: v1 compare-replay /m, 'usage is reported';

    ($exit, $stdout, $stderr) = _run_cli(
        'v1', 'compare-replay',
        '--fixture', File::Spec->catdir($fixture_dir, 'minimal'),
        '--profiles', 'local-goftp1,no-such-profile',
    );
    is $exit, 1, 'unknown explicit profile exits usage';
    is $stdout, '', 'unknown profile usage failure writes no stdout';
    like $stderr, qr/^usage: v1 compare-replay /m, 'unknown profile reports compare-replay usage';

    ($exit, $stdout, $stderr) = _run_cli(
        'v1', 'compare-replay',
        '--fixture', File::Spec->catdir($fixture_dir, 'minimal'),
        '--profiles', 'local-goftp1,',
    );
    is $exit, 1, 'trailing empty profile exits usage';
    is $stdout, '', 'trailing empty profile usage failure writes no stdout';
    like $stderr, qr/^usage: v1 compare-replay /m, 'trailing empty profile reports usage';

    ($exit, $stdout, $stderr) = _run_cli(
        'v1', 'compare-roots',
        '--fixture', File::Spec->catdir($fixture_dir, 'minimal'),
        '--profiles', 'local-goftp1,signed-hmac-goftp1',
    );
    is $exit, 1, 'signed profile is outside unsigned compare matrix';
    is $stdout, '', 'signed profile usage failure writes no stdout';
    like $stderr, qr/^usage: v1 compare-roots /m, 'signed profile reports compare-roots usage';
};

subtest 'v1 compare does not print secret-shaped fixture paths' => sub {
    my $root = tempdir(CLEANUP => 1);
    my $secret_fixture_id = 'secret-fixture';
    local $ENV{GOBANFTP_TEST_SECRET} = $secret_fixture_id;
    my $fixture = File::Spec->catdir($root, $secret_fixture_id);
    make_path(
        File::Spec->catdir($fixture, 'local-goftp1'),
        File::Spec->catdir($fixture, 'ftp-goftp1'),
    );

    my $minimal = File::Spec->catdir($fixture_dir, 'minimal');
    _write_text(
        File::Spec->catfile($fixture, 'game.name'),
        _read_text(File::Spec->catfile($minimal, 'game.name')),
    );
    _write_text(
        File::Spec->catfile($fixture, 'local-goftp1', 'listing.names'),
        _read_text(File::Spec->catfile($minimal, 'local-goftp1', 'listing.names')),
    );
    _write_text(
        File::Spec->catfile($fixture, 'ftp-goftp1', 'listing.names'),
        _read_text(File::Spec->catfile($minimal, 'ftp-goftp1', 'listing.names')),
    );

    my ($exit, $stdout, $stderr) = _run_cli(
        'v1', 'compare-roots',
        '--fixture', $fixture,
    );

    is $exit, 0, 'secret-shaped fixture id still compares successfully';
    like $stdout, qr/^fixture_id=REDACTED$/m, 'secret-shaped fixture id is redacted';
    unlike $stdout . $stderr, qr/\Q$secret_fixture_id\E/, 'secret-shaped fixture path is not printed';
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

sub _read_text {
    my ($path) = @_;

    open my $fh, '<:encoding(UTF-8)', $path or die "read $path: $!";
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
