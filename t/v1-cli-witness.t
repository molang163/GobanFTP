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

my $cross_dir   = "$FindBin::Bin/fixtures/v1/cross-substrate";
my $signed_dir  = "$FindBin::Bin/fixtures/v1/signed-hmac";
my $fixture_key = 'gobanftp signed hmac fixture key 1';
my $ruleset_fixture_digest = '7fff59777950a614b901c305dba319cbb1090ef5a17515d949e249611bcec432';
my $ruleset_seal = '085b851293e7cac4000baea532c4b975d1d830d6bea539ae51f50eea29c1034f';

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
    like $stdout, qr/^ruleset_id=chinese-area-v1$/m, 'prints ruleset id';
    like $stdout, qr/^ruleset_semver=1\.0\.0$/m, 'prints ruleset semantic version';
    like $stdout, qr/^ruleset_seal_version=GOFTP-RULESET-SEAL\/1$/m,
        'prints ruleset seal version';
    like $stdout, qr/^ruleset_fixture_digest=\Q$ruleset_fixture_digest\E$/m,
        'prints ruleset fixture digest';
    like $stdout, qr/^ruleset_seal=\Q$ruleset_seal\E$/m, 'prints ruleset seal';
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
    like $stdout, qr/^ruleset_id=chinese-area-v1$/m, 'signed witness prints ruleset id';
    like $stdout, qr/^ruleset_seal=\Q$ruleset_seal\E$/m, 'signed witness prints ruleset seal';
    like $stdout, qr/^attestation_count=3$/m, 'prints attestation count';
    like $stdout, qr/^trusted_hmac_key_ids=fixture-key-1$/m, 'prints public trusted key selector';
    like $stdout, qr/^signature\.status=ok$/m, 'signature status is ok';
    like $stdout, qr/^accepted_count=3$/m, 'accepts signed events';
    like $stdout, qr/^rejected_count=0$/m, 'has no signed rejection';
};

