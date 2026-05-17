package GobanFTP::Filename::Grammar;

use strict;
use warnings;

use Exporter qw(import);

use GobanFTP::EventID qw(event_id);

our @EXPORT_OK = qw(parse_event parse_event_filename event_id_for);

my $EVENT_ID_RE = qr/[0-9a-v]{16}/;
my $ATOM_RE     = qr/[a-z0-9_-]+/;

sub parse_event_filename {
    goto &parse_event;
}

sub parse_event {
    my ($name, %opts) = @_;

    my ($event, $error) = _parse_event($name, %opts);
    return wantarray ? ($event, $error) : $event;
}

sub event_id_for {
    my ($game_descriptor, $event_without_hash) = @_;

    die 'game_descriptor is required' if !defined $game_descriptor;
    die 'event_without_hash is required' if !defined $event_without_hash;

    return event_id($game_descriptor, $event_without_hash);
}

sub _parse_event {
    my ($name, %opts) = @_;

    return _fail('filename.empty') if !defined($name) || $name eq '';

    my @parts = split /\./, $name, -1;
    return _fail('event.version') if !@parts;

    if ($parts[0] eq 'm1') {
        return _parse_move($name, \@parts, \%opts);
    }

    if ($parts[0] eq 'a1') {
        return _parse_ack($name, \@parts, \%opts);
    }

    return _fail('event.version');
}

sub _parse_move {
    my ($name, $parts, $opts) = @_;

    return _fail('filename.charset') if !_filename_charset_ok($name, $parts);
    return _fail('event_id.missing') if !@$parts || $parts->[-1] !~ /\Ah-/;

    my ($event_id, $id_error) = _event_id_from_hash_part($parts->[-1]);
    return _fail($id_error) if defined $id_error;

    return _fail('event.field_count') if @$parts != 8;

    my ($version, $ply_part, $color, $action, $parent_part, $player_part, $nonce_part) = @$parts[0 .. 6];

    return _fail('move.ply_width') if $ply_part !~ /\Ap[0-9]{6}\z/;
    return _fail('move.color')     if $color ne 'b' && $color ne 'w';

    my %fields = (
        ply   => substr($ply_part, 1),
        color => $color,
    );

    my ($parsed_action, $point, $action_error) = _parse_action($action, _board_size($opts));
    return _fail($action_error) if defined $action_error;
    $fields{action} = $parsed_action;
    $fields{point}  = $point if defined $point;

    return _fail('move.parent') if $parent_part !~ /\Apa-(.+)\z/;
    my $parent = $1;
    return _fail('move.parent') if $parent ne 'genesis' && $parent !~ /\A$EVENT_ID_RE\z/;
    $fields{parent} = $parent;

    my ($player, $player_error) = _field_value($player_part, 'by-', 'event.player', $ATOM_RE);
    return _fail($player_error) if defined $player_error;
    $fields{player} = $player;

    my ($nonce, $nonce_error) = _field_value($nonce_part, 'n-', 'event.nonce', qr/[a-z0-9_-]{1,16}/);
    return _fail($nonce_error) if defined $nonce_error;
    $fields{nonce} = $nonce;

    $fields{event_id} = $event_id;

    my $event_without_hash = join '.', @$parts[0 .. 6];
    my $mismatch = _event_id_mismatch($opts, $event_without_hash, $event_id);
    return _fail($mismatch) if defined $mismatch;

    return _success({
        kind   => 'move',
        fields => \%fields,
    });
}

