use v5.34;
use strict;
use warnings;

use FindBin;
use File::Spec;
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::CLI;

my $cross_dir   = "$FindBin::Bin/fixtures/v1/cross-substrate";
my $signed_dir  = "$FindBin::Bin/fixtures/v1/signed-hmac";
my $fixture_key = 'gobanftp signed hmac fixture key 1';

subtest 'v1 witness surface text is a read-only inspection view' => sub {
    my ($exit, $stdout, $stderr) = _run_cli(
        'v1', 'witness',
        '--profile', 'local-goftp1',
        '--fixture', File::Spec->catdir($cross_dir, 'minimal'),
        '--surface', 'text',
    );

    is $exit, 0, 'text surface exits success';
    is $stderr, '', 'text surface has no diagnostics';
    like $stdout, qr/\AGOFTP-WITNESS-SURFACE\/1\n/, 'text surface has surface header';
    unlike $stdout, qr/^gobanftp[.]v1[.]witness=/m, 'text surface does not emit default witness header';
    like $stdout, qr/^profile_id=local-goftp1$/m, 'text surface prints profile id';
    like $stdout, qr/^adapter_id=local-listing-goftp1$/m, 'text surface prints adapter id';
    like $stdout,
        qr/^event_set_root=599c00f0614e400274a92ab1c96d09087a53d0d88bd8b0ecba481ac60a1f1461$/m,
        'text surface prints event_set_root';
    like $stdout, qr/^replay_status=ok$/m, 'text surface prints replay status';
    like $stdout, qr/^signature[.]status=unsigned$/m, 'text surface prints signature status';
    like $stdout, qr/^--- projection[.]board ---$/m, 'text surface includes board projection';
    like $stdout, qr/^3 B \. \.$/m, 'text surface includes board text';
    like $stdout, qr/^--- projection[.]sgf_main ---$/m, 'text surface includes SGF projection';
};

subtest 'v1 witness surface html is static stdout only' => sub {
    my ($exit, $stdout, $stderr) = _run_cli(
        'v1', 'witness',
        '--profile', 'local-goftp1',
        '--fixture', File::Spec->catdir($cross_dir, 'minimal'),
        '--surface=html',
    );

    is $exit, 0, 'HTML surface exits success';
    is $stderr, '', 'HTML surface has no diagnostics';
    like $stdout, qr/\A<!doctype html>\n/, 'HTML surface starts with doctype';
    unlike $stdout, qr/^gobanftp[.]v1[.]witness=/m, 'HTML surface does not emit default witness header';
    like $stdout,
        qr/<dt>event_set_root<\/dt><dd>599c00f0614e400274a92ab1c96d09087a53d0d88bd8b0ecba481ac60a1f1461<\/dd>/,
        'HTML surface includes event_set_root';
    like $stdout, qr/<dt>signature[.]status<\/dt><dd>unsigned<\/dd>/,
        'HTML surface includes signature status';
    like $stdout, qr/<h2>projection[.]board<\/h2>/, 'HTML surface includes board projection';
};

subtest 'signed-HMAC surface keeps failure diagnostics and redaction' => sub {
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
        '--surface', 'text',
    );

    is $exit, 2, 'signed failure surface preserves validation exit';
    like $stdout, qr/\AGOFTP-WITNESS-SURFACE\/1\n/, 'signed failure still renders surface';
    like $stdout, qr/^profile_id=signed-hmac-goftp1$/m, 'signed surface prints profile id';
    like $stdout, qr/^signature[.]status=failed$/m, 'signed surface reports failed signature';
    like $stderr, qr/^diagnostic .*code=wrong_signature/m, 'signature diagnostic remains on stderr';
    unlike $stdout . $stderr, qr/\Q$fixture_key\E/, 'HMAC secret is not printed';
};

subtest 'v1 witness rejects invalid surface format' => sub {
    my ($exit, $stdout, $stderr) = _run_cli(
        'v1', 'witness',
        '--profile', 'local-goftp1',
        '--fixture', File::Spec->catdir($cross_dir, 'minimal'),
        '--surface', 'json',
    );

    is $exit, 1, 'bad surface format exits usage';
    is $stdout, '', 'bad surface format prints no stdout';
    like $stderr, qr/^usage: v1 witness .*--surface text[|]html/m,
        'usage names supported surface formats';
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