subtest 'v1 witness rejects signed-HMAC event injection without changing accepted truth' => sub {
    my $fixture = File::Spec->catdir($signed_dir, 'injected-event');
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

    is $exit, 2, 'signed injection exits validation failure';
    like $stdout, qr/^gobanftp\.v1\.witness=failed$/m, 'status is failed';
    like $stdout, qr/^raw_count=10$/m, 'prints hostile raw listing count';
    like $stdout, qr/^normalized_count=4$/m, 'normalizes the injected event';
    like $stdout, qr/^attestation_count=3$/m, 'attestation count stays at the signed baseline';
    like $stdout, qr/^trusted_hmac_key_ids=fixture-key-1$/m, 'prints public trusted key selector';
    like $stdout, qr/^accepted_count=3$/m, 'accepts the valid signed chain';
    like $stdout, qr/^rejected_count=1$/m, 'rejects only the unsigned injection';
    like $stdout, qr/^rejected_codes=missing_signature$/m, 'prints missing-signature rejection';
    like $stdout, qr/^rejected_classes=signature$/m, 'prints signature rejection class';
    like $stdout,
        qr/^event_set_root=599c00f0614e400274a92ab1c96d09087a53d0d88bd8b0ecba481ac60a1f1461$/m,
        'accepted event_set_root matches valid baseline';
    like $stdout, qr/^replay_status=ok$/m, 'accepted signed set still replays';
    like $stdout,
        qr/^canonical_ids=khjclcui7pejbv3m,bihb3re4k9hlucat,kcvtlonfje163p9q$/m,
        'canonical ids match valid baseline';
    like $stdout, qr/^signature\.status=failed$/m, 'signature status is failed';
    like $stderr, qr/^diagnostic .*code=missing_signature/m, 'diagnostic code is on stderr';
    like $stderr, qr/\bname=m1[.]p000004[.]w[.]play-cc[.]pa-kcvtlonfje163p9q[.]by-bob[.]n-inject1[.]h-nr55esqpd0ika4bt\b/,
        'diagnostic names the injected event';
    like $stderr, qr/\bevent_id=nr55esqpd0ika4bt\b/, 'diagnostic reports injected event id';
    unlike $stdout . $stderr, qr/\Q$fixture_key\E/, 'HMAC secret is never printed';
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

subtest 'v1 witness rejects trusted HMACs bound to a different payload' => sub {
    my $fixture = File::Spec->catdir($signed_dir, 'payload-mismatch');
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

    is $exit, 2, 'payload mismatch exits validation failure';
    like $stdout, qr/^gobanftp\.v1\.witness=failed$/m, 'status is failed';
    like $stdout, qr/^accepted_count=0$/m, 'accepts no payload-mismatched event';
    like $stdout, qr/^rejected_count=1$/m, 'reports one rejection';
    like $stdout, qr/^rejected_codes=wrong_signature$/m, 'prints stable rejection code';
    like $stdout, qr/^rejected_classes=signature$/m, 'prints signature rejection class';
    like $stdout, qr/^signature\.status=failed$/m, 'signature status is failed';
    like $stderr, qr/^diagnostic .*code=wrong_signature/m, 'diagnostic code is on stderr';
    like $stderr, qr/\breason=signature\.mismatch\b/,
        'diagnostic explains the payload binding mismatch';
    unlike $stdout . $stderr, qr/\Q$fixture_key\E/, 'HMAC secret is never printed';
};

subtest 'v1 witness rejects HMAC records that declare a different game' => sub {
    my $fixture = File::Spec->catdir($signed_dir, 'game-descriptor-mismatch');
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

    is $exit, 2, 'game descriptor mismatch exits validation failure';
    like $stdout, qr/^gobanftp\.v1\.witness=failed$/m, 'status is failed';
    like $stdout, qr/^accepted_count=0$/m, 'accepts no mismatched-game event';
    like $stdout, qr/^rejected_count=1$/m, 'reports one rejection';
    like $stdout, qr/^rejected_codes=wrong_signature$/m, 'prints stable rejection code';
    like $stdout, qr/^rejected_classes=signature$/m, 'prints signature rejection class';
    like $stdout, qr/^signature\.status=failed$/m, 'signature status is failed';
    like $stderr, qr/^diagnostic .*code=wrong_signature/m, 'diagnostic code is on stderr';
    like $stderr, qr/\breason=game_descriptor\.mismatch\b/,
        'diagnostic explains the declared game binding mismatch';
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

    ($exit, $stdout, $stderr) = _run_cli(
        'v1', 'witness',
        '--profile', 'signed-hmac-goftp1',
        '--fixture', File::Spec->catdir($signed_dir, 'valid'),
        '--trusted-hmac-key', 'k1.jk4bs0r77srdlpds260hka9fpp49clpg=public-key-namespace-secret',
    );

    is $exit, 1, 'GOFTP-KEY public namespace is not an HMAC trusted selector';
    is $stdout, '', 'k1 namespace usage failure writes no stdout';
    like $stderr, qr/^usage: v1 witness /m, 'k1 namespace usage is reported';
    unlike $stdout . $stderr, qr/public-key-namespace-secret|jk4bs0r77srdlpds260hka9fpp49clpg/,
        'k1 namespace failure does not print selector or key bytes';
};

subtest 'v1 witness rejects bad argument shape' => sub {
    my ($exit, $stdout, $stderr) = _run_cli('v1', 'witness', '--profile', 'local-goftp1');

    is $exit, 1, 'missing fixture exits usage';
    is $stdout, '', 'usage failure writes no stdout';
    like $stderr, qr/^usage: v1 witness /m, 'usage is reported';
};

subtest 'v1 witness reports unsupported rules without internal error' => sub {
    my $fixture = _fixture_with_game('g1.id-replay.s3.r-made-up.k0.pb-alice.pw-bob');

    my ($exit, $stdout, $stderr) = _run_cli(
        'v1', 'witness',
        '--profile', 'local-goftp1',
        '--fixture', $fixture,
    );

    is $exit, 2, 'unsupported rules exit validation failure';
    like $stdout, qr/^gobanftp\.v1\.witness=failed$/m, 'status is failed';
    like $stdout, qr/^replay_status=validation$/m, 'replay status is validation';
    like $stdout, qr/^diagnostic_codes=rules$/m, 'prints rules diagnostic code';
    like $stdout, qr/^diagnostic_classes=rules$/m, 'prints rules diagnostic class';
    unlike $stdout, qr/^ruleset_seal=/m, 'unsupported rules do not print a seal';
    like $stderr, qr/^diagnostic .*code=rules\b/m, 'rules diagnostic is on stderr';
    unlike $stderr, qr/^internal:/m, 'does not report an internal error';
};

subtest 'v1 witness reports bad game descriptors without internal error' => sub {
    my $fixture = _fixture_with_game('not-a-game');

    my ($exit, $stdout, $stderr) = _run_cli(
        'v1', 'witness',
        '--profile', 'local-goftp1',
        '--fixture', $fixture,
    );

    is $exit, 2, 'bad game descriptor exits validation failure';
    like $stdout, qr/^gobanftp\.v1\.witness=failed$/m, 'status is failed';
    like $stdout, qr/^replay_status=validation$/m, 'replay status is validation';
    like $stdout, qr/^diagnostic_codes=parse_game_descriptor$/m,
        'prints parse game descriptor code';
    like $stdout, qr/^diagnostic_classes=parse$/m, 'prints parse diagnostic class';
    unlike $stdout, qr/^ruleset_seal=/m, 'bad game descriptor does not print a seal';
    like $stderr, qr/^diagnostic .*code=parse_game_descriptor\b/m,
        'parse game descriptor diagnostic is on stderr';
    unlike $stderr, qr/^internal:/m, 'does not report an internal error';
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

sub _fixture_with_game {
    my ($game) = @_;

    my $fixture = tempdir(CLEANUP => 1);
    make_path(File::Spec->catdir($fixture, 'local-goftp1'));
    _write_text(File::Spec->catfile($fixture, 'game.name'), "$game\n");
    _write_text(File::Spec->catfile($fixture, 'local-goftp1', 'listing.names'), '');

    return $fixture;
}
