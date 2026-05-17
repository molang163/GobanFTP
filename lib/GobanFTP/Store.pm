package GobanFTP::Store;

use v5.34;
use strict;
use warnings;

use Carp qw(croak);

sub list_names {
    my ($self) = @_;
    return _abstract_method($self, 'list_names');
}

sub publish_event_name {
    my ($self) = @_;
    return _abstract_method($self, 'publish_event_name');
}

sub mkdir {
    my ($self) = @_;
    return _abstract_method($self, 'mkdir');
}

sub exists_name {
    my ($self) = @_;
    return _abstract_method($self, 'exists_name');
}

sub _abstract_method {
    my ($self, $method) = @_;

    my $class = ref($self) || $self || __PACKAGE__;
    croak "$class must implement $method";
}

1;

__END__

=head1 NAME

GobanFTP::Store - storage interface for listing-first game state

=head1 DESCRIPTION

Store implementations provide directory-entry operations used by higher layers:
C<list_names>, C<publish_event_name>, C<mkdir>, and C<exists_name>.

=cut
