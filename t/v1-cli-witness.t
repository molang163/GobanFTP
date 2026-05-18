use v5.34;
use strict;
use warnings;

use FindBin;
use File::Spec;
use File::Temp qw(tempdir);
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::CLI;

my $cross_dir   = "$FindBin::Bin/fixtures/v1/cross-substrate";
my $signed_dir  = "$FindBin::Bin/fixtures/v1/signed-hmac";
my $fixture_key = 'gobanftp signed hmac fixture key 1';

subtest 'v1 witness prints unsigned fixture witness fields' => sub {
    my ($exit, $stdout, $stderr) = _run_cli(
        'v1', 'witness',
        '--profile', 'local-goftp1',
        '--fixture', File::Spec->catdir($cross_dir, 'minimal'),
    );

    is $exit, 0, 'unsigned witness exits success';
    is $stderr, '', 'unsigned witness has no diagnostics';
    like $stdout, qr/^gobanftp\.v1\.witness=ok$/m, 'status is ok';
    like $stdout, qr/^profile_id=local-goftp1$/m, 'prints profile id';
    like $stdout, qr/^profile_consensus_version=GOFTP-PROFILE\/local-goftp1\/1$/m,
        'prints profile consensus version';
    like $stdout, qr/^adapter_id=local-listing-goftp1$/m, 'prints adapter id';
    like $stdout, qr/^raw_count=4$/m, 'prints raw count';
    like $stdout, qr/^normalized_count=3$/m, 'prints normalized count';
    like $stdout, qr/^accepted_count=3$/m, 'prints accepted count';
    like $stdout, qr/^rejected_count=0$/m, 'prints rejected count';
    like $stdout,
        qr/^event_set_root=599c00f0614e400274a92ab1c96d09087a53d0d88bd8b0ecba481ac60a1f1461$/m,
        'prints event_set_root';
    like $stdout, qr/^replay_status=ok$/m, 'prints replay status';
    like $stdout, qr/^canonical_tip=kcvtlonfje163p9q$/m, 'prints canonical tip';
    like $stdout,
        qr/^canonical_ids=khjclcui7pejbv3m,bihb3re4k9hlucat,kcvtlonfje163p9q$/m,
        'prints canonical ids';
    like $stdout, qr/^signature\.status=unsigned$/m, 'unsigned profile ignores signatures';
};

subtest 'v1 witness verifies signed-HMAC fixture attestations' => sub {
    my $fixture = File::Spec->catdir($signed_dir, 'valid');
    my $attestations = File::Spec->catfile(
        $fixture,
        'signed-hmac-goftp1',
        'attestations.jsonl',
    );

    my ($exit, $stdout, $stderr) = _run_cli(
        'v1', 'witness',
        '--profile', 'signed-hmac-goftp1',
        '--fixture', $fixture,
        '--attestations', $attestations,
        '--trusted-hmac-key', "fixture-key-1=$fixture_key",
    );

    is $exit, 0, 'signed valid witness exits success';
    is $stderr, '', 'signed valid witness has no diagnostics';
    like $stdout, qr/^gobanftp\.v1\.witness=ok$/m, 'signed status is ok';
    like $stdout, qr/^profile_id=signed-hmac-goftp1$/m, 'prints signed profile id';
    like $stdout, qr/^adapter_id=signed-hmac-listing-goftp1$/m, 'prints signed adapter id';
    like $stdout, qr/^attestation_count=3$/m, 'prints attestation count';
    like $stdout, qr/^trusted_hmac_key_ids=fixture-key-1$/m, 'prints public trusted key selector';
    like $stdout, qr/^signature\.status=ok$/m, 'signature status is ok';
    like $stdout, qr/^accepted_count=3$/m, 'accepts signed events';
    like $stdout, qr/^rejected_count=0$/m, 'has no signed rejection';
};

