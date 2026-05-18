use v5.34;
use strict;
use warnings;

use FindBin;
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::CLI;

my $fixture_dir = "$FindBin::Bin/fixtures/auth/trust-report";
my $root = '599c00f0614e400274a92ab1c96d09087a53d0d88bd8b0ecba481ac60a1f1461';
my $trusted = 'k1.jk4bs0r77srdlpds260hka9fpp49clpg';
my $rotated = 'k1.j0bq17f7tnre2rmihg81jnv8ud1r1crd';
my $revoked = 'k1.b9qqr423d7t8utun0q6f9nbt9o5jcita';
my $expired = 'k1.8fqoc7krroqkucq5avbaa48qoi7p882a';

subtest 'v1 trust-report prints advisory trust state after witness truth' => sub {
    my ($exit, $stdout, $stderr) = _run_cli('v1', 'trust-report', '--fixture', "$fixture_dir/advisory-ok");

    is $exit, 0, 'advisory trust report exits success';
    is $stderr, '', 'advisory trust report has no diagnostics';
    like $stdout, qr/^gobanftp[.]v1[.]trust-report=ok$/m, 'prints ok status';
    like $stdout, qr/^fixture_id=advisory-ok$/m, 'prints safe fixture id';
    like $stdout, qr/^profile_id=local-goftp1$/m, 'uses local profile';
    like $stdout, qr/^event_set_root=\Q$root\E$/m, 'prints observed event_set_root';
    like $stdout, qr/^replay_status=ok$/m, 'prints replay status';
    like $stdout, qr/^trust[.]status=advisory$/m, 'prints advisory trust status';
    like $stdout, qr/^trust[.]public_key_count=4$/m, 'counts public keys';
    like $stdout, qr/^trust[.]record_count=4$/m, 'counts trust rows';
    like $stdout, qr/^trust[.]trusted_key_ids=\Q$trusted\E$/m, 'prints trusted key id';
    like $stdout, qr/^trust[.]rotated_key_ids=\Q$rotated\E$/m, 'prints rotated key id';
    like $stdout, qr/^trust[.]revoked_key_ids=\Q$revoked\E$/m, 'prints revoked key id';
    like $stdout, qr/^trust[.]expired_key_ids=\Q$expired\E$/m, 'prints expired key id';
    like $stdout, qr/^signature[.]status=unsigned$/m, 'trust report does not imply signed enforcement';
    unlike $stdout . $stderr, qr/public_hex|00010203|private_hex|aaaaaaaa|compromised/, 'report does not echo key material or trust reasons';
};

subtest 'missing trust material is advisory, not replay failure' => sub {
    my ($untrusted_exit, $untrusted_stdout, $untrusted_stderr)
        = _run_cli('v1', 'trust-report', '--fixture', "$fixture_dir/untrusted");
    is $untrusted_exit, 0, 'public keys without trust rows still exit success';
    is $untrusted_stderr, '', 'untrusted advisory state has no diagnostics';
    like $untrusted_stdout, qr/^event_set_root=\Q$root\E$/m, 'untrusted advisory state keeps event root';
    like $untrusted_stdout, qr/^trust[.]status=untrusted$/m, 'reports untrusted advisory state';
    like $untrusted_stdout, qr/^trust[.]public_key_count=1$/m, 'counts public key';
    like $untrusted_stdout, qr/^trust[.]record_count=0$/m, 'has no trust rows';

    my ($unsigned_exit, $unsigned_stdout, $unsigned_stderr)
        = _run_cli('v1', 'trust-report', '--fixture', "$fixture_dir/unsigned");
    is $unsigned_exit, 0, 'fixture without auth material exits success';
    is $unsigned_stderr, '', 'unsigned advisory state has no diagnostics';
    like $unsigned_stdout, qr/^event_set_root=\Q$root\E$/m, 'unsigned advisory state keeps event root';
    like $unsigned_stdout, qr/^trust[.]status=unsigned$/m, 'reports unsigned advisory state';
    like $unsigned_stdout, qr/^trust[.]public_key_count=0$/m, 'has no public keys';
    like $unsigned_stdout, qr/^trust[.]record_count=0$/m, 'has no trust rows';
};

subtest 'trust-report exit follows unsigned witness replay state' => sub {
    my ($fork_exit, $fork_stdout, $fork_stderr)
        = _run_cli('v1', 'trust-report', '--fixture', "$fixture_dir/fork");
    is $fork_exit, 3, 'fork exits conflict';
    like $fork_stdout, qr/^gobanftp[.]v1[.]trust-report=fork$/m, 'fork status is printed';
    like $fork_stdout, qr/^replay_status=fork$/m, 'fork replay status is printed';
    like $fork_stdout, qr/^trust[.]status=unsigned$/m, 'fork trust state remains advisory';
    like $fork_stderr, qr/^diagnostic .*code=fork/m, 'fork diagnostic is emitted';

    my ($validation_exit, $validation_stdout, $validation_stderr)
        = _run_cli('v1', 'trust-report', '--fixture', "$fixture_dir/validation");
    is $validation_exit, 2, 'invalid listing exits validation';
    like $validation_stdout, qr/^gobanftp[.]v1[.]trust-report=failed$/m, 'validation status is failed';
    like $validation_stdout, qr/^rejected_count=1$/m, 'invalid event is rejected before replay';
    like $validation_stdout, qr/^trust[.]status=unsigned$/m, 'validation trust state remains advisory';
    like $validation_stderr, qr/^diagnostic .*code=parse_event/m, 'parse diagnostic is emitted';
};

subtest 'malformed trust and key material fail without leaking contents' => sub {
    my ($trust_exit, $trust_stdout, $trust_stderr)
        = _run_cli('v1', 'trust-report', '--fixture', "$fixture_dir/bad-trust");
    is $trust_exit, 2, 'bad trust TSV exits validation failure';
    is $trust_stdout, "gobanftp.v1.trust-report=failed\n", 'bad trust prints failed status only';
    like $trust_stderr, qr/^diagnostic code=parse_trust error=status$/m, 'bad trust prints parse_trust diagnostic';
    unlike $trust_stdout . $trust_stderr, qr/do not leak this phrase|unknown/, 'bad trust diagnostic does not echo TSV content';

    my ($key_exit, $key_stdout, $key_stderr)
        = _run_cli('v1', 'trust-report', '--fixture', "$fixture_dir/bad-key");
    is $key_exit, 2, 'bad public key exits validation failure';
    is $key_stdout, "gobanftp.v1.trust-report=failed\n", 'bad key prints failed status only';
    like $key_stderr, qr/^diagnostic code=parse_public_key error=private_material$/m, 'bad key prints parse_public_key diagnostic';
    unlike $key_stdout . $key_stderr, qr/aaaaaaaa|private_hex/, 'bad key diagnostic does not echo key material';
};

subtest 'trust-report preserves usage and storage boundaries' => sub {
    my ($usage_exit, $usage_stdout, $usage_stderr) = _run_cli('v1', 'trust-report');
    is $usage_exit, 1, 'missing fixture exits usage';
    is $usage_stdout, '', 'usage failure has no stdout';
    like $usage_stderr, qr/^usage: v1 trust-report --fixture fixture-dir/m, 'usage names trust-report';

    my ($missing_exit, $missing_stdout, $missing_stderr)
        = _run_cli('v1', 'trust-report', '--fixture', "$fixture_dir/missing");
    is $missing_exit, 4, 'missing fixture exits storage failure';
    is $missing_stdout, '', 'storage failure has no stdout';
    like $missing_stderr, qr/^storage: open /m, 'storage failure uses storage stderr';
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
