use v5.34;
use strict;
use warnings;

use FindBin;
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use JSON::PP qw(decode_json);
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::Auth::HMACKey qw(read_hmac_key_file);
use GobanFTP::CLI;
use GobanFTP::Listing qw(normalize_listing);

my $signed_fixture = "$FindBin::Bin/fixtures/v1/signed-hmac/valid";
my $GAME = _read_single(File::Spec->catfile($signed_fixture, 'game.name'));
my @EVENTS = normalize_listing(_read_lines(
    File::Spec->catfile($signed_fixture, 'signed-hmac-goftp1', 'listing.names'),
));

subtest 'v1 keygen creates a verifier-local signed-HMAC key file' => sub {
    my $dir = tempdir(CLEANUP => 1);
    my $key_path = File::Spec->catfile($dir, 'player.hmac-key');

    my ($exit, $stdout, $stderr) = _run_cli(
        'v1', 'keygen',
        '--profile', 'signed-hmac-goftp1',
        '--out', $key_path,
    );

    is $exit, 0, 'keygen exits success';
    is $stderr, '', 'keygen has no diagnostics';
    like $stdout, qr/^gobanftp[.]v1[.]keygen=ok$/m, 'keygen prints ok status';
    like $stdout, qr/^profile_id=signed-hmac-goftp1$/m, 'keygen prints profile';
    like $stdout, qr/^algorithm=hmac-sha256$/m, 'keygen prints algorithm';
    like $stdout, qr/^key_id=[0-9a-v]{16}$/m, 'keygen prints public HMAC selector';
    like $stdout, qr/^key_path=\Q$key_path\E$/m, 'keygen prints key path';
    unlike $stdout . $stderr, qr/secret_hex|GOFTP-HMAC-KEY/, 'keygen does not print key material';
    ok -f $key_path, 'key file exists';
    if ($^O ne 'MSWin32') {
        is sprintf('%04o', ((stat $key_path)[2] & 07777)), '0600', 'key file is mode 0600';
    }
    else {
        pass 'Windows key file mode is not tested as a POSIX 0600 bitmask';
    }

    my $key = read_hmac_key_file($key_path);
    like $key->{secret_hex}, qr/\A[0-9a-f]{64}\z/, 'key file stores private HMAC secret';

    my ($again_exit, $again_stdout, $again_stderr) = _run_cli(
        'v1', 'keygen',
        '--profile', 'signed-hmac-goftp1',
        '--out', $key_path,
    );
    is $again_exit, 4, 'keygen refuses to overwrite existing key';
    is $again_stdout, '', 'overwrite failure has no stdout';
    like $again_stderr, qr/^storage: create /m, 'overwrite failure is storage-scoped';
    unlike $again_stdout . $again_stderr, qr/\Q$key->{secret_hex}\E/, 'overwrite failure does not leak secret';
};