sub _parse_ack {
    my ($name, $parts, $opts) = @_;

    return _fail('filename.charset') if !_filename_charset_ok($name, $parts);
    return _fail('event_id.missing') if !@$parts || $parts->[-1] !~ /\Ah-/;

    my ($event_id, $id_error) = _event_id_from_hash_part($parts->[-1]);
    return _fail($id_error) if defined $id_error;

    return _fail('event.field_count') if @$parts != 5;

    my ($version, $target_part, $player_part, $nonce_part) = @$parts[0 .. 3];

    return _fail('ack.target') if $target_part !~ /\At-($EVENT_ID_RE)\z/;
    my $target = $1;

    my ($player, $player_error) = _field_value($player_part, 'by-', 'event.player', $ATOM_RE);
    return _fail($player_error) if defined $player_error;

    my ($nonce, $nonce_error) = _field_value($nonce_part, 'n-', 'event.nonce', qr/[a-z0-9_-]{1,16}/);
    return _fail($nonce_error) if defined $nonce_error;

    my $event_without_hash = join '.', @$parts[0 .. 3];
    my $mismatch = _event_id_mismatch($opts, $event_without_hash, $event_id);
    return _fail($mismatch) if defined $mismatch;

    return _success({
        kind   => 'ack',
        fields => {
            target   => $target,
            player   => $player,
            nonce    => $nonce,
            event_id => $event_id,
        },
    });
}

sub _filename_charset_ok {
    my ($name, $parts) = @_;

    return 1 if $name =~ /\A[a-z0-9._-]+\z/;

    return 0 if $parts->[0] ne 'm1' || @$parts < 3;

    my @normalized = @$parts;
    $normalized[2] = 'b' if $normalized[2] =~ /\A[A-Z]\z/;
    return (join('.', @normalized) =~ /\A[a-z0-9._-]+\z/) ? 1 : 0;
}

sub _event_id_from_hash_part {
    my ($hash_part) = @_;

    return (undef, 'event_id.missing')  if $hash_part !~ /\Ah-(.*)\z/;

    my $event_id = $1;
    return (undef, 'event_id.length')   if length($event_id) != 16;
    return (undef, 'event_id.alphabet') if $event_id !~ /\A$EVENT_ID_RE\z/;

    return ($event_id, undef);
}

sub _parse_action {
    my ($action, $board_size) = @_;

    return ($action, undef, undef) if $action eq 'pass' || $action eq 'resign';

    return (undef, undef, 'move.action') if $action !~ /\Aplay-([a-z][a-z])\z/;

    my $point = $1;
    return (undef, undef, 'move.point_bounds') if defined($board_size) && !_point_in_bounds($point, $board_size);

    return ($action, $point, undef);
}

sub _point_in_bounds {
    my ($point, $board_size) = @_;

    my ($x, $y) = map { ord($_) - ord('a') } split //, $point;
    return $x >= 0 && $x < $board_size && $y >= 0 && $y < $board_size;
}

sub _board_size {
    my ($opts) = @_;

    return $opts->{board_size} if defined $opts->{board_size};

    my $game_descriptor = $opts->{game_descriptor};
    return undef if !defined $game_descriptor;

    return int($1) if $game_descriptor =~ /(?:\A|\.)s([1-9][0-9]*)(?:\.|\z)/;
    return undef;
}

sub _field_value {
    my ($field, $prefix, $error, $value_re) = @_;

    return (undef, $error) if index($field, $prefix) != 0;

    my $value = substr $field, length($prefix);
    return (undef, $error) if $value !~ /\A$value_re\z/;

    return ($value, undef);
}

sub _event_id_mismatch {
    my ($opts, $event_without_hash, $event_id) = @_;

    return undef if !defined $opts->{game_descriptor};

    my $expected = event_id_for($opts->{game_descriptor}, $event_without_hash);
    return $expected eq $event_id ? undef : 'event_id.mismatch';
}

sub _success {
    my ($event) = @_;
    return ($event, undef);
}

sub _fail {
    my ($error) = @_;
    return (undef, $error);
}

1;

__END__

=head1 NAME

GobanFTP::Filename::Grammar - parse GOFTP/1 event filenames

=head1 SYNOPSIS

  my ($event, $error) = GobanFTP::Filename::Grammar::parse_event(
      $name,
      game_descriptor => $game_descriptor,
  );

=cut
