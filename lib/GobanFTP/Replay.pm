package GobanFTP::Replay;

use v5.34;
use strict;
use warnings;

use Exporter qw(import);
use Scalar::Util qw(blessed);

use GobanFTP::DAG qw(build);
use GobanFTP::Event qw(event_id fields from_name);
use GobanFTP::GameSpec qw(parse_basename);
use GobanFTP::Rules;

our @EXPORT_OK = qw(replay);

sub replay {
    my (%args) = @_;

    my $game_descriptor = $args{game_descriptor};
    my $raw_events      = exists $args{events} ? $args{events}
        : exists $args{event_basenames}       ? $args{event_basenames}
        : exists $args{items}                 ? $args{items}
        : [];
    my $policy = $args{policy} // 'conservative';

    die 'game_descriptor is required' if !defined $game_descriptor;
    die 'events must be an array reference' if ref($raw_events) ne 'ARRAY';
    die 'replay.policy' if $policy ne 'conservative' && $policy ne 'ack-assisted';

    my @diagnostics;
    my ($game, $game_error) = parse_basename($game_descriptor);
    if (defined $game_error) {
        push @diagnostics, {
            code  => 'parse_game_descriptor',
            error => $game_error,
        };
        return _empty_result(\@diagnostics, $policy);
    }

    my $game_view = _game_view($game_descriptor, $game);

    my $rules;
    eval {
        $rules = GobanFTP::Rules->new(size => $game->{size}, rules => $game->{rules});
        1;
    } or do {
        push @diagnostics, {
            code  => 'rules',
            error => _error_class($@),
        };
        return _empty_result(\@diagnostics, $policy);
    };

    my @items = _parse_items($raw_events, $game_descriptor, \@diagnostics);
    my ($events_by_id, $names_by_id) = _event_maps(\@items);

    my $dag = build(events => \@items);
    my @dag_diagnostics = map { +{%$_} } $dag->diagnostics;
    my @ack_player_diagnostics = _ack_player_diagnostics($dag, $game);
    push @diagnostics, @dag_diagnostics, @ack_player_diagnostics;

    my %invalid_ack_ids = _invalid_ack_ids(@dag_diagnostics, @ack_player_diagnostics);
    my $ack_ids_by_target = _ack_ids_by_target($dag, \%invalid_ack_ids);

    my ($legal_ids, $illegal_by_id, $states_by_id)
        = _replay_topological($dag, $rules, $game, \@diagnostics);

    my $legal_children_by_parent = _legal_children_by_parent($dag, $legal_ids);
    my ($canonical_ids, $fork, $final_state, $ack_assisted_choices)
        = _canonical_line(
            $legal_children_by_parent,
            $rules->initial_state,
            $states_by_id,
            policy            => $policy,
            dag               => $dag,
            game              => $game,
            ack_ids_by_target => $ack_ids_by_target,
        );
    push @diagnostics, {%$fork} if defined $fork;

    my $canonical_steps = _canonical_steps($dag, $canonical_ids, $states_by_id);

    return bless {
        policy                   => $policy,
        diagnostics              => \@diagnostics,
        canonical_ids            => $canonical_ids,
        legal_ids                => $legal_ids,
        illegal_by_id            => $illegal_by_id,
        fork                     => $fork,
        states_by_id             => $states_by_id,
        final_state              => $final_state,
        game                     => $game_view,
        events_by_id             => $events_by_id,
        names_by_id              => $names_by_id,
        canonical_steps          => $canonical_steps,
        legal_children_by_parent => $legal_children_by_parent,
        ack_ids_by_target        => $ack_ids_by_target,
        ack_assisted_choices     => $ack_assisted_choices,
    }, __PACKAGE__;
}

sub policy {
    my ($self) = @_;
    return $self->{policy};
}

sub diagnostics {
    my ($self) = @_;
    return map { _clone($_) } @{ $self->{diagnostics} };
}

sub canonical_ids {
    my ($self) = @_;
    return @{ $self->{canonical_ids} };
}

sub legal_ids {
    my ($self) = @_;
    return @{ $self->{legal_ids} };
}

sub illegal_by_id {
    my ($self) = @_;
    return _clone($self->{illegal_by_id});
}

sub fork {
    my ($self) = @_;
    return _clone($self->{fork});
}

sub final_state {
    my ($self) = @_;
    return _clone($self->{final_state});
}

sub game {
    my ($self) = @_;
    return _clone($self->{game});
}

sub events_by_id {
    my ($self) = @_;
    return _clone($self->{events_by_id});
}

sub names_by_id {
    my ($self) = @_;
    return _clone($self->{names_by_id});
}

