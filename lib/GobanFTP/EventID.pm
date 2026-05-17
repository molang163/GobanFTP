package GobanFTP::EventID;

use strict;
use warnings;

use Digest::SHA qw(sha256);
use Exporter qw(import);

our @EXPORT_OK = qw(event_id event_id_error);

my $DOMAIN = "GOFTP-EVENT/1\0";
my $BASE32HEX = '0123456789abcdefghijklmnopqrstuv';
my $EVENT_ID_RE = qr/\A[0-9a-v]+\z/;

sub event_id {
    my ($game_descriptor, $event_without_hash) = @_;

    my $digest = sha256($DOMAIN . $game_descriptor . "\0" . $event_without_hash);

    return substr _base32hex_no_padding($digest), 0, 16;
}

sub event_id_error {
    my ($game_descriptor, $event_name) = @_;

    return 'event_id.missing'
        if !defined($event_name) || $event_name !~ /\A(.+)\.h-([^.]*)\z/;

    my ($event_without_hash, $found) = ($1, $2);

    return 'event_id.length'   if length($found) != 16;
    return 'event_id.alphabet' if $found !~ $EVENT_ID_RE;
    return 'event_id.mismatch' if $found ne event_id($game_descriptor, $event_without_hash);

    return undef;
}

sub _base32hex_no_padding {
    my ($bytes) = @_;

    my $bits = 0;
    my $bit_count = 0;
    my $out = '';

    for my $byte (unpack 'C*', $bytes) {
        $bits = ($bits << 8) | $byte;
        $bit_count += 8;

        while ($bit_count >= 5) {
            $bit_count -= 5;
            $out .= substr $BASE32HEX, ($bits >> $bit_count) & 0x1f, 1;
        }

        $bits &= (1 << $bit_count) - 1;
    }

    if ($bit_count) {
        $out .= substr $BASE32HEX, ($bits << (5 - $bit_count)) & 0x1f, 1;
    }

    return $out;
}

1;

__END__

=head1 NAME

GobanFTP::EventID - GOFTP/1 domain-separated event ids

=cut
