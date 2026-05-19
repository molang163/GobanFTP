use v5.34;
use strict;
use warnings;

use FindBin;
use File::Spec;
use File::Temp qw(tempdir);
use JSON::PP qw(decode_json);
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::Auth::HMACKey qw(read_hmac_key_file);
use GobanFTP::CLI;

my $game = 'g1.id-replay.s3.r-chinese-area-v1.k0.pb-alice.pw-bob';
my $event = 'm1.p000001.b.play-aa.pa-genesis.by-alice.n-chain1.h-khjclcui7pejbv3m';
my $other_event =
    'm1.p000002.w.play-bb.pa-khjclcui7pejbv3m.by-bob.n-chain2.h-bihb3re4k9hlucat';

subtest 'v1 publish-token writes a verifier-local publish authorization token' => sub {
    my $dir = tempdir(CLEANUP => 1);
    my ($key_path, $key) = _keygen($dir);
    my $token_path = File::Spec->catfile($dir, 'publish-token.jsonl');

    my ($exit, $stdout, $stderr) = _run_cli(
        'v1', 'publish-token',
        '--profile', 'signed-hmac-goftp1',
        '--key', $key_path,
        '--out', $token_path,
        $game,
        $event,
    );

    is $exit, 0, 'publish-token exits success';
    is $stderr, '', 'publish-token has no diagnostics';
    like $stdout, qr/^gobanftp[.]v1[.]publish-token=ok$/m, 'prints ok status';
    like $stdout, qr/^publish_auth[.]status=authorized$/m, 'prints authorization status';
    like $stdout, qr/^event_id=khjclcui7pejbv3m$/m, 'prints event id';
    like $stdout, qr/^key_id=\Q$key->{key_id}\E$/m, 'prints public selector';
    like $stdout, qr/^publish_token=\Q$token_path\E$/m, 'prints token path';
    unlike $stdout . $stderr, qr/\Q$key->{secret_hex}\E|secret_hex|GOFTP-HMAC-KEY/,
        'does not print HMAC secret';

    my @rows = _read_jsonl($token_path);
    is scalar(@rows), 1, 'token file has one row';
    is $rows[0]{version}, 'GOFTP-HMAC-PUBLISH/1', 'token file has publish version';
    is $rows[0]{purpose}, 'publish', 'token file has publish purpose';
    is $rows[0]{event_basename}, $event, 'token binds the event basename';
    is $rows[0]{key_id}, $key->{key_id}, 'token binds the generated selector';
    unlike _slurp($token_path), qr/\Q$key->{secret_hex}\E/, 'token file excludes HMAC secret';
};

subtest 'v1 publish-auth verifies a publish token and lifecycle status' => sub {
    my $dir = tempdir(CLEANUP => 1);
    my ($key_path, $key) = _keygen($dir);
    my $token_path = File::Spec->catfile($dir, 'publish-token.jsonl');

    my ($token_exit) = _run_cli(
        'v1', 'publish-token',
        '--profile', 'signed-hmac-goftp1',
        '--key', $key_path,
        '--out', $token_path,
        $game,
        $event,
    );
    is $token_exit, 0, 'token setup succeeds';

    my ($exit, $stdout, $stderr) = _run_cli(
        'v1', 'publish-auth',
        '--profile', 'signed-hmac-goftp1',
        '--token', $token_path,
        '--trusted-hmac-key-file', $key_path,
        $game,
        $event,
    );

    is $exit, 0, 'publish-auth exits success';
    is $stderr, '', 'publish-auth has no diagnostics';
    like $stdout, qr/^gobanftp[.]v1[.]publish-auth=authorized$/m, 'prints authorized status';
    like $stdout, qr/^publish_auth[.]status=authorized$/m, 'prints publish auth status';
    like $stdout, qr/^diagnostic_count=0$/m, 'authorized token has no diagnostics';
    unlike $stdout . $stderr, qr/\Q$key->{secret_hex}\E/, 'does not print HMAC secret';

    ($exit, $stdout, $stderr) = _run_cli(
        'v1', 'publish-auth',
        '--profile', 'signed-hmac-goftp1',
        '--token', $token_path,
        '--trusted-hmac-key-file', $key_path,
        '--trusted-hmac-status', "$key->{key_id}=rotated",
        $game,
        $event,
    );

    is $exit, 2, 'rotated key cannot authorize new publish material';
    like $stdout, qr/^gobanftp[.]v1[.]publish-auth=denied$/m, 'rotated token is denied';
    like $stdout, qr/^diagnostic_codes=untrusted_signature$/m,
        'rotated token reports trust diagnostic code';
    like $stdout, qr/^diagnostic_classes=signature$/m,
        'rotated token maps to signature class';
    like $stderr, qr/\breason=key[.]rotated\b/, 'rotated diagnostic reason is stable';
    unlike $stdout . $stderr, qr/\Q$key->{secret_hex}\E/, 'denial does not print HMAC secret';
};