sub canonical_steps {
    my ($self) = @_;
    return map { _clone($_) } @{ $self->{canonical_steps} };
}

sub legal_children_by_parent {
    my ($self) = @_;
    return _clone($self->{legal_children_by_parent});
}

sub ack_ids_by_target {
    my ($self) = @_;
    return _clone($self->{ack_ids_by_target});
}

sub ack_assisted_choices {
    my ($self) = @_;
    return map { _clone($_) } @{ $self->{ack_assisted_choices} };
}

sub _parse_items {
    my ($raw_events, $game_descriptor, $diagnostics) = @_;

    my @items;
    for my $index (0 .. $#$raw_events) {
        my $raw = $raw_events->[$index];

        if (!ref $raw) {
            _parse_item_name(\@items, $diagnostics, $raw, $game_descriptor);
            next;
        }

        if (ref($raw) eq 'HASH' && exists $raw->{name}) {
            _parse_item_name(\@items, $diagnostics, $raw->{name}, $game_descriptor);
            next;
        }

        push @$diagnostics, {
            code  => 'invalid_event_item',
            stage => 'parse',
            index => $index,
        };
    }

    return @items;
}

sub _parse_item_name {
    my ($items, $diagnostics, $name, $game_descriptor) = @_;

    my ($event, $error) = from_name($name, game_descriptor => $game_descriptor);
    if (defined $error) {
        push @$diagnostics, {
            code  => 'parse_event',
            name  => $name,
            error => $error,
        };
        return;
    }

    push @$items, {
        name  => $name,
        event => $event,
    };
}

sub _game_view {
    my ($game_descriptor, $game) = @_;

    return {
        %$game,
        descriptor => $game_descriptor,
    };
}

sub _event_maps {
    my ($items) = @_;

    my (%seen_name, %by_id);
    for my $item (@$items) {
        my $name = $item->{name};
        next if $seen_name{$name}++;

        my $id = _event_id($item->{event});
        push @{ $by_id{$id} }, {
            name  => $name,
            event => $item->{event},
        };
    }

    my (%events_by_id, %names_by_id);
    for my $id (sort keys %by_id) {
        my @candidates = sort { $a->{name} cmp $b->{name} } @{ $by_id{$id} };
        next if @candidates > 1;

        $events_by_id{$id} = _clone($candidates[0]{event});
        $names_by_id{$id}  = $candidates[0]{name};
    }

    return (\%events_by_id, \%names_by_id);
}

sub _replay_topological {
    my ($dag, $rules, $game, $diagnostics) = @_;

    my $initial_state = $rules->initial_state;
    my %states_by_id;
    my %depth_by_id;
    my %illegal_by_id;
    my @legal_ids;

    for my $id ($dag->topological_move_ids) {
        my $node      = $dag->node($id);
        my $parent_id = $node->{parent_id};

        my ($parent_state, $parent_depth);
        if ($parent_id eq 'genesis') {
            ($parent_state, $parent_depth) = ($initial_state, 0);
        }
        else {
            ($parent_state, $parent_depth) = ($states_by_id{$parent_id}, $depth_by_id{$parent_id});
        }

        if (!defined $parent_state) {
            _mark_illegal(
                \%illegal_by_id,
                $diagnostics,
                $id,
                {
                    code      => 'parent_not_legal',
                    event_id  => $id,
                    parent_id => $parent_id,
                },
            );
            next;
        }

        my @preflight = _preflight_diagnostics($node, $game, $parent_state, $parent_depth);
        if (@preflight) {
            _mark_illegal(\%illegal_by_id, $diagnostics, $id, @preflight);
            next;
        }

        my $state = $rules->apply_move($parent_state, $node->{event});
        if (!$state->{ok}) {
            _mark_illegal(
                \%illegal_by_id,
                $diagnostics,
                $id,
                {
                    code      => 'illegal_move',
                    event_id  => $id,
                    parent_id => $parent_id,
                    reason    => $state->{reason},
                },
            );
            next;
        }

        push @legal_ids, $id;
        $states_by_id{$id} = $state;
        $depth_by_id{$id}  = $parent_depth + 1;
    }

    return (\@legal_ids, \%illegal_by_id, \%states_by_id);
}

