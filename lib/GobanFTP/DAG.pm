package GobanFTP::DAG;

use v5.34;
use strict;
use warnings;

use Exporter qw(import);
use Scalar::Util qw(blessed);

use GobanFTP::Event qw(event_id fields is_ack is_move kind parent_id);

our @EXPORT_OK = qw(build);

sub build {
    my (%args) = @_;

    my $items = $args{events} // [];
    die 'events must be an array reference' if ref($items) ne 'ARRAY';

    my %by_id;
    my %seen_name;
    for my $item (@$items) {
        die 'event item must be a hash reference' if ref($item) ne 'HASH';

        my $name  = $item->{name};
        my $event = $item->{event};
        die 'event item name is required'  if !defined $name;
        die 'event item event is required' if !defined $event;

        my $id = _event_id($event);
        die 'event_id is required' if !defined $id;

        next if $seen_name{$name}++;

        push @{ $by_id{$id} }, {
            id    => $id,
            name  => $name,
            event => $event,
        };
    }

    my (@diagnostics, %nodes);
    for my $id (sort keys %by_id) {
        my @candidates = sort { $a->{name} cmp $b->{name} } @{ $by_id{$id} };

        if (@candidates > 1) {
            push @diagnostics, {
                code     => 'event_id_collision',
                event_id => $id,
                names    => [map { $_->{name} } @candidates],
            };
            next;
        }

        my $node = _node_from_candidate($candidates[0]);
        $nodes{$id} = $node;
    }

    my (%invalid_move_ids, %candidate_move_ids, %ack_ids);
    for my $id (sort keys %nodes) {
        my $node = $nodes{$id};

        if ($node->{kind} eq 'move') {
            my $parent = $node->{parent_id};
            $candidate_move_ids{$id} = 1;
            next if $parent eq 'genesis';

            if (!exists $nodes{$parent}) {
                push @diagnostics, {
                    code      => 'missing_parent',
                    event_id  => $id,
                    parent_id => $parent,
                };
                $invalid_move_ids{$id} = 1;
            }
            elsif ($nodes{$parent}{kind} ne 'move') {
                push @diagnostics, {
                    code        => 'parent_not_move',
                    event_id    => $id,
                    parent_id   => $parent,
                    parent_kind => $nodes{$parent}{kind},
                };
                $invalid_move_ids{$id} = 1;
            }
        }
        elsif ($node->{kind} eq 'ack') {
            $ack_ids{$id} = 1;
            if (!exists $nodes{ $node->{target_id} }) {
                push @diagnostics, {
                    code      => 'dangling_ack_target',
                    event_id  => $id,
                    target_id => $node->{target_id},
                };
            }
            elsif ($nodes{ $node->{target_id} }{kind} ne 'move') {
                push @diagnostics, {
                    code        => 'ack_target_not_move',
                    event_id    => $id,
                    target_id   => $node->{target_id},
                    target_kind => $nodes{ $node->{target_id} }{kind},
                };
            }
        }
    }

    delete @candidate_move_ids{keys %invalid_move_ids};

    my @cycle_ids = _cycle_ids(\%nodes, \%candidate_move_ids);
    for my $id (@cycle_ids) {
        push @diagnostics, {
            code     => 'cycle',
            event_id => $id,
        };
    }
    delete @candidate_move_ids{@cycle_ids};

    my (%children_by_parent, %move_ids);
    for my $id (sort keys %candidate_move_ids) {
        my $node = $nodes{$id};
        $move_ids{$id} = 1;
        push @{ $children_by_parent{ $node->{parent_id} } }, $id;
    }

    for my $parent (keys %children_by_parent) {
        @{ $children_by_parent{$parent} } = sort @{ $children_by_parent{$parent} };
    }

    @diagnostics = sort {
           $a->{code} cmp $b->{code}
        || ($a->{event_id} // '') cmp ($b->{event_id} // '')
        || ($a->{parent_id} // '') cmp ($b->{parent_id} // '')
        || ($a->{target_id} // '') cmp ($b->{target_id} // '')
    } @diagnostics;

    return bless {
        nodes              => \%nodes,
        move_ids           => [sort keys %move_ids],
        ack_ids            => [sort keys %ack_ids],
        children_by_parent => \%children_by_parent,
        diagnostics        => \@diagnostics,
    }, __PACKAGE__;
}

sub node {
    my ($self, $id) = @_;
    return $self->{nodes}{$id};
}

sub move_ids {
    my ($self) = @_;
    return @{ $self->{move_ids} };
}

sub ack_ids {
    my ($self) = @_;
    return @{ $self->{ack_ids} };
}

sub children_of {
    my ($self, $parent_id) = @_;
    $parent_id = 'genesis' if !defined $parent_id;
    return @{ $self->{children_by_parent}{$parent_id} // [] };
}

sub topological_move_ids {
    my ($self) = @_;

    my (%in_degree, %children);
    for my $id (@{ $self->{move_ids} }) {
        $in_degree{$id} = 0;
    }

    for my $id (@{ $self->{move_ids} }) {
        my $node   = $self->{nodes}{$id};
        my $parent = $node->{parent_id};
        next if $parent eq 'genesis';
        next if !exists $self->{nodes}{$parent};
        next if $self->{nodes}{$parent}{kind} ne 'move';

        push @{ $children{$parent} }, $id;
        $in_degree{$id}++;
    }

    for my $id (keys %children) {
        @{ $children{$id} } = sort @{ $children{$id} };
    }

    my @ready = sort grep { $in_degree{$_} == 0 } keys %in_degree;
    my @ordered;
    while (@ready) {
        my $id = shift @ready;
        push @ordered, $id;

        for my $child (@{ $children{$id} // [] }) {
            $in_degree{$child}--;
            next if $in_degree{$child} != 0;
            push @ready, $child;
        }
        @ready = sort @ready;
    }

    return @ordered;
}

sub forks {
    my ($self) = @_;

    my %forks;
    for my $parent (sort keys %{ $self->{children_by_parent} }) {
        my @children = @{ $self->{children_by_parent}{$parent} };
        next if @children < 2;
        $forks{$parent} = \@children;
    }

    return \%forks;
}

sub diagnostics {
    my ($self) = @_;
    return @{ $self->{diagnostics} };
}

sub _node_from_candidate {
    my ($candidate) = @_;
    my $event = $candidate->{event};
    my $kind  = _kind($event);

    my $node = {
        id    => $candidate->{id},
        name  => $candidate->{name},
        event => $event,
        kind  => $kind,
    };

    if ($kind eq 'move') {
        $node->{parent_id} = _parent_id($event);
    }
    elsif ($kind eq 'ack') {
        $node->{target_id} = _fields($event)->{target};
    }

    return $node;
}

sub _event_id {
    my ($event) = @_;
    return $event->event_id if blessed($event) && $event->can('event_id');
    return event_id($event);
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

sub _parent_id {
    my ($event) = @_;
    return $event->parent_id if blessed($event) && $event->can('parent_id');
    return parent_id($event);
}

sub _cycle_ids {
    my ($nodes, $move_ids) = @_;

    my (%in_degree, %children);
    for my $id (keys %$move_ids) {
        $in_degree{$id} = 0;
    }

    for my $id (keys %$move_ids) {
        my $parent = $nodes->{$id}{parent_id};
        next if $parent eq 'genesis';
        next if !$move_ids->{$parent};

        push @{ $children{$parent} }, $id;
        $in_degree{$id}++;
    }

    my @ready = sort grep { $in_degree{$_} == 0 } keys %in_degree;
    my @ordered;
    while (@ready) {
        my $id = shift @ready;
        push @ordered, $id;

        for my $child (@{ $children{$id} // [] }) {
            $in_degree{$child}--;
            next if $in_degree{$child} != 0;
            push @ready, $child;
        }
        @ready = sort @ready;
    }

    return sort grep { $in_degree{$_} && $in_degree{$_} > 0 } keys %in_degree;
}

1;

__END__

=head1 NAME

GobanFTP::DAG - thin DAG view over parsed GOFTP/1 events

=cut
