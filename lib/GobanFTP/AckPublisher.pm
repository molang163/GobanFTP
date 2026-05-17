package GobanFTP::AckPublisher;

use v5.34;
use strict;
use warnings;

use Exporter qw(import);
use Carp qw(croak);
use Scalar::Util qw(blessed);

use GobanFTP::Event qw(fields kind);
use GobanFTP::EventID qw(event_id);
use GobanFTP::GameSpec qw(parse_basename);
use GobanFTP::MovePublisher qw(default_nonce);

our @EXPORT_OK = qw(build_ack_for_target build_ack_name);

my $EVENT_ID_RE = qr/[0-9a-v]{16}/;
my $ATOM_RE     = qr/[a-z0-9_-]+/;

sub build_ack_for_target {
    my (%args) = @_;

    my $game_descriptor = $args{game_descriptor};
    my $result          = $args{replay_result};
    my $target_id       = $args{target_id} // $args{target};
    my $nonce           = $args{nonce} // default_nonce();

    croak 'game_descriptor is required' if !defined($game_descriptor) || $game_descriptor eq '';
    croak 'replay_result is required'   if !defined $result;
    croak 'ack.target'                  if !defined($target_id) || $target_id !~ /\A$EVENT_ID_RE\z/;

    my $game  = _game_from_result($result, $game_descriptor);
    my $event = _event_by_id($result, $target_id);
    croak 'ack.target' if !defined $event;
    croak 'ack.target_move' if _kind($event) ne 'move';

    my %legal = map { $_ => 1 } _legal_ids($result);
    croak 'ack.target_legal' if !$legal{$target_id};

    my $color = _fields($event)->{color};
    my $player = $color eq 'b' ? $game->{white}
        : $color eq 'w'        ? $game->{black}
        :                        undef;

    return build_ack_name(
        game_descriptor => $game_descriptor,
        target_id       => $target_id,
        player          => $player,
        nonce           => $nonce,
    );
}

sub build_ack_name {
    my (%args) = @_;

    my $game_descriptor = $args{game_descriptor};
    my $target_id       = $args{target_id} // $args{target};
    my $player          = $args{player};
    my $nonce           = $args{nonce};

    croak 'game_descriptor is required' if !defined($game_descriptor) || $game_descriptor eq '';
    croak 'ack.target' if !defined($target_id) || $target_id !~ /\A$EVENT_ID_RE\z/;
    croak 'event.player' if !defined($player) || $player !~ /\A$ATOM_RE\z/;
    croak 'event.nonce'  if !defined($nonce)  || $nonce !~ /\A[a-z0-9_-]{1,16}\z/;

    my $event_without_hash = join '.',
        'a1',
        "t-$target_id",
        "by-$player",
        "n-$nonce";

    my $id = event_id($game_descriptor, $event_without_hash);
    my $name = "$event_without_hash.h-$id";

    return wantarray ? ($name, $id) : $name;
}

sub _game_from_result {
    my ($result, $game_descriptor) = @_;

    my $game = ref($result) && eval { $result->can('game') } ? $result->game : undef;
    return $game if ref($game) eq 'HASH';

    my ($parsed, $error) = parse_basename($game_descriptor);
    croak "invalid game descriptor: $error" if defined $error;

    return $parsed;
}

sub _event_by_id {
    my ($result, $id) = @_;

    my $events = ref($result) && eval { $result->can('events_by_id') }
        ? $result->events_by_id
        : ref($result) eq 'HASH' ? ($result->{events_by_id} // {})
        : {};

    return $events->{$id};
}

sub _legal_ids {
    my ($result) = @_;
    return $result->legal_ids if ref($result) && eval { $result->can('legal_ids') };
    return @{ $result->{legal_ids} // [] } if ref($result) eq 'HASH';
    return ();
}

sub _kind {
    my ($event) = @_;
    return $event->kind if blessed($event) && $event->can('kind');
    return kind($event);
}

sub _fields {
    my ($event) = @_;
    return $event->fields if blessed($event) && $event->can('fields');
    return fields($event);
}

1;

__END__

=head1 NAME

GobanFTP::AckPublisher - build GOFTP/1 ack event names

=cut