sub _preflight_diagnostics {
    my ($node, $game, $parent_state, $parent_depth) = @_;

    my $id        = $node->{id};
    my $parent_id = $node->{parent_id};
    my $fields    = _event_fields($node->{event});
    my @diagnostics;

    my $color = $fields->{color};
    if (!defined($color) || $color ne $parent_state->{next_color}) {
        push @diagnostics, {
            code           => 'wrong_color',
            event_id       => $id,
            parent_id      => $parent_id,
            expected_color => $parent_state->{next_color},
            color          => $color,
        };
    }

    if (defined $color && ($color eq 'b' || $color eq 'w')) {
        my $expected_player = $color eq 'b' ? $game->{black} : $game->{white};
        if (!defined($fields->{player}) || $fields->{player} ne $expected_player) {
            push @diagnostics, {
                code            => 'wrong_player',
                event_id        => $id,
                parent_id       => $parent_id,
                color           => $color,
                expected_player => $expected_player,
                player          => $fields->{player},
            };
        }
    }

    my $expected_ply = $parent_depth + 1;
    my $ply          = $fields->{ply};
    if (!defined($ply) || $ply !~ /\A[0-9]+\z/ || 0 + $ply != $expected_ply) {
        push @diagnostics, {
            code         => 'wrong_ply',
            event_id     => $id,
            parent_id    => $parent_id,
            expected_ply => $expected_ply,
            ply          => $ply,
        };
    }

    return @diagnostics;
}

sub _ack_player_diagnostics {
    my ($dag, $game) = @_;

    my @allowed = grep { defined && $_ ne '' } ($game->{black}, $game->{white});
    my %allowed = map { $_ => 1 } @allowed;
    my $expected = join ',', @allowed;

    my @diagnostics;
    for my $id ($dag->ack_ids) {
        my $node = $dag->node($id);
        next if !defined $node;

        my $fields = _event_fields($node->{event});
        my $player = $fields->{player};
        next if defined($player) && $allowed{$player};

        push @diagnostics, {
            code            => 'ack_wrong_player',
            event_id        => $id,
            expected_player => $expected,
            player          => $player,
        };
    }

    return @diagnostics;
}