subtest 'v1 attest generates signed-HMAC JSONL that v1 witness verifies' => sub {
    my $dir = tempdir(CLEANUP => 1);
    my $key_path = File::Spec->catfile($dir, 'player.hmac-key');
    my $attest_path = File::Spec->catfile($dir, 'attestations.jsonl');
    my $game_root = _make_game_root($dir);

    my ($keygen_exit) = _run_cli(
        'v1', 'keygen',
        '--profile', 'signed-hmac-goftp1',
        '--out', $key_path,
    );
    is $keygen_exit, 0, 'roundtrip keygen succeeds';
    my $key = read_hmac_key_file($key_path);

    my ($attest_exit, $attest_stdout, $attest_stderr) = _run_cli(
        'v1', 'attest',
        '--profile', 'signed-hmac-goftp1',
        '--key', $key_path,
        '--out', $attest_path,
        $game_root,
    );

    is $attest_exit, 0, 'attest exits success';
    is $attest_stderr, '', 'attest has no diagnostics';
    like $attest_stdout, qr/^gobanftp[.]v1[.]attest=ok$/m, 'attest prints ok status';
    like $attest_stdout, qr/^event_set_count=3$/m, 'attest signs accepted event basenames';
    like $attest_stdout, qr/^attestation_count=3$/m, 'attest reports three signatures';
    like $attest_stdout, qr/^key_id=\Q$key->{key_id}\E$/m, 'attest reports public selector';
    unlike $attest_stdout . $attest_stderr, qr/\Q$key->{secret_hex}\E|secret_hex|GOFTP-HMAC-KEY/,
        'attest does not print private key material';

    my @records = _read_jsonl($attest_path);
    is scalar(@records), 3, 'attestation JSONL has one row per accepted event';
    is_deeply [map { $_->{event_basename} } @records], \@EVENTS, 'attestation rows follow event-set order';
    is_deeply [map { $_->{key_id} } @records], [($key->{key_id}) x 3], 'attestation rows use generated selector';
    is_deeply [map { $_->{profile} } @records], [('signed-hmac-goftp1') x 3], 'attestation rows bind profile';
    is_deeply [map { $_->{algorithm} } @records], [('hmac-sha256') x 3], 'attestation rows bind algorithm';
    unlike _slurp($attest_path), qr/\Q$key->{secret_hex}\E/, 'attestation file does not contain the secret';

    my ($witness_exit, $witness_stdout, $witness_stderr) = _run_cli(
        'v1', 'witness',
        '--profile', 'signed-hmac-goftp1',
        '--fixture', $signed_fixture,
        '--attestations', $attest_path,
        '--trusted-hmac-key-file', $key_path,
    );

    is $witness_exit, 0, 'generated attestations verify under signed profile';
    is $witness_stderr, '', 'generated witness has no diagnostics';
    like $witness_stdout, qr/^gobanftp[.]v1[.]witness=ok$/m, 'witness prints ok status';
    like $witness_stdout, qr/^accepted_count=3$/m, 'signed witness accepts all generated attestations';
    like $witness_stdout, qr/^signature[.]status=ok$/m, 'signature status is ok';
    like $witness_stdout, qr/^trusted_hmac_key_ids=\Q$key->{key_id}\E$/m,
        'trusted key came from the key file';
    unlike $witness_stdout . $witness_stderr, qr/\Q$key->{secret_hex}\E/,
        'witness does not print private key material';

    my $inside_events = File::Spec->catfile($game_root, 'events', 'm2.attestations.jsonl');
    my ($inside_exit, $inside_stdout, $inside_stderr) = _run_cli(
        'v1', 'attest',
        '--profile', 'signed-hmac-goftp1',
        '--key', $key_path,
        '--out', $inside_events,
        $game_root,
    );
    is $inside_exit, 1, 'attest refuses replay-visible output under the game root';
    is $inside_stdout, '', 'replay-visible output writes no stdout';
    like $inside_stderr, qr/^usage: v1 attest /m, 'replay-visible output is a usage failure';
    ok !-e $inside_events, 'replay-visible output file is not created';
};

subtest 'v1 attest fails closed on dirty replay input before writing attestations' => sub {
    my $dir = tempdir(CLEANUP => 1);
    my $key_path = File::Spec->catfile($dir, 'player.hmac-key');
    my $attest_path = File::Spec->catfile($dir, 'dirty-attestations.jsonl');
    my $game_root = _make_game_root($dir);
    _write_text(File::Spec->catfile($game_root, 'events', 'm1.bad'), '');

    my ($keygen_exit) = _run_cli(
        'v1', 'keygen',
        '--profile', 'signed-hmac-goftp1',
        '--out', $key_path,
    );
    is $keygen_exit, 0, 'dirty replay keygen succeeds';
    my $key = read_hmac_key_file($key_path);

    my ($attest_exit, $attest_stdout, $attest_stderr) = _run_cli(
        'v1', 'attest',
        '--profile', 'signed-hmac-goftp1',
        '--key', $key_path,
        '--out', $attest_path,
        $game_root,
    );

    is $attest_exit, 2, 'attest dirty replay exits validation';
    like $attest_stdout, qr/^gobanftp[.]v1[.]attest=failed$/m, 'dirty replay prints failed status';
    like $attest_stdout, qr/^event_set_count=3$/m, 'dirty replay reports accepted clean event count';
    like $attest_stderr, qr/^diagnostic code=parse_event error=event_id[.]missing name=m1[.]bad$/m,
        'dirty replay emits parse diagnostic';
    unlike $attest_stdout . $attest_stderr, qr/\Q$key->{secret_hex}\E/,
        'dirty replay failure does not leak key material';
    ok !-e $attest_path, 'dirty replay writes no attestations';
};

