package GobanFTP::Listing;

use v5.34;
use strict;
use warnings;

use Exporter qw(import);

our @EXPORT_OK = qw(event_basenames normalize_listing sort_event_basenames);

sub normalize_listing {
    my @events = event_basenames(@_);
    return sort_event_basenames(@events);
}

sub event_basenames {
    my @names = _names_from_args(@_);
    my @events;

    for my $name (@names) {
        my $event = _direct_event_basename($name);
        push @events, $event if defined $event;
    }

    return @events;
}

sub sort_event_basenames {
    my @names = grep { defined } _names_from_args(@_);
    return sort { $a cmp $b } @names;
}

sub _direct_event_basename {
    my ($name) = @_;

    return undef if !defined $name || $name eq '';

    $name =~ s{\A(?:\./)+}{};

    return undef if $name =~ m{\A(?:tmp|sidecar|projection|projections)(?:/|\z)};

    if ($name =~ m{\Aevents/([^/]+)\z}) {
        return _looks_like_event_basename($1) ? $1 : undef;
    }

    return undef if index($name, '/') >= 0;
    return _looks_like_event_basename($name) ? $name : undef;
}

sub _looks_like_event_basename {
    my ($name) = @_;
    return defined($name) && $name =~ /\A(?:m[0-9]+|a[0-9]+)(?:\.|\z)/;
}

sub _names_from_args {
    return @{ $_[0] } if @_ == 1 && ref($_[0]) eq 'ARRAY';
    return @_;
}

1;

__END__

=head1 NAME

GobanFTP::Listing - normalize GOFTP/1 listing names

=head1 SYNOPSIS

  my @events = normalize_listing(@listing_names);

=head1 DESCRIPTION

This module keeps the listing-first boundary narrow. It accepts local or FTP
listing names, keeps direct C<events/> children that look like move or ack event
basenames, and ignores sidecar, projection, temporary, and recursive child
paths. Unknown move or ack event versions are preserved so replay can report a
stable parser diagnostic. Full event filename validation belongs to
C<GobanFTP::Filename::Grammar>.

=cut