subtest 'v1 witness reports signed-HMAC gate failures as diagnostics' => sub {
    my $fixture = File::Spec->catdir($signed_dir, 'wrong-signature');
    my $attestations = File::Spec->catfile(
        $fixture,
        'signed-hmac-goftp1',
        'attestations.jsonl',
    );

    my ($exit, $stdout, $stderr) = _run_cli(
        'v1', 'witness',
        '--profile', 'signed-hmac-goftp1',
        '--fixture', $fixture,
        '--attestations', $attestations,
        '--trusted-hmac-key', "fixture-key-1=$fixture_key",
    );

    is $exit, 2, 'wrong signature exits validation failure';
    like $stdout, qr/^gobanftp\.v1\.witness=failed$/m, 'status is failed';
    like $stdout, qr/^accepted_count=0$/m, 'accepts no bad signature event';
    like $stdout, qr/^rejected_count=1$/m, 'reports one rejection';
    like $stdout, qr/^rejected_codes=wrong_signature$/m, 'prints rejected code';
    like $stdout, qr/^rejected_classes=signature$/m, 'prints rejected class';
    like $stdout, qr/^replay_status=ok$/m, 'replay of accepted signed set is ok';
    like $stdout, qr/^signature\.status=failed$/m, 'signature status is failed';
    like $stderr, qr/^diagnostic .*code=wrong_signature/m, 'diagnostic code is on stderr';
    like $stderr, qr/\bprofile_id=signed-hmac-goftp1\b/, 'diagnostic includes profile id';
    like $stderr, qr/\bkey_id=fixture-key-1\b/, 'diagnostic includes public key id';
    unlike $stdout . $stderr, qr/\Q$fixture_key\E/, 'HMAC secret is never printed';
};

subtest 'v1 witness keeps key selectors diagnostic-safe' => sub {
    my $fixture = File::Spec->catdir($signed_dir, 'wrong-signature');
    my $tempdir = tempdir(CLEANUP => 1);
    my $attestations = File::Spec->catfile($tempdir, 'attestations.jsonl');
    _write_text(
        $attestations,
        '{"algorithm":"hmac-sha256","event_basename":"m1.p000001.b.play-aa.pa-genesis.by-alice.n-chain1.h-khjclcui7pejbv3m","event_id":"khjclcui7pejbv3m","game_descriptor":"g1.id-replay.s3.r-chinese-area-v1.k0.pb-alice.pw-bob","key_id":"fixture key\n1","mac":"0000000000000000000000000000000000000000000000000000000000000000","profile":"signed-hmac-goftp1","signature":"0000000000000000000000000000000000000000000000000000000000000000","version":"GOFTP-HMAC-EVENT/1"}' . "\n",
    );

    my ($exit, $stdout, $stderr) = _run_cli(
        'v1', 'witness',
        '--profile', 'signed-hmac-goftp1',
        '--fixture', $fixture,
        '--attestations', $attestations,
        '--trusted-hmac-key', "fixture-key-1=$fixture_key",
    );

    is $exit, 2, 'unsafe attestation key id exits validation failure';
    like $stdout, qr/^rejected_codes=untrusted_signature$/m, 'unsafe key id is rejected';
    my @diagnostics = grep { /^diagnostic / } split /\n/, $stderr;
    is scalar(@diagnostics), 1, 'diagnostic remains one stderr line';
    like $diagnostics[0], qr/\bkey_id=fixture%20key%0A1\b/, 'unsafe key id is percent-encoded';
    unlike $stdout . $stderr, qr/key_id=fixture key/, 'raw key id whitespace is not emitted';
    unlike $stdout . $stderr, qr/\Q$fixture_key\E/, 'HMAC secret is still never printed';
};