subtest 'bad HMAC key files fail closed without leaking key material' => sub {
    my $dir = tempdir(CLEANUP => 1);
    my $bad_key = File::Spec->catfile($dir, 'bad.hmac-key');
    my $attest_path = File::Spec->catfile($dir, 'bad-attestations.jsonl');
    my $game_root = _make_game_root($dir);
    _write_text($bad_key, join("\n",
        'GOFTP-HMAC-KEY/1',
        'profile=signed-hmac-goftp1',
        'algorithm=hmac-sha256',
        'secret_hex=SECRETSECRETSECRETSECRETSECRET',
        '',
    ));
    chmod 0600, $bad_key or die "chmod $bad_key: $!";

    my ($attest_exit, $attest_stdout, $attest_stderr) = _run_cli(
        'v1', 'attest',
        '--profile', 'signed-hmac-goftp1',
        '--key', $bad_key,
        '--out', $attest_path,
        $game_root,
    );
    is $attest_exit, 2, 'attest bad key exits validation';
    is $attest_stdout, "gobanftp.v1.attest=failed\n", 'attest bad key prints failed status only';
    like $attest_stderr, qr/^diagnostic code=parse_hmac_key error=secret_hex[.]format$/m,
        'attest bad key prints stable parse diagnostic';
    unlike $attest_stdout . $attest_stderr, qr/SECRETSECRET/, 'attest bad key does not leak file content';
    ok !-e $attest_path, 'attest bad key writes no output file';

    my ($witness_exit, $witness_stdout, $witness_stderr) = _run_cli(
        'v1', 'witness',
        '--profile', 'signed-hmac-goftp1',
        '--fixture', $signed_fixture,
        '--attestations', File::Spec->catfile($signed_fixture, 'signed-hmac-goftp1', 'attestations.jsonl'),
        '--trusted-hmac-key-file', $bad_key,
    );
    is $witness_exit, 2, 'witness bad key exits validation';
    is $witness_stdout, "gobanftp.v1.witness=failed\n", 'witness bad key prints failed status only';
    like $witness_stderr, qr/^diagnostic code=parse_hmac_key error=secret_hex[.]format$/m,
        'witness bad key prints stable parse diagnostic';
    unlike $witness_stdout . $witness_stderr, qr/SECRETSECRET/, 'witness bad key does not leak file content';

    my $missing_key = File::Spec->catfile($dir, 'missing.hmac-key');
    my ($missing_attest_exit, $missing_attest_stdout, $missing_attest_stderr) = _run_cli(
        'v1', 'attest',
        '--profile', 'signed-hmac-goftp1',
        '--key', $missing_key,
        '--out', File::Spec->catfile($dir, 'missing-attestations.jsonl'),
        $game_root,
    );
    is $missing_attest_exit, 4, 'attest missing key exits storage';
    is $missing_attest_stdout, '', 'attest missing key has no stdout';
    like $missing_attest_stderr, qr/^storage: stat \Q$missing_key\E:/m,
        'attest missing key is storage-scoped';

    my ($missing_witness_exit, $missing_witness_stdout, $missing_witness_stderr) = _run_cli(
        'v1', 'witness',
        '--profile', 'signed-hmac-goftp1',
        '--fixture', $signed_fixture,
        '--attestations', File::Spec->catfile($signed_fixture, 'signed-hmac-goftp1', 'attestations.jsonl'),
        '--trusted-hmac-key-file', $missing_key,
    );
    is $missing_witness_exit, 4, 'witness missing key exits storage';
    is $missing_witness_stdout, '', 'witness missing key has no stdout';
    like $missing_witness_stderr, qr/^storage: stat \Q$missing_key\E:/m,
        'witness missing key is storage-scoped';
};

