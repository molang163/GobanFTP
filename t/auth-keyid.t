use v5.34;
use strict;
use warnings;

use FindBin;
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::Auth::KeyID qw(
    key_id_for_public_key
    parse_public_key_record
);

my $fixture_dir = "$FindBin::Bin/fixtures/auth/keyid";
my $expected_key_id = 'k1.jk4bs0r77srdlpds260hka9fpp49clpg';
my $public_hex = '000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f';

subtest 'fixture public key record derives the documented key id' => sub {
    my $record = parse_public_key_record(_read_text("$fixture_dir/alice.pub"));

    is $record->{public_key_version}, 'gobanftp-public-key-v1', 'records public key version';
    is $record->{key_id_version}, 'GOFTP-KEY/1', 'records key-id version';
    is $record->{suite}, 'fixture-ed25519-v1', 'records fixture suite';
    is $record->{public_key_bytes}, 32, 'records public key byte length';
    is $record->{key_id}, $expected_key_id, 'derives stable k1 key id';
};

subtest 'public metadata does not change key identity' => sub {
    my $plain = parse_public_key_record(_read_text("$fixture_dir/alice.pub"));
    my $metadata = parse_public_key_record(_read_text("$fixture_dir/alice-with-metadata.pub"));

    is $metadata->{key_id}, $plain->{key_id}, 'metadata fields are excluded from key-id preimage';
    is key_id_for_public_key(suite => 'fixture-ed25519-v1', public_hex => $public_hex),
        $expected_key_id,
        'direct public_hex helper matches record parsing';
};

subtest 'malformed and private-looking records fail closed' => sub {
    like _exception(sub { parse_public_key_record(_read_text("$fixture_dir/bad-suite.pub")) }),
        qr/\Asuite[.]unsupported\b/,
        'unsupported suite is rejected';
    like _exception(sub { parse_public_key_record(_read_text("$fixture_dir/private-field-fixture.pub")) }),
        qr/\Aprivate_material\b/,
        'private-looking fields are rejected';
    like _exception(sub {
        parse_public_key_record(qq{gobanftp-public-key-v1\nsuite=fixture-ed25519-v1\npublic_hex=abc\n});
    }), qr/\Apublic_hex[.]length\b/, 'short hex is rejected';
    like _exception(sub {
        parse_public_key_record(qq{gobanftp-public-key-v1\nsuite=fixture-ed25519-v1\npublic_hex=ABCDEF\n});
    }), qr/\Apublic_hex[.]format\b/, 'uppercase or non-lowercase hex is rejected';
    like _exception(sub {
        parse_public_key_record(qq{gobanftp-public-key-v1\nsuite=fixture-ed25519-v1\nsuite=fixture-ed25519-v1\npublic_hex=$public_hex\n});
    }), qr/\Aduplicate_field\b/, 'duplicate fields are rejected';
};

done_testing;

sub _read_text {
    my ($path) = @_;

    open my $fh, '<:encoding(UTF-8)', $path or die "open $path: $!";
    local $/;
    my $text = <$fh>;
    close $fh or die "close $path: $!";
    return $text;
}

sub _exception {
    my ($code) = @_;

    my $error = '';
    eval { $code->(); 1 } or $error = $@;
    $error =~ s/\s+at \S+ line [0-9]+[.]\s*\z//;
    return $error;
}
