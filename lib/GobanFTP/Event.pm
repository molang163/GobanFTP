package GobanFTP::Event;

use v5.34;
use strict;
use warnings;

use Exporter qw(import);

use GobanFTP::Filename::Grammar qw(parse_event);

our @EXPORT_OK = qw(from_name event_id kind fields is_move is_ack parent_id);

sub from_name {
    my ($name, %opts) = @_;

    my ($parsed, $error) = parse_event($name, %opts);
    return wantarray ? ($parsed, $error) : $parsed;
}

sub kind {
    my ($event) = @_;
    return $event->{kind};
}

sub fields {
    my ($event) = @_;
    return $event->{fields};
}

sub event_id {
    my ($event) = @_;
    return $event->{fields}{event_id};
}

sub is_move {
    my ($event) = @_;
    return $event->{kind} eq 'move';
}

sub is_ack {
    my ($event) = @_;
    return $event->{kind} eq 'ack';
}

sub parent_id {
    my ($event) = @_;
    return undef if !is_move($event);
    return $event->{fields}{parent};
}

1;

__END__

=head1 NAME

GobanFTP::Event - typed GOFTP/1 event helper

=cut