subtest 'malformed witness attestations are validation diagnostics' => sub {
    my $dir = tempdir(CLEANUP => 1);
    my $bad_json = File::Spec->catfile($dir, 'bad-attestations.jsonl');
    _write_text($bad_json, "{not-json\n");

    my ($bad_exit, $bad_stdout, $bad_stderr) = _run_cli(
        'v1', 'witness',
        '--profile', 'signed-hmac-goftp1',
        '--fixture', $signed_fixture,
        '--attestations', $bad_json,
        '--trusted-hmac-key', 'fixture-key-1=test-key',
    );
    is $bad_exit, 2, 'bad attestation JSON exits validation';
    is $bad_stdout, "gobanftp.v1.witness=failed\n", 'bad attestation JSON has failed status only';
    like $bad_stderr, qr/^diagnostic code=parse_attestations error=/m,
        'bad attestation JSON emits validation diagnostic';
    unlike $bad_stderr, qr/^internal:/m, 'bad attestation JSON is not internal failure';

    my $non_object = File::Spec->catfile($dir, 'non-object-attestations.jsonl');
    _write_text($non_object, "[]\n");
    my ($row_exit, $row_stdout, $row_stderr) = _run_cli(
        'v1', 'witness',
        '--profile', 'signed-hmac-goftp1',
        '--fixture', $signed_fixture,
        '--attestations', $non_object,
        '--trusted-hmac-key', 'fixture-key-1=test-key',
    );
    is $row_exit, 2, 'non-object attestation row exits validation';
    is $row_stdout, "gobanftp.v1.witness=failed\n", 'non-object attestation row has failed status only';
    like $row_stderr, qr/^diagnostic code=parse_attestations error=record[.]0$/m,
        'non-object attestation row emits validation diagnostic';

    my $long_line = File::Spec->catfile($dir, 'long-line-attestations.jsonl');
    _write_text($long_line, '{"x":"' . ('a' x 8_200) . "\"}\n");
    my ($long_exit, $long_stdout, $long_stderr) = _run_cli(
        'v1', 'witness',
        '--profile', 'signed-hmac-goftp1',
        '--fixture', $signed_fixture,
        '--attestations', $long_line,
        '--trusted-hmac-key', 'fixture-key-1=test-key',
    );
    is $long_exit, 2, 'oversized attestation JSONL line exits validation';
    is $long_stdout, "gobanftp.v1.witness=failed\n", 'oversized attestation line has failed status only';
    like $long_stderr, qr/^diagnostic code=parse_attestations error=line[.]too_long$/m,
        'oversized attestation line emits stable validation diagnostic';

    my $too_large = File::Spec->catfile($dir, 'too-large-attestations.jsonl');
    _write_text($too_large, 'x' x (1_048_576 + 1));
    my ($large_exit, $large_stdout, $large_stderr) = _run_cli(
        'v1', 'witness',
        '--profile', 'signed-hmac-goftp1',
        '--fixture', $signed_fixture,
        '--attestations', $too_large,
        '--trusted-hmac-key', 'fixture-key-1=test-key',
    );
    is $large_exit, 2, 'oversized attestation JSONL file exits validation';
    is $large_stdout, "gobanftp.v1.witness=failed\n", 'oversized attestation file has failed status only';
    like $large_stderr, qr/^diagnostic code=parse_attestations error=file[.]too_large$/m,
        'oversized attestation file emits stable validation diagnostic';

    my $too_many = File::Spec->catfile($dir, 'too-many-attestations.jsonl');
    _write_text($too_many, "{}\n" x 10_001);
    my ($many_exit, $many_stdout, $many_stderr) = _run_cli(
        'v1', 'witness',
        '--profile', 'signed-hmac-goftp1',
        '--fixture', $signed_fixture,
        '--attestations', $too_many,
        '--trusted-hmac-key', 'fixture-key-1=test-key',
    );
    is $many_exit, 2, 'too many attestation JSONL rows exit validation';
    is $many_stdout, "gobanftp.v1.witness=failed\n", 'too many attestation rows have failed status only';
    like $many_stderr, qr/^diagnostic code=parse_attestations error=record_count$/m,
        'too many attestation rows emit stable validation diagnostic';
};

