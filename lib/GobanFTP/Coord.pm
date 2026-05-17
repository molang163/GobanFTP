package GobanFTP::Coord;

use v5.34;
use strict;
use warnings;

use Exporter qw(import);

our @EXPORT_OK = qw(point_to_xy point_to_index index_to_point);

my $ALPHABET = 'abcdefghijklmnopqrstuvwxyz';

sub point_to_xy {
    my ($point, $size) = @_;

    my ($xy, $error) = _point_to_xy($point, $size);
    return wantarray ? ($xy, $error) : $xy;
}

sub point_to_index {
    my ($point, $size) = @_;

    my ($xy, $error) = _point_to_xy($point, $size);
    return wantarray ? (undef, $error) : undef if defined $error;

    my ($x, $y) = @$xy;
    my $index = $y * $size + $x;

    return wantarray ? ($index, undef) : $index;
}

sub index_to_point {
    my ($index, $size) = @_;

    my $error = _size_error($size) // _index_error($index, $size);
    return wantarray ? (undef, $error) : undef if defined $error;

    my $x = $index % $size;
    my $y = int($index / $size);

    my $point = substr($ALPHABET, $x, 1) . substr($ALPHABET, $y, 1);
    return wantarray ? ($point, undef) : $point;
}

sub _point_to_xy {
    my ($point, $size) = @_;

    my $error = _size_error($size);
    return _error($error) if defined $error;

    return _error('coord.point')
        if !defined($point) || $point !~ /\A([a-z])([a-z])\z/;

    my $x = index($ALPHABET, $1);
    my $y = index($ALPHABET, $2);

    return _error('coord.bounds') if $x >= $size || $y >= $size;
    return ([ $x, $y ], undef);
}

sub _size_error {
    my ($size) = @_;
    return 'coord.size'
        if !defined($size) || $size !~ /\A(?:0|[1-9][0-9]*)\z/ || $size < 1 || $size > length($ALPHABET);
    return undef;
}

sub _index_error {
    my ($index, $size) = @_;
    return 'coord.index'
        if !defined($index) || $index !~ /\A(?:0|[1-9][0-9]*)\z/;
    return 'coord.bounds' if $index >= $size * $size;
    return undef;
}

sub _error {
    my ($code) = @_;
    return (undef, $code);
}

1;

__END__

=head1 NAME

GobanFTP::Coord - SGF-style board point conversion

=cut