subtest 'v1 witness redacts secret-shaped attestation key selectors' => sub {
    my $fixture = File::Spec->catdir($signed_dir, 'wrong-signature');
    my $tempdir = tempdir(CLEANUP => 1);
    my $attestations = File::Spec->catfile($tempdir, 'attestations.jsonl');
    _write_text(
        $attestations,
        '{"algorithm":"hmac-sha256","event_basename":"m1.p000001.b.play-aa.pa-genesis.by-alice.n-chain1.h-khjclcui7pejbv3m","event_id":"khjclcui7pejbv3m","game_descriptor":"g1.id-replay.s3.r-chinese-area-v1.k0.pb-alice.pw-bob","key_id":"gobanftp signed hmac fixture key 1","mac":"0000000000000000000000000000000000000000000000000000000000000000","profile":"signed-hmac-goftp1","signature":"0000000000000000000000000000000000000000000000000000000000000000","version":"GOFTP-HMAC-EVENT/1"}' . "\n",
    );

    my ($exit, $stdout, $stderr) = _run_cli(
        'v1', 'witness',
        '--profile', 'signed-hmac-goftp1',
        '--fixture', $fixture,
        '--attestations', $attestations,
        '--trusted-hmac-key', "fixture-key-1=$fixture_key",
    );

    is $exit, 2, 'secret-shaped key id exits validation failure';
    like $stdout, qr/^rejected_codes=untrusted_signature$/m, 'secret-shaped key id is rejected';
    like $stderr, qr/\bkey_id=REDACTED\b/, 'secret-shaped key id is redacted';
    unlike $stdout . $stderr, qr/\Q$fixture_key\E/, 'HMAC secret is never printed';
    unlike $stdout . $stderr, qr/gobanftp%20signed%20hmac%20fixture%20key%201/,
        'percent-encoded HMAC secret is never printed';

    _write_text(
        $attestations,
        '{"algorithm":"hmac-sha256","event_basename":"m1.p000001.b.play-aa.pa-genesis.by-alice.n-chain1.h-khjclcui7pejbv3m","event_id":"khjclcui7pejbv3m","game_descriptor":"g1.id-replay.s3.r-chinese-area-v1.k0.pb-alice.pw-bob","key_id":"secret-long","mac":"0000000000000000000000000000000000000000000000000000000000000000","profile":"signed-hmac-goftp1","signature":"0000000000000000000000000000000000000000000000000000000000000000","version":"GOFTP-HMAC-EVENT/1"}' . "\n",
    );

    ($exit, $stdout, $stderr) = _run_cli(
        'v1', 'witness',
        '--profile', 'signed-hmac-goftp1',
        '--fixture', $fixture,
        '--attestations', $attestations,
        '--trusted-hmac-key', 'short-id=secret',
        '--trusted-hmac-key', 'long-id=secret-long',
    );

    is $exit, 2, 'overlapping secret-shaped key id exits validation failure';
    like $stderr, qr/\bkey_id=REDACTED\b/, 'longest overlapping secret is redacted first';
    unlike $stdout . $stderr, qr/secret-long|REDACTED-long/,
        'overlapping HMAC secret suffix is not printed';

    _write_text(
        $attestations,
        '{"algorithm":"hmac-sha256","event_basename":"m1.p000001.b.play-aa.pa-genesis.by-alice.n-chain1.h-khjclcui7pejbv3m","event_id":"khjclcui7pejbv3m","game_descriptor":"g1.id-replay.s3.r-chinese-area-v1.k0.pb-alice.pw-bob","key_id":"gobanftp%20signed%20hmac%20fixture%20key%201","mac":"0000000000000000000000000000000000000000000000000000000000000000","profile":"signed-hmac-goftp1","signature":"0000000000000000000000000000000000000000000000000000000000000000","version":"GOFTP-HMAC-EVENT/1"}' . "\n",
    );

    ($exit, $stdout, $stderr) = _run_cli(
        'v1', 'witness',
        '--profile', 'signed-hmac-goftp1',
        '--fixture', $fixture,
        '--attestations', $attestations,
        '--trusted-hmac-key', "fixture-key-1=$fixture_key",
    );

    is $exit, 2, 'percent-encoded secret-shaped key id exits validation failure';
    like $stderr, qr/\bkey_id=REDACTED\b/, 'percent-encoded secret-shaped key id is redacted';
    unlike $stdout . $stderr, qr/gobanftp%2520signed%2520hmac%2520fixture%2520key%25201/,
        'double-encoded HMAC secret is never printed';

    _write_text(
        $attestations,
        '{"algorithm":"hmac-sha256","event_basename":"m1.p000001.b.play-aa.pa-genesis.by-alice.n-chain1.h-khjclcui7pejbv3m","event_id":"khjclcui7pejbv3m","game_descriptor":"g1.id-replay.s3.r-chinese-area-v1.k0.pb-alice.pw-bob","key_id":"gobanftp%25252520signed%25252520hmac%25252520fixture%25252520key%252525201","mac":"0000000000000000000000000000000000000000000000000000000000000000","profile":"signed-hmac-goftp1","signature":"0000000000000000000000000000000000000000000000000000000000000000","version":"GOFTP-HMAC-EVENT/1"}' . "\n",
    );

    ($exit, $stdout, $stderr) = _run_cli(
        'v1', 'witness',
        '--profile', 'signed-hmac-goftp1',
        '--fixture', $fixture,
        '--attestations', $attestations,
        '--trusted-hmac-key', "fixture-key-1=$fixture_key",
    );

    is $exit, 2, 'multi-encoded secret-shaped key id exits validation failure';
    like $stderr, qr/\bkey_id=REDACTED\b/, 'multi-encoded secret-shaped key id is redacted';
    unlike $stdout . $stderr, qr/gobanftp%2525252520signed/,
        'multi-encoded HMAC secret is never printed';
};

