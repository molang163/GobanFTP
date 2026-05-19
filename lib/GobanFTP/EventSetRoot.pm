package GobanFTP::EventSetRoot;

use v5.34;
use strict;
use warnings;

use Carp qw(croak);
use Digest::SHA qw(sha256_hex);
use Exporter qw(import);

use GobanFTP::Filename::Grammar qw(parse_event);
use GobanFTP::Listing qw(event_basenames);

our @EXPORT_OK = qw(accepted_event_basenames event_set_root event_set_root_preimage event_set_root_result);

my $DOMAIN = "GOFTP-EVENT-SET/1\0";

sub event_set_root {
    return event_set_root_result(@_)->{event_set_root};
}

sub event_set_root_preimage {
    my ($game_descriptor, $names) = _game_and_names(@_);
    my $set = _accepted_set($game_descriptor, $names);

    return _preimage($game_descriptor, @{ $set->{accepted_events} });
}

sub event_set_root_result {
    my ($game_descriptor, $names) = _game_and_names(@_);
    my $set = _accepted_set($game_descriptor, $names);
    my $preimage = _preimage($game_descriptor, @{ $set->{accepted_events} });
    my $root = sha256_hex($preimage);

    return {
        version         => 'GOFTP-EVENT-SET/1',
        event_set_root  => $root,
        root            => $root,
        event_count     => scalar(@{ $set->{accepted_events} }),
        accepted_events => [ @{ $set->{accepted_events} } ],
        diagnostics     => [ @{ $set->{diagnostics} } ],
    };
}

sub accepted_event_basenames {
    my ($game_descriptor, $names) = _game_and_names(@_);
    my $set = _accepted_set($game_descriptor, $names);
    return @{ $set->{accepted_events} };
}

sub _accepted_set {
    my ($game_descriptor, $names) = @_;

    my %seen;
    my @accepted;
    my @diagnostics;

    for my $basename (event_basenames($names)) {
        next if $seen{$basename}++;

        my (undef, $error) = parse_event($basename, game_descriptor => $game_descriptor);
        if (defined $error) {
            push @diagnostics, {
                code  => 'parse_event',
                name  => $basename,
                error => $error,
            };
            next;
        }

        push @accepted, $basename;
    }

    return {
        accepted_events => [ sort { $a cmp $b } @accepted ],
        diagnostics     => \@diagnostics,
    };
}

sub _preimage {
    my ($game_descriptor, @accepted) = @_;

    return $DOMAIN
        . $game_descriptor . "\0"
        . scalar(@accepted) . "\0"
        . join('', map { "$_\0" } @accepted);
}

sub _game_and_names {
    if (@_ == 1 && ref($_[0]) eq 'HASH') {
        return _named_game_and_names(%{ $_[0] });
    }

    if (@_ && !ref($_[0]) && ($_[0] eq 'game_descriptor' || $_[0] eq 'game')) {
        return _named_game_and_names(@_);
    }

    my ($game_descriptor, @names) = @_;
    croak 'game_descriptor is required' if !defined $game_descriptor;

    if (@names == 1 && ref($names[0]) eq 'ARRAY') {
        return ($game_descriptor, $names[0]);
    }

    return ($game_descriptor, \@names);
}

sub _named_game_and_names {
    my (%args) = @_;

    my $game_descriptor = $args{game_descriptor} // $args{game};
    croak 'game_descriptor is required' if !defined $game_descriptor;

    my $names = $args{names} // $args{events} // $args{listing} // [];
    return ($game_descriptor, _array_ref($names));
}

sub _array_ref {
    my ($value) = @_;

    return $value if ref($value) eq 'ARRAY';
    return [] if !defined $value;
    return [$value];
}

1;

__END__

=head1 NAME

GobanFTP::EventSetRoot - v1.0 frozen GOFTP/1 accepted event-set root

=cut