subtest 'path-like output options reject control characters' => sub {
    my $dir = tempdir(CLEANUP => 1);
    my $newline_path = File::Spec->catfile($dir, "key\ninjected=1");

    my ($exit, $stdout, $stderr) = _run_cli(
        'v1', 'keygen',
        '--profile', 'signed-hmac-goftp1',
        '--out', $newline_path,
    );
    is $exit, 1, 'keygen newline path exits usage';
    is $stdout, '', 'keygen newline path has no injectable stdout';
    unlike $stderr, qr/^injected=1$/m, 'keygen newline path cannot inject a machine line';

    my $tab_path = File::Spec->catfile($dir, "key\tinjected=1");
    ($exit, $stdout, $stderr) = _run_cli(
        'v1', 'keygen',
        '--profile', 'signed-hmac-goftp1',
        '--out', $tab_path,
    );
    is $exit, 1, 'keygen tab path exits usage';
    is $stdout, '', 'keygen tab path has no injectable stdout';

    my $esc_path = File::Spec->catfile($dir, "key\einjected=1");
    ($exit, $stdout, $stderr) = _run_cli(
        'v1', 'keygen',
        '--profile', 'signed-hmac-goftp1',
        '--out', $esc_path,
    );
    is $exit, 1, 'keygen escape path exits usage';
    is $stdout, '', 'keygen escape path has no injectable stdout';

    ($exit, $stdout, $stderr) = _run_cli(
        'v1', 'keyid',
        '--fixture', "missing\ninjected=1",
    );
    is $exit, 1, 'keyid newline fixture exits usage';
    unlike $stdout . $stderr, qr/^injected=1$/m, 'keyid fixture cannot inject a machine line';

    my $missing_with_newline = File::Spec->catfile($dir, "missing\ninjected=1");
    ($exit, $stdout, $stderr) = _run_cli(
        'v1', 'keyid',
        '--fixture', $missing_with_newline,
    );
    is $exit, 1, 'keyid newline storage path is rejected before open';
    unlike $stdout . $stderr, qr/^injected=1/m, 'keyid storage path cannot split stderr';
};

done_testing;

sub _make_game_root {
    my ($dir) = @_;

    my $game_root = File::Spec->catdir($dir, $GAME);
    make_path(File::Spec->catdir($game_root, 'events'));
    make_path(File::Spec->catdir($game_root, 'tmp'));
    make_path(File::Spec->catdir($game_root, 'sidecar'));
    for my $event (@EVENTS) {
        _write_text(File::Spec->catfile($game_root, 'events', $event), '');
    }

    return $game_root;
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

sub _read_single {
    my ($path) = @_;
    my @lines = _read_lines($path);
    return $lines[0];
}

sub _read_lines {
    my ($path) = @_;

    open my $fh, '<:encoding(UTF-8)', $path or die "open $path: $!";
    my @lines = grep { $_ ne '' } map { chomp; $_ } <$fh>;
    close $fh or die "close $path: $!";
    return @lines;
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

sub _slurp {
    my ($path) = @_;

    open my $fh, '<:encoding(UTF-8)', $path or die "open $path: $!";
    my $text = do { local $/; <$fh> };
    close $fh or die "close $path: $!";
    return $text // '';
}

sub _write_text {
    my ($path, $text) = @_;

    open my $fh, '>:encoding(UTF-8)', $path or die "write $path: $!";
    print {$fh} $text;
    close $fh or die "close $path: $!";
}