subtest 'v1 witness rejects unsafe trusted key selectors' => sub {
    my ($exit, $stdout, $stderr) = _run_cli(
        'v1', 'witness',
        '--profile', 'signed-hmac-goftp1',
        '--fixture', File::Spec->catdir($signed_dir, 'valid'),
        '--trusted-hmac-key', "bad key=$fixture_key",
    );

    is $exit, 1, 'unsafe trusted key id exits usage';
    is $stdout, '', 'usage failure writes no stdout';
    like $stderr, qr/^usage: v1 witness /m, 'usage is reported';
    unlike $stdout . $stderr, qr/\Q$fixture_key\E/, 'usage failure does not print HMAC secret';

    ($exit, $stdout, $stderr) = _run_cli(
        'v1', 'witness',
        '--profile', 'signed-hmac-goftp1',
        '--fixture', File::Spec->catdir($signed_dir, 'valid'),
        '--trusted-hmac-key', 'same-secret=same-secret',
    );

    is $exit, 1, 'trusted key id cannot equal key bytes';
    is $stdout, '', 'same-secret usage failure writes no stdout';
    like $stderr, qr/^usage: v1 witness /m, 'same-secret usage is reported';
    unlike $stdout . $stderr, qr/same-secret/, 'same-secret key bytes are not printed';

    ($exit, $stdout, $stderr) = _run_cli(
        'v1', 'witness',
        '--profile', 'signed-hmac-goftp1',
        '--fixture', File::Spec->catdir($signed_dir, 'valid'),
        '--trusted-hmac-key', 'public-id=secret-long',
        '--trusted-hmac-key', 'secret-long=other-secret',
    );

    is $exit, 1, 'trusted key id cannot equal any trusted key bytes';
    is $stdout, '', 'cross-key secret usage failure writes no stdout';
    like $stderr, qr/^usage: v1 witness /m, 'cross-key secret usage is reported';
    unlike $stdout . $stderr, qr/secret-long|other-secret/,
        'cross-key secret bytes are not printed';

    ($exit, $stdout, $stderr) = _run_cli(
        'v1', 'witness',
        '--profile', 'signed-hmac-goftp1',
        '--fixture', File::Spec->catdir($signed_dir, 'valid'),
        '--trusted-hmac-key', 'public-id=secret',
        '--trusted-hmac-key', 'secret-long=other-value',
    );

    is $exit, 1, 'trusted key id cannot contain any trusted key bytes';
    is $stdout, '', 'substring-secret usage failure writes no stdout';
    like $stderr, qr/^usage: v1 witness /m, 'substring-secret usage is reported';
    unlike $stdout . $stderr, qr/secret|other-value/,
        'substring secret bytes are not printed';

    ($exit, $stdout, $stderr) = _run_cli(
        'v1', 'witness',
        '--profile', 'signed-hmac-goftp1',
        '--fixture', File::Spec->catdir($signed_dir, 'valid'),
        '--trusted-hmac-key', 'secret-long=secret',
        '--trusted-hmac-key', 'secret-long=other-value',
    );

    is $exit, 1, 'duplicate trusted key id is rejected';
    is $stdout, '', 'duplicate trusted key failure writes no stdout';
    like $stderr, qr/^usage: v1 witness /m, 'duplicate trusted key usage is reported';
    unlike $stdout . $stderr, qr/secret|other-value/,
        'duplicate trusted key bytes are not printed';
};

subtest 'v1 witness rejects bad argument shape' => sub {
    my ($exit, $stdout, $stderr) = _run_cli('v1', 'witness', '--profile', 'local-goftp1');

    is $exit, 1, 'missing fixture exits usage';
    is $stdout, '', 'usage failure writes no stdout';
    like $stderr, qr/^usage: v1 witness /m, 'usage is reported';
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

sub _write_text {
    my ($path, $text) = @_;

    open my $fh, '>:encoding(UTF-8)', $path or die "write $path: $!";
    print {$fh} $text;
    close $fh or die "close $path: $!";
}
