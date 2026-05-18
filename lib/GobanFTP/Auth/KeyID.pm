package GobanFTP::Auth::KeyID;

use v5.34;
use strict;
use warnings;

use bytes ();
use Carp qw(croak);
use Digest::SHA qw(sha256);
use Exporter qw(import);

our @EXPORT_OK = qw(
    key_id_for_public_key
    parse_public_key_record
);

my $KEY_ID_VERSION = 'GOFTP-KEY/1';
my $PUBLIC_KEY_VERSION = 'gobanftp-public-key-v1';
my $FIXTURE_SUITE = 'fixture-ed25519-v1';
my $BASE32HEX = '0123456789abcdefghijklmnopqrstuv';
my $KEY_DOMAIN = "$KEY_ID_VERSION\0";

sub parse_public_key_record {
    my ($text) = @_;

    croak 'record.missing' if !defined $text;

    my @lines = grep { $_ ne '' } map {
        s/\r\z//r
    } split /\n/, $text, -1;

    croak 'header' if !@lines || shift(@lines) ne $PUBLIC_KEY_VERSION;

    my %fields;
    for my $line (@lines) {
        croak 'line.format' if $line !~ /\A([A-Za-z][A-Za-z0-9_.-]*)=(.*)\z/;
        my ($key, $value) = ($1, $2);
        croak 'duplicate_field' if exists $fields{$key};
        croak 'private_material' if _private_field_name($key);
        croak 'field.nul' if index($value, "\0") >= 0;
        $fields{$key} = $value;
    }

    my $suite = $fields{suite};
    croak 'suite.missing' if !defined($suite) || $suite eq '';
    croak 'suite.unsupported' if $suite ne $FIXTURE_SUITE;

    my $public_hex = $fields{public_hex};
    croak 'public_hex.missing' if !defined($public_hex) || $public_hex eq '';
    croak 'public_hex.format' if $public_hex !~ /\A[0-9a-f]+\z/;
    croak 'public_hex.length' if length($public_hex) != 64;

    my $public_key = pack 'H*', $public_hex;
    return {
        public_key_version => $PUBLIC_KEY_VERSION,
        key_id_version     => $KEY_ID_VERSION,
        suite              => $suite,
        public_hex         => $public_hex,
        public_key_bytes   => bytes::length($public_key),
        key_id             => key_id_for_public_key(
            suite      => $suite,
            public_key => $public_key,
        ),
    };
}

sub key_id_for_public_key {
    my %args = @_ == 1 && ref($_[0]) eq 'HASH' ? %{ $_[0] } : @_;

    my $suite = $args{suite};
    croak 'suite.missing' if !defined($suite) || $suite eq '';
    croak 'suite.unsupported' if $suite ne $FIXTURE_SUITE;

    my $public_key = $args{public_key};
    if (!defined $public_key && defined $args{public_hex}) {
        croak 'public_hex.format' if $args{public_hex} !~ /\A[0-9a-f]+\z/;
        croak 'public_hex.length' if length($args{public_hex}) != 64;
        $public_key = pack 'H*', $args{public_hex};
    }

    croak 'public_key.missing' if !defined $public_key;
    croak 'public_key.length' if bytes::length($public_key) != 32;

    my $digest = sha256($KEY_DOMAIN . $suite . "\0" . $public_key . "\0");
    return 'k1.' . substr(_base32hex_no_padding($digest), 0, 32);
}

sub _private_field_name {
    my ($key) = @_;
    return $key =~ /\A(?:private|secret|seed)(?:[_-]|$)/i
        || $key =~ /(?:[_-](?:private|secret|seed))\z/i
        || $key =~ /\A(?:private_key|private_hex|secret_key|signing_seed)\z/i;
}

sub _base32hex_no_padding {
    my ($bytes) = @_;

    my $out = '';
    my ($buffer, $bits) = (0, 0);
    for my $byte (unpack 'C*', $bytes) {
        $buffer = ($buffer << 8) | $byte;
        $bits += 8;
        while ($bits >= 5) {
            $bits -= 5;
            $out .= substr($BASE32HEX, ($buffer >> $bits) & 31, 1);
        }
    }

    if ($bits > 0) {
        $out .= substr($BASE32HEX, ($buffer << (5 - $bits)) & 31, 1);
    }

    return $out;
}

1;

__END__

=head1 NAME

GobanFTP::Auth::KeyID - public fixture key identity helpers

=cut