sub _invalid_ack_ids {
    my (@diagnostics) = @_;

    my %invalid;
    for my $diagnostic (@diagnostics) {
        next if ref($diagnostic) ne 'HASH';
        next if !defined $diagnostic->{event_id};
        next if ($diagnostic->{code} // '') !~ /\A(?:ack_target_not_move|ack_wrong_player|dangling_ack_target)\z/;
        $invalid{ $diagnostic->{event_id} } = 1;
    }

    return %invalid;
}

sub _ack_ids_by_target {
    my ($dag, $invalid_ack_ids) = @_;

    my %by_target;
    for my $id ($dag->ack_ids) {
        next if $invalid_ack_ids->{$id};

        my $node = $dag->node($id);
        next if !defined $node;

        my $target = _event_fields($node->{event})->{target};
        next if !defined $target;

        push @{ $by_target{$target} }, $id;
    }

    for my $target (keys %by_target) {
        @{ $by_target{$target} } = sort @{ $by_target{$target} };
    }

    return \%by_target;
}

sub _legal_children_by_parent {
    my ($dag, $legal_ids) = @_;

    my %children_by_parent;
    for my $id (@$legal_ids) {
        my $node = $dag->node($id);
        next if !defined $node;
        push @{ $children_by_parent{ $node->{parent_id} } }, $id;
    }

    for my $parent (keys %children_by_parent) {
        @{ $children_by_parent{$parent} } = sort @{ $children_by_parent{$parent} };
    }

    return \%children_by_parent;
}

sub _canonical_line {
    my ($legal_children_by_parent, $initial_state, $states_by_id, %opts) = @_;

    my @canonical_ids;
    my @ack_assisted_choices;
    my $parent_id   = 'genesis';
    my $final_state = $initial_state;
    my $policy      = $opts{policy} // 'conservative';

    while (1) {
        my @legal_children = @{ $legal_children_by_parent->{$parent_id} // [] };

        return (\@canonical_ids, undef, $final_state, \@ack_assisted_choices) if @legal_children == 0;

        if (@legal_children > 1) {
            if ($policy eq 'ack-assisted') {
                my $choice = _ack_assisted_choice(\@legal_children, %opts);
                if (defined $choice) {
                    push @ack_assisted_choices, $choice;

                    my $child_id = $choice->{child_id};
                    push @canonical_ids, $child_id;
                    $parent_id   = $child_id;
                    $final_state = $states_by_id->{$child_id};
                    next;
                }
            }

            my $fork = {
                code      => 'fork',
                parent_id => $parent_id,
                child_ids => \@legal_children,
            };
            return (\@canonical_ids, $fork, $final_state, \@ack_assisted_choices);
        }

        my $child_id = $legal_children[0];
        push @canonical_ids, $child_id;
        $parent_id   = $child_id;
        $final_state = $states_by_id->{$child_id};
    }
}

sub _ack_assisted_choice {
    my ($legal_children, %opts) = @_;

    my $dag = $opts{dag};
    my $game = $opts{game};
    my $ack_ids_by_target = $opts{ack_ids_by_target} // {};

    return undef if !defined $dag || ref($game) ne 'HASH';

    my @acked_children;
    for my $child_id (@$legal_children) {
        my $node = $dag->node($child_id);
        next if !defined $node;

        my $opponent = _opponent_player($node, $game);
        next if !defined $opponent;

        my @ack_ids;
        for my $ack_id (@{ $ack_ids_by_target->{$child_id} // [] }) {
            my $ack_node = $dag->node($ack_id);
            next if !defined $ack_node;

            my $ack_player = _event_fields($ack_node->{event})->{player};
            push @ack_ids, $ack_id if defined($ack_player) && $ack_player eq $opponent;
        }
        next if !@ack_ids;

        push @acked_children, {
            child_id => $child_id,
            ack_ids  => [sort @ack_ids],
        };
    }

    return undef if @acked_children != 1;

    return {
        parent_id => $dag->node($acked_children[0]{child_id})->{parent_id},
        child_id  => $acked_children[0]{child_id},
        ack_ids   => $acked_children[0]{ack_ids},
    };
}

sub _opponent_player {
    my ($move_node, $game) = @_;

    my $color = _event_fields($move_node->{event})->{color};
    return $game->{white} if defined($color) && $color eq 'b';
    return $game->{black} if defined($color) && $color eq 'w';

    return undef;
}

sub _canonical_steps {
    my ($dag, $canonical_ids, $states_by_id) = @_;

    my @steps;
    for my $id (@$canonical_ids) {
        my $node = $dag->node($id);
        next if !defined $node;

        my $state    = $states_by_id->{$id};
        my $captures = ref($state) eq 'HASH' && ref($state->{captures}) eq 'ARRAY'
            ? [ @{ $state->{captures} } ]
            : [];

        push @steps, {
            id        => $id,
            event_id  => $id,
            name      => $node->{name},
            kind      => $node->{kind},
            parent_id => $node->{parent_id},
            event     => _clone($node->{event}),
            fields    => _clone(_event_fields($node->{event})),
            state     => _clone($state),
            captures  => $captures,
        };
    }

    return \@steps;
}

sub _mark_illegal {
    my ($illegal_by_id, $diagnostics, $id, @event_diagnostics) = @_;

    push @{ $illegal_by_id->{$id} }, map { +{%$_} } @event_diagnostics;
    push @$diagnostics, @event_diagnostics;
}

sub _empty_result {
    my ($diagnostics, $policy) = @_;

    return bless {
        policy                   => $policy // 'conservative',
        diagnostics              => $diagnostics,
        canonical_ids            => [],
        legal_ids                => [],
        illegal_by_id            => {},
        fork                     => undef,
        states_by_id             => {},
        final_state              => undef,
        game                     => undef,
        events_by_id             => {},
        names_by_id              => {},
        canonical_steps          => [],
        legal_children_by_parent => {},
        ack_ids_by_target        => {},
        ack_assisted_choices     => [],
    }, __PACKAGE__;
}

sub _event_id {
    my ($event) = @_;
    return $event->event_id if blessed($event) && $event->can('event_id');
    return event_id($event);
}

sub _event_fields {
    my ($event) = @_;
    return $event->fields if blessed($event) && $event->can('fields');
    return fields($event);
}

sub _clone {
    my ($value) = @_;

    return undef if !defined $value;
    return $value->copy if blessed($value) && $value->can('copy');

    if (ref($value) eq 'ARRAY') {
        return [ map { _clone($_) } @$value ];
    }

    if (ref($value) eq 'HASH') {
        return { map { $_ => _clone($value->{$_}) } keys %$value };
    }

    return $value;
}

sub _error_class {
    my ($error) = @_;

    $error = 'unknown' if !defined($error) || $error eq '';
    chomp $error;
    $error =~ s/\s+at\s+.*\z//s;
    $error =~ s/\A\s+//;
    $error =~ s/\s+\z//;
    $error =~ s/:.*\z//;
    $error =~ s/\s+.*\z//;
    $error = lc $error;
    $error =~ s/[^a-z0-9_.-]+/_/g;
    $error =~ s/\A_+//;
    $error =~ s/_+\z//;

    return $error ne '' ? $error : 'unknown';
}

1;

__END__

=head1 NAME

GobanFTP::Replay - parse, DAG, and replay GOFTP/1 move events

=cut
