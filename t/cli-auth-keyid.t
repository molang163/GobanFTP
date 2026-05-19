use v5.34;
use strict;
use warnings;

use FindBin;
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::CLI;

my $fixture_dir = "$FindBin::Bin/fixtures/auth/keyid";
my $expected_key_id = 'k1.jk4bs0r77srdlpds260hka9fpp49clpg';

subtest 'v1 keyid derives a fixture public key id' => sub {
    my ($exit, $stdout, $stderr) = _run_cli(
        'v1', 'keyid',
        '--fixture', "$fixture_dir/alice.pub",
    );

    is $exit, 0, 'keyid exits success';
    is $stderr, '', 'keyid has no diagnostics';
    like $stdout, qr/^gobanftp[.]v1[.]keyid=ok$/m, 'prints ok status';
    like $stdout, qr/^key_id=\Q$expected_key_id\E$/m, 'prints derived key id';
    like $stdout, qr/^key_id_version=GOFTP-KEY\/1$/m, 'prints key-id version';
    like $stdout, qr/^public_key_version=gobanftp-public-key-v1$/m, 'prints public key version';
    like $stdout, qr/^suite=fixture-ed25519-v1$/m, 'prints fixture suite';
    like $stdout, qr/^public_key_bytes=32$/m, 'prints byte length';
    unlike $stdout . $stderr, qr/public_hex=/, 'does not echo public_hex';

    my ($eq_exit, $eq_stdout, $eq_stderr) = _run_cli(
        'v1', 'keyid',
        "--fixture=$fixture_dir/alice.pub",
    );
    is $eq_exit, 0, '--fixture=file exits success';
    is $eq_stderr, '', '--fixture=file has no diagnostics';
    like $eq_stdout, qr/^key_id=\Q$expected_key_id\E$/m, '--fixture=file derives the same key id';
};

subtest 'v1 keyid reports malformed fixture records as validation failures' => sub {
    my ($exit, $stdout, $stderr) = _run_cli(
        'v1', 'keyid',
        '--fixture', "$fixture_dir/bad-suite.pub",
    );

    is $exit, 2, 'bad key record exits validation failure';
    is $stdout, "gobanftp.v1.keyid=failed\n", 'bad key record prints failed status only';
    like $stderr, qr/^diagnostic code=parse_public_key error=suite[.]unsupported$/m,
        'bad key record prints stable parse diagnostic';
    unlike $stdout . $stderr, qr/real-ed25519-v1|00010203/, 'diagnostic does not echo record contents';

    for my $case (
        ['bad-header.pub',         'header',             qr/BEGIN PRIVATE KEY|00010203/],
        ['missing-public-hex.pub', 'public_hex.missing', qr/fixture-ed25519-v1/],
        ['uppercase-hex.pub',      'public_hex.format',  qr/0A0B0C|00010203/],
        ['duplicate-field.pub',    'duplicate_field',    qr/fixture-ed25519-v1|00010203/],
    ) {
        my ($file, $error, $leak_re) = @$case;
        my ($case_exit, $case_stdout, $case_stderr) = _run_cli(
            'v1', 'keyid',
            '--fixture', "$fixture_dir/$file",
        );

        is $case_exit, 2, "$file exits validation failure";
        is $case_stdout, "gobanftp.v1.keyid=failed\n", "$file prints failed status only";
        like $case_stderr, qr/^diagnostic code=parse_public_key error=\Q$error\E$/m,
            "$file prints stable parse diagnostic";
        unlike $case_stdout . $case_stderr, $leak_re, "$file diagnostic does not echo record contents";
    }
};

subtest 'v1 keyid rejects private-looking fixture records without echoing material' => sub {
    my ($exit, $stdout, $stderr) = _run_cli(
        'v1', 'keyid',
        '--fixture', "$fixture_dir/private-field-fixture.pub",
    );

    is $exit, 2, 'private-looking key record exits validation failure';
    is $stdout, "gobanftp.v1.keyid=failed\n", 'private-looking record prints failed status only';
    like $stderr, qr/^diagnostic code=parse_public_key error=private_material$/m,
        'private-looking record prints stable parse diagnostic';
    unlike $stdout . $stderr, qr/aaaaaaaaaaaaaaaa/, 'diagnostic does not echo private-looking material';
};

subtest 'v1 keyid preserves usage and storage boundaries' => sub {
    my ($usage_exit, $usage_stdout, $usage_stderr) = _run_cli('v1', 'keyid');
    is $usage_exit, 1, 'missing fixture exits usage';
    is $usage_stdout, '', 'usage failure has no stdout';
    like $usage_stderr, qr/^usage: v1 keyid --fixture public-key-file/m,
        'usage failure names keyid command';

    my ($missing_exit, $missing_stdout, $missing_stderr) = _run_cli(
        'v1', 'keyid',
        '--fixture', "$fixture_dir/missing.pub",
    );
    is $missing_exit, 4, 'missing key file exits storage failure';
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