subtest 'v1 publish-token refuses non-trusted lifecycle status before writing' => sub {
    my $dir = tempdir(CLEANUP => 1);
    my ($key_path, $key) = _keygen($dir);

    for my $status (qw(rotated revoked expired)) {
        my $token_path = File::Spec->catfile($dir, "publish-$status.jsonl");
        my ($exit, $stdout, $stderr) = _run_cli(
            'v1', 'publish-token',
            '--profile', 'signed-hmac-goftp1',
            '--key', $key_path,
            '--key-status', $status,
            '--out', $token_path,
            $game,
            $event,
        );

        is $exit, 2, "$status key cannot mint publish token";
        like $stdout, qr/^gobanftp[.]v1[.]publish-token=failed$/m,
            "$status prints failed status";
        like $stdout, qr/^publish_auth[.]status=denied$/m,
            "$status prints denied status";
        like $stderr, qr/\breason=key[.]\Q$status\E\b/, "$status reason is stable";
        unlike $stdout . $stderr, qr/\Q$key->{secret_hex}\E/, "$status denial redacts secret";
        ok !-e $token_path, "$status token file is not created";
    }
};

subtest 'v1 publish-auth rejects replayed or malformed publish tokens' => sub {
    my $dir = tempdir(CLEANUP => 1);
    my ($key_path, $key) = _keygen($dir);
    my $token_path = File::Spec->catfile($dir, 'publish-token.jsonl');

    my ($token_exit) = _run_cli(
        'v1', 'publish-token',
        '--profile', 'signed-hmac-goftp1',
        '--key', $key_path,
        '--out', $token_path,
        $game,
        $event,
    );
    is $token_exit, 0, 'token setup succeeds';

    my ($exit, $stdout, $stderr) = _run_cli(
        'v1', 'publish-auth',
        '--profile', 'signed-hmac-goftp1',
        '--token', $token_path,
        '--trusted-hmac-key-file', $key_path,
        $game,
        $other_event,
    );

    is $exit, 2, 'token replayed for another event is denied';
    like $stdout, qr/^gobanftp[.]v1[.]publish-auth=denied$/m, 'wrong event is denied';
    like $stdout, qr/^diagnostic_codes=wrong_signature$/m,
        'wrong event reports wrong signature';
    like $stderr, qr/\breason=event_basename[.]mismatch\b/,
        'wrong event reason is stable';
    unlike $stdout . $stderr, qr/\Q$key->{secret_hex}\E/, 'wrong event denial redacts secret';

    my $bad_token = File::Spec->catfile($dir, 'bad-token.jsonl');
    _write_text($bad_token, "not json\n");
    ($exit, $stdout, $stderr) = _run_cli(
        'v1', 'publish-auth',
        '--profile', 'signed-hmac-goftp1',
        '--token', $bad_token,
        '--trusted-hmac-key-file', $key_path,
        $game,
        $event,
    );

    is $exit, 2, 'malformed token exits validation';
    is $stdout, "gobanftp.v1.publish-auth=failed\n", 'malformed token prints failed only';
    like $stderr, qr/^diagnostic code=parse_publish_token /m,
        'malformed token emits parser diagnostic';
    unlike $stdout . $stderr, qr/\Q$key->{secret_hex}\E/, 'malformed token does not leak secret';
};

done_testing;

sub _keygen {
    my ($dir) = @_;

    my $key_path = File::Spec->catfile($dir, 'player.hmac-key');
    my ($exit, $stdout, $stderr) = _run_cli(
        'v1', 'keygen',
        '--profile', 'signed-hmac-goftp1',
        '--out', $key_path,
    );
    is $exit, 0, 'keygen setup succeeds';
    is $stderr, '', 'keygen setup has no diagnostics';
    like $stdout, qr/^gobanftp[.]v1[.]keygen=ok$/m, 'keygen setup prints ok';

    return ($key_path, read_hmac_key_file($key_path));
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

sub _read_jsonl {
    my ($path) = @_;

    open my $fh, '<:encoding(UTF-8)', $path or die "open $path: $!";
    my @rows;
    while (my $line = <$fh>) {
        chomp $line;
        next if $line =~ /\A\s*\z/;
        push @rows, decode_json($line);
    }
    close $fh or die "close $path: $!";

    return @rows;
}

sub _write_text {
    my ($path, $text) = @_;

    open my $fh, '>:encoding(UTF-8)', $path or die "write $path: $!";
    print {$fh} $text;
    close $fh or die "close $path: $!";
}

sub _slurp {
    my ($path) = @_;

    open my $fh, '<:encoding(UTF-8)', $path or die "open $path: $!";
    local $/;
    my $text = <$fh>;
    close $fh or die "close $path: $!";
    return $text;
}
