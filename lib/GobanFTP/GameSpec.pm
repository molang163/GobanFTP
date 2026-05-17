package GobanFTP::GameSpec;

use v5.34;
use strict;
use warnings;

use Carp qw(croak);
use Exporter qw(import);

our @EXPORT_OK = qw(build_basename parse parse_basename);

my $ATOM_RE = qr/[a-z0-9_-]+/;

sub build_basename {
    my (%args) = @_;

    my $game_id = $args{game_id} // $args{id};
    my $size    = $args{size} // 19;
    my $rules   = $args{rules} // 'chinese-area-v1';
    my $komi    = $args{komi_milli} // $args{komi} // 7500;
    my $black   = $args{black};
    my $white   = $args{white};

    croak 'gamespec.game_id' if !defined($game_id) || $game_id !~ /\A$ATOM_RE\z/;
    croak 'gamespec.size'
        if !defined($size) || $size !~ /\A(?:0|[1-9][0-9]*)\z/ || $size < 2 || $size > 26;
    croak 'gamespec.rules' if !defined($rules) || $rules !~ /\A$ATOM_RE\z/;
    croak 'gamespec.komi'
        if !defined($komi) || $komi !~ /\A(?:0|[1-9][0-9]*)\z/;
    croak 'gamespec.player' if !defined($black) || $black !~ /\A$ATOM_RE\z/;
    croak 'gamespec.player' if !defined($white) || $white !~ /\A$ATOM_RE\z/;

    my $descriptor = join '.',
        'g1',
        "id-$game_id",
        's' . (0 + $size),
        "r-$rules",
        'k' . (0 + $komi),
        "pb-$black",
        "pw-$white";

    my (undef, $error) = parse_basename($descriptor);
    croak $error if defined $error;

    return $descriptor;
}

sub parse {
    goto &parse_basename;
}

sub parse_basename {
    my ($name) = @_;

    my ($fields, $error) = _parse_basename($name);
    return wantarray ? ($fields, $error) : $fields;
}

sub _parse_basename {
    my ($name) = @_;

    return _error('gamespec.charset')
        if !defined $name || $name !~ /\A[a-z0-9._-]+\z/;

    my @parts = split /\./, $name, -1;
    return _error('gamespec.field_count') if @parts != 7;

    return _error('gamespec.version') if $parts[0] ne 'g1';

    my ($game_id) = $parts[1] =~ /\Aid-($ATOM_RE)\z/;
    return _error('gamespec.game_id') if !defined $game_id;

    my ($size_text) = $parts[2] =~ /\As([1-9][0-9]*)\z/;
    return _error('gamespec.size') if !defined $size_text;

    my $size = 0 + $size_text;
    return _error('gamespec.size') if $size < 2 || $size > 26;

    my ($rules) = $parts[3] =~ /\Ar-($ATOM_RE)\z/;
    return _error('gamespec.rules') if !defined $rules;

    my ($komi_text) = $parts[4] =~ /\Ak(0|[1-9][0-9]*)\z/;
    return _error('gamespec.komi') if !defined $komi_text;

    my ($black) = $parts[5] =~ /\Apb-($ATOM_RE)\z/;
    my ($white) = $parts[6] =~ /\Apw-($ATOM_RE)\z/;
    return _error('gamespec.player') if !defined $black || !defined $white;

    return ({
        game_id    => $game_id,
        size       => $size,
        rules      => $rules,
        komi_milli => 0 + $komi_text,
        black      => $black,
        white      => $white,
    }, undef);
}

sub _error {
    my ($code) = @_;
    return (undef, $code);
}

1;
