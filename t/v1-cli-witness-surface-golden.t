use v5.34;
use strict;
use warnings;

use Digest::SHA qw(sha256_hex);
use FindBin;
use File::Spec;
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::CLI;

my $fixture = File::Spec->catdir(
    "$FindBin::Bin/fixtures/v1/cross-substrate",
    'minimal',
);

subtest 'minimal witness text surface is frozen' => sub {
    my ($exit, $stdout, $stderr) = _run_cli(
        'v1', 'witness',
        '--profile', 'local-goftp1',
        '--fixture', $fixture,
        '--surface', 'text',
    );

    is $exit, 0, 'text surface exits success';
    is $stderr, '', 'text surface has no diagnostics';
    is length($stdout), 3157, 'text surface byte length is frozen';
    is sha256_hex($stdout),
        '8d9f53fa8998ef1567adc39946bebad813ecd9f1692a018427aca4e5e946c1de',
        'text surface digest is frozen';
    like $stdout, qr/\AGOFTP-WITNESS-SURFACE\/1\n/, 'text surface starts with surface header';
    like $stdout,
        qr/^event_set_root=599c00f0614e400274a92ab1c96d09087a53d0d88bd8b0ecba481ac60a1f1461$/m,
        'text surface keeps root visible';
    like $stdout, qr/^--- projection[.]sgf_main ---$/m,
        'text surface keeps canonical SGF section';
    unlike $stdout, qr/^--- projection[.]sgf ---$/m,
        'text surface omits duplicate SGF aliases';
};

subtest 'minimal witness HTML surface is frozen' => sub {
    my ($exit, $stdout, $stderr) = _run_cli(
        'v1', 'witness',
        '--profile', 'local-goftp1',
        '--fixture', $fixture,
        '--surface', 'html',
    );

    is $exit, 0, 'HTML surface exits success';
    is $stderr, '', 'HTML surface has no diagnostics';
    is length($stdout), 8300, 'HTML surface byte length is frozen';
    is sha256_hex($stdout),
        '9a4fddb4388812354c33d77cff2cb4e4a4648f44751c6f2e883e2a8fe99df63f',
        'HTML surface digest is frozen';
    like $stdout, qr/\A<!doctype html>\n/, 'HTML surface starts with doctype';
    like $stdout,
        qr/<dt>event_set_root<\/dt><dd>599c00f0614e400274a92ab1c96d09087a53d0d88bd8b0ecba481ac60a1f1461<\/dd>/,
        'HTML surface keeps root visible';
    like $stdout, qr/<h2>projection[.]board<\/h2>/,
        'HTML surface includes board projection';
    like $stdout, qr/<h2>projection[.]sgf_main<\/h2>/,
        'HTML surface keeps canonical SGF section';
    unlike $stdout, qr/<h2>projection[.]sgf<\/h2>/,
        'HTML surface omits duplicate SGF aliases';
    unlike $stdout, qr/^gobanftp[.]v1[.]witness=/m,
        'HTML surface does not mix in default key/value output';
};

subtest 'minimal witness terminal surface is frozen' => sub {
    my ($exit, $stdout, $stderr) = _run_cli(
        'v1', 'witness',
        '--profile', 'local-goftp1',
        '--fixture', $fixture,
        '--surface', 'terminal',
    );

    is $exit, 0, 'terminal surface exits success';
    is $stderr, '', 'terminal surface has no diagnostics';
    is length($stdout), 1497, 'terminal surface byte length is frozen';
    is sha256_hex($stdout),
        'bd5a9004c5cb3156153369ad07df366a75c92f43209eaef74291cbee5409d5d5',
        'terminal surface digest is frozen';
    like $stdout, qr/\AGOFTP-TERMINAL-OBSERVATORY\/1\n/,
        'terminal surface starts with observatory header';
    like $stdout,
        qr/^truth[.]event_set_root=599c00f0614e400274a92ab1c96d09087a53d0d88bd8b0ecba481ac60a1f1461$/m,
        'terminal surface keeps root visible';
    like $stdout, qr/^--- observed[.]board ---$/m,
        'terminal surface keeps board section';
    like $stdout, qr/^--- observed[.]verdict ---$/m,
        'terminal surface keeps verdict section';
    unlike $stdout, qr/^--- observed[.]sgf_main ---$/m,
        'terminal surface omits full SGF projection';
    unlike $stdout, qr/^gobanftp[.]v1[.]witness=/m,
        'terminal surface does not mix in default key/value output';
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
