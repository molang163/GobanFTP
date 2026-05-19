use v5.34;
use strict;
use warnings;

use FindBin;
use File::Temp qw(tempdir);
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::Auth::HMAC qw(key_id_for_secret);
use GobanFTP::Auth::HMACKey qw(
    generate_hmac_key_record
    hmac_key_record_text
    parse_hmac_key_record
    read_hmac_key_file
    write_hmac_key_file
);

subtest 'signed-HMAC key records round-trip without changing key id semantics' => sub {
    my $secret = "\x11" x 32;
    my $record = generate_hmac_key_record(
        profile    => 'signed-hmac-goftp1',
        secret_hex => unpack('H*', $secret),
    );

    is $record->{version}, 'GOFTP-HMAC-KEY/1', 'record has key version';
    is $record->{profile}, 'signed-hmac-goftp1', 'record has signed profile';
    is $record->{algorithm}, 'hmac-sha256', 'record has HMAC algorithm';
    is $record->{key_id}, key_id_for_secret($secret), 'key id uses Auth::HMAC semantics';
    is $record->{secret}, $secret, 'secret bytes are retained for verifier-local use';

    my $text = hmac_key_record_text($record);
    like $text, qr/\AGOFTP-HMAC-KEY\/1\n/, 'record text has header';
    like $text, qr/^key_id=\Q$record->{key_id}\E$/m, 'record text carries public selector';
    like $text, qr/^secret_hex=1111111111111111111111111111111111111111111111111111111111111111$/m,
        'record text carries private verifier secret';

    my $parsed = parse_hmac_key_record($text);
    is_deeply $parsed, $record, 'parsed record matches generated record';
};

subtest 'key files are exclusive and private' => sub {
    my $dir = tempdir(CLEANUP => 1);
    my $path = "$dir/hmac.key";
    my $record = generate_hmac_key_record(secret_hex => '22' x 32);

    ok write_hmac_key_file($path, $record), 'key file is written';
    my $mode = (stat $path)[2] & 07777;
    is sprintf('%04o', $mode), '0600', 'key file mode is private';
    is_deeply read_hmac_key_file($path), $record, 'key file parses back';

    chmod 0644, $path or die "chmod $path: $!";
    my $mode_error = do {
        local $@;
        eval { read_hmac_key_file($path) };
        $@;
    };
    like $mode_error, qr/mode[.]public/, 'public key file mode is rejected';
    chmod 0600, $path or die "chmod $path: $!";

    my $error = do {
        local $@;
        eval { write_hmac_key_file($path, generate_hmac_key_record(secret_hex => '33' x 32)) };
        $@;
    };
    like $error, qr/create \Q$path\E:/, 'existing key file is not overwritten';
};

subtest 'malformed key records fail with stable parse errors' => sub {
    for my $case (
        ['bad header',      "not-a-key\n",                                             qr/header/],
        ['bad profile',     "GOFTP-HMAC-KEY/1\nprofile=other\nalgorithm=hmac-sha256\nsecret_hex=" . ('44' x 32) . "\n", qr/profile[.]unsupported/],
        ['bad algorithm',   "GOFTP-HMAC-KEY/1\nprofile=signed-hmac-goftp1\nalgorithm=sha1\nsecret_hex=" . ('44' x 32) . "\n", qr/algorithm[.]unsupported/],
        ['bad secret hex',  "GOFTP-HMAC-KEY/1\nprofile=signed-hmac-goftp1\nalgorithm=hmac-sha256\nsecret_hex=SECRET\n", qr/secret_hex[.]format/],
        ['key mismatch',    "GOFTP-HMAC-KEY/1\nprofile=signed-hmac-goftp1\nalgorithm=hmac-sha256\nkey_id=wrong\nsecret_hex=" . ('44' x 32) . "\n", qr/key_id[.]mismatch/],
        ['unknown field',   "GOFTP-HMAC-KEY/1\nprofile=signed-hmac-goftp1\nalgorithm=hmac-sha256\ncomment=nope\nsecret_hex=" . ('44' x 32) . "\n", qr/field[.]unknown/],
    ) {
        my ($label, $text, $pattern) = @$case;
        my $error = do {
            local $@;
            eval { parse_hmac_key_record($text) };
            $@;
        };
        like $error, $pattern, "$label reports expected parse error";
    }
};

done_testing;
