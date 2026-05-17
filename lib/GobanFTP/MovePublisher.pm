package GobanFTP::MovePublisher;

use v5.34;
use strict;
use warnings;

use Exporter qw(import);
use Carp qw(croak);

use GobanFTP::EventID qw(event_id);
use GobanFTP::GameSpec qw(parse_basename);

our @EXPORT_OK = qw(build_move_name build_next_move_name default_nonce normalize_action);

my $EVENT_ID_RE = qr/[0-9a-v]{16}/;
my $ATOM_RE     = qr/[a-z0-9_-]+/;

sub normalize_action {
    my ($input) = @_;

    my ($action, $error) = _normalize_action($input);
    return wantarray ? ($action, $error) : $action;
}

sub build_next_move_name {
    my (%args) = @_;

    my $game_descriptor = $args{game_descriptor};
    my $result          = $args{replay_result};
    my $action          = $args{action};
    my $nonce           = $args{nonce} // default_nonce();

    croak 'game_descriptor is required' if !defined($game_descriptor) || $game_descriptor eq '';
    croak 'replay_result is required'   if !defined $result;

    my $game = _game_from_result($result, $game_descriptor);
    my @canonical_ids = _canonical_ids($result);
    my @steps = _canonical_steps($result);

    my $parent_id = @canonical_ids ? $canonical_ids[-1] : 'genesis';
    my $ply       = @canonical_ids + 1;
    my $color = @steps && ref($steps[-1]{state}) eq 'HASH'
        ? $steps[-1]{state}{next_color}
        : 'b';
    my $player = $color eq 'b' ? $game->{black}
        : $color eq 'w'        ? $game->{white}
        : undef;

    return build_move_name(
        game_descriptor => $game_descriptor,
        ply             => $ply,
        color           => $color,
        action          => $action,
        parent_id       => $parent_id,
        player          => $player,
        nonce           => $nonce,
    );
}

sub build_move_name {
    my (%args) = @_;

    my $game_descriptor = $args{game_descriptor};
    my $ply             = $args{ply};
    my $color           = $args{color};
    my $action          = $args{action};
    my $parent_id       = $args{parent_id} // $args{parent};
    my $player          = $args{player};
    my $nonce           = $args{nonce};

    croak 'game_descriptor is required' if !defined($game_descriptor) || $game_descriptor eq '';
    croak 'move.ply'
        if !defined($ply) || $ply !~ /\A(?:0|[1-9][0-9]*)\z/ || $ply < 1 || $ply > 999999;
    croak 'move.color' if !defined($color) || ($color ne 'b' && $color ne 'w');
    croak 'move.action' if !defined($action) || $action !~ /\A(?:pass|resign|play-[a-z][a-z])\z/;
    croak 'move.parent'
        if !defined($parent_id) || ($parent_id ne 'genesis' && $parent_id !~ /\A$EVENT_ID_RE\z/);
    croak 'event.player' if !defined($player) || $player !~ /\A$ATOM_RE\z/;
    croak 'event.nonce'  if !defined($nonce)  || $nonce !~ /\A[a-z0-9_-]{1,16}\z/;

    my $event_without_hash = join '.',
        'm1',
        sprintf('p%06d', $ply),
        $color,
        $action,
        "pa-$parent_id",
        "by-$player",
        "n-$nonce";

    my $id = event_id($game_descriptor, $event_without_hash);
    my $name = "$event_without_hash.h-$id";

    return wantarray ? ($name, $id) : $name;
}

sub default_nonce {
    return substr(sprintf('%x%08x', time, int(rand(0xffffffff))), 0, 16);
}

sub _normalize_action {
    my ($input) = @_;

    return (undef, 'move.action') if !defined($input) || $input eq '';
    return ($input, undef) if $input eq 'pass' || $input eq 'resign';
    return ($input, undef) if $input =~ /\Aplay-[a-z][a-z]\z/;
    return ("play-$input", undef) if $input =~ /\A[a-z][a-z]\z/;

    return (undef, 'move.action');
}

sub _game_from_result {
    my ($result, $game_descriptor) = @_;

    my $game = ref($result) && eval { $result->can('game') } ? $result->game : undef;
    return $game if ref($game) eq 'HASH';

    my ($parsed, $error) = parse_basename($game_descriptor);
    croak "invalid game descriptor: $error" if defined $error;

    return $parsed;
}

sub _canonical_ids {
    my ($result) = @_;
    return $result->canonical_ids if ref($result) && eval { $result->can('canonical_ids') };
    return @{ $result->{canonical_ids} // [] } if ref($result) eq 'HASH';
    return ();
}

sub _canonical_steps {
    my ($result) = @_;
    return $result->canonical_steps if ref($result) && eval { $result->can('canonical_steps') };
    return @{ $result->{canonical_steps} // [] } if ref($result) eq 'HASH';
    return ();
}

1;

__END__

=head1 NAME

GobanFTP::MovePublisher - build GOFTP/1 move event names

=cut
