package GobanFTP::Board;

use v5.34;
use strict;
use warnings;

use Carp qw(croak);
use Digest::SHA qw(sha256_hex);

use GobanFTP::Coord qw(point_to_index);

sub new {
    my ($class, @args) = @_;

    my $size = @args == 1 ? $args[0] : do {
        my %args = @args;
        $args{size};
    };
    croak 'board.size'
        if !defined($size) || $size !~ /\A(?:0|[1-9][0-9]*)\z/ || $size < 1 || $size > 26;

    return bless {
        size  => 0 + $size,
        cells => [ (0) x ($size * $size) ],
    }, $class;
}

sub size {
    my ($self) = @_;
    return $self->{size};
}

sub copy {
    my ($self) = @_;

    return bless {
        size  => $self->{size},
        cells => [ @{ $self->{cells} } ],
    }, ref($self);
}

sub from_canonical_bytes {
    my ($class, @args) = @_;

    my %args = @args == 1 ? (canonical_bytes => $args[0]) : @args;
    my $size = $args{size};
    croak 'board.size'
        if !defined($size) || $size !~ /\A(?:0|[1-9][0-9]*)\z/ || $size < 1 || $size > 26;

    my $bytes = $args{canonical_bytes};
    croak 'board.bytes'
        if !defined($bytes) || ref($bytes) || length($bytes) != $size * $size;

    my @cells = unpack 'C*', $bytes;
    for my $cell (@cells) {
        croak 'board.bytes' if $cell > 2;
    }

    return bless {
        size  => 0 + $size,
        cells => \@cells,
    }, $class;
}

sub get {
    my ($self, $x, $y) = @_;
    return $self->{cells}->[ _xy_to_index($self, $x, $y) ];
}

sub set {
    my ($self, $x, $y, $stone) = @_;

    _assert_stone($stone);
    $self->{cells}->[ _xy_to_index($self, $x, $y) ] = 0 + $stone;

    return $self;
}

sub stone_at {
    my ($self, $point) = @_;
    return $self->{cells}->[ _point_to_index_or_croak($self, $point) ];
}

sub place {
    my ($self, $point, $stone) = @_;

    _assert_stone($stone);
    $self->{cells}->[ _point_to_index_or_croak($self, $point) ] = 0 + $stone;

    return $self;
}

sub canonical_bytes {
    my ($self) = @_;
    return pack 'C*', @{ $self->{cells} };
}

sub board_hash_sha256 {
    my ($self) = @_;
    return sha256_hex("GOFTP-BOARD/1\0" . $self->{size} . "\0" . $self->canonical_bytes);
}

sub _xy_to_index {
    my ($self, $x, $y) = @_;

    croak 'board.bounds'
        if !defined($x) || !defined($y)
        || $x !~ /\A(?:0|[1-9][0-9]*)\z/
        || $y !~ /\A(?:0|[1-9][0-9]*)\z/
        || $x >= $self->{size}
        || $y >= $self->{size};

    return $y * $self->{size} + $x;
}

sub _point_to_index_or_croak {
    my ($self, $point) = @_;

    my ($index, $error) = point_to_index($point, $self->{size});
    croak $error if defined $error;

    return $index;
}

sub _assert_stone {
    my ($stone) = @_;

    croak 'board.stone'
        if !defined($stone) || $stone !~ /\A[012]\z/;
}

1;

__END__

=head1 NAME

GobanFTP::Board - basic mutable board storage

=cut
