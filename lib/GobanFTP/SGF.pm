package GobanFTP::SGF;

use v5.34;
use strict;
use warnings;

use Exporter qw(import);
use Scalar::Util qw(blessed);

use GobanFTP::GameSpec qw(parse_basename);

our @EXPORT_OK = qw(
    main_sgf variations_sgf render_main render_variations
    render_sgf render main_line to_sgf sgf
    escape_sgf_value
);

sub render_main {
    return main_sgf(@_);
}

sub render_variations {
    return variations_sgf(@_);
}

sub render_sgf {
    return main_sgf(@_);
}

sub render {
    return main_sgf(@_);
}

sub main_line {
    return main_sgf(@_);
}

sub to_sgf {
    return main_sgf(@_);
}

sub sgf {
    return main_sgf(@_);
}

sub main_sgf {
    my @args = _without_invocant(@_);
    my ($game, $steps) = _main_inputs(@args);
    my $root_extra = {};

    my $result = _resign_result($steps);
    $root_extra->{RE} = $result if defined $result;

    return _render_game_tree(
        $game,
        $root_extra,
        sub {
            return join '', map { _move_node($_) } @$steps;
        },
    );
}

sub variations_sgf {
    my @args = _without_invocant(@_);
    my ($game, $events_by_id, $children_by_parent) = _variation_inputs(@args);

    return _render_game_tree(
        $game,
        {},
        sub {
            return _render_children('genesis', $events_by_id, $children_by_parent, {});
        },
    );
}

sub escape_sgf_value {
    my ($value) = @_;

    $value = '' if !defined $value;
    $value =~ s/\r\n?/\n/g;
    $value =~ s/\\/\\\\/g;
    $value =~ s/\]/\\]/g;

    return $value;
}

sub _main_inputs {
    if (@_ == 1 && _looks_like_replay($_[0])) {
        my $result = $_[0];
        my $game = $result->can('game') ? $result->game : _clone($result->{game});
        my @steps = $result->can('canonical_steps')
            ? $result->canonical_steps
            : map { _clone($_) } @{ $result->{canonical_steps} // [] };

        return (_normalize_game($game), \@steps);
    }

    if (@_ == 2) {
        return (_normalize_game($_[0]), _normalize_steps($_[1]));
    }

    die 'sgf.args' if @_ % 2;
    my %args = @_;

    return _main_inputs($args{replay_result}) if exists $args{replay_result};

    my $game = exists $args{game} ? $args{game} : $args{game_descriptor};
    my $steps = $args{canonical_events} // $args{steps};

    if (!defined $steps && exists $args{canonical_ids} && exists $args{events_by_id}) {
        die 'sgf.canonical_ids' if ref($args{canonical_ids}) ne 'ARRAY';
        die 'sgf.events_by_id'  if ref($args{events_by_id}) ne 'HASH';
        $steps = [ map {
            die "sgf.missing_event.$_" if !exists $args{events_by_id}{$_};
            $args{events_by_id}{$_};
        } @{ $args{canonical_ids} } ];
    }

    $steps //= $args{events};

    return (_normalize_game($game), _normalize_steps($steps));
}

sub _variation_inputs {
    if (@_ == 1 && _looks_like_replay($_[0])) {
        my $result = $_[0];
        my $game = $result->can('game') ? $result->game : _clone($result->{game});
        my $events_by_id = $result->can('events_by_id')
            ? $result->events_by_id
            : _clone($result->{events_by_id} // {});
        my $children_by_parent = $result->can('legal_children_by_parent')
            ? $result->legal_children_by_parent
            : _clone($result->{legal_children_by_parent} // {});

        return (
            _normalize_game($game),
            _normalize_events_by_id($events_by_id),
            _normalize_children_by_parent($children_by_parent),
        );
    }

    die 'sgf.args' if @_ % 2;
    my %args = @_;

    my $game = exists $args{game} ? $args{game} : $args{game_descriptor};
    my $events_by_id = $args{events_by_id};
    my $children_by_parent = $args{legal_children_by_parent} // $args{children_by_parent};

    return (
        _normalize_game($game),
        _normalize_events_by_id($events_by_id),
        _normalize_children_by_parent($children_by_parent),
    );
}

sub _looks_like_replay {
    my ($value) = @_;

    return 0 if !defined $value;
    return 1 if blessed($value) && $value->can('canonical_steps') && $value->can('game');
    return ref($value) eq 'HASH' && exists $value->{game} && exists $value->{canonical_steps};
}

sub _without_invocant {
    return @_ if !@_;
    shift @_ if !ref($_[0]) && $_[0] eq __PACKAGE__;
    return @_;
}

sub _normalize_game {
    my ($game) = @_;

    die 'sgf.game' if !defined $game;

    if (!ref $game) {
        my ($parsed, $error) = parse_basename($game);
        die "sgf.game_descriptor.$error" if defined $error;

        return {
            %$parsed,
            descriptor => $game,
        };
    }

    die 'sgf.game' if ref($game) ne 'HASH';
    return _clone($game);
}

sub _normalize_steps {
    my ($steps) = @_;

    die 'sgf.events' if ref($steps) ne 'ARRAY';
    return [ map { _clone($_) } @$steps ];
}

sub _normalize_events_by_id {
    my ($events_by_id) = @_;

    die 'sgf.events_by_id' if ref($events_by_id) ne 'HASH';
    return { map { $_ => _clone($events_by_id->{$_}) } keys %$events_by_id };
}

sub _normalize_children_by_parent {
    my ($children_by_parent) = @_;

    die 'sgf.legal_children_by_parent' if ref($children_by_parent) ne 'HASH';

    my %normalized;
    for my $parent (keys %$children_by_parent) {
        die 'sgf.legal_children_by_parent' if ref($children_by_parent->{$parent}) ne 'ARRAY';
        $normalized{$parent} = [ sort @{ $children_by_parent->{$parent} } ];
    }

    return \%normalized;
}

sub _render_game_tree {
    my ($game, $root_extra, $body_cb) = @_;

    return '(' . _root_node($game, $root_extra) . $body_cb->() . ')' . "\n";
}

sub _root_node {
    my ($game, $extra) = @_;

    my @properties = (
        GM => 1,
        FF => 4,
        CA => 'UTF-8',
        AP => 'GobanFTP',
        SZ => _required_game_field($game, 'size'),
        KM => _format_komi(_required_game_field($game, 'komi_milli')),
        PB => _required_game_field($game, 'black'),
        PW => _required_game_field($game, 'white'),
        RU => _required_game_field($game, 'rules'),
    );

    push @properties, RE => $extra->{RE} if defined $extra->{RE};

    return ';' . _properties(@properties);
}

sub _properties {
    my (@properties) = @_;

    my $sgf = '';
    while (@properties) {
        my $identifier = shift @properties;
        my $value      = shift @properties;
        die 'sgf.property' if !defined($identifier) || $identifier !~ /\A[A-Z]+\z/;
        $sgf .= $identifier . '[' . escape_sgf_value($value) . ']';
    }

    return $sgf;
}

sub _render_children {
    my ($parent_id, $events_by_id, $children_by_parent, $path) = @_;

    my @children = @{ $children_by_parent->{$parent_id} // [] };
    return '' if @children == 0;

    if (@children == 1) {
        return _render_branch($children[0], $events_by_id, $children_by_parent, $path);
    }

    return join '', map {
        '(' . _render_branch($_, $events_by_id, $children_by_parent, $path) . ')'
    } @children;
}

sub _render_branch {
    my ($id, $events_by_id, $children_by_parent, $path) = @_;

    die 'sgf.cycle' if $path->{$id};
    die "sgf.missing_event.$id" if !exists $events_by_id->{$id};

    my %next_path = (%$path, $id => 1);
    return _move_node($events_by_id->{$id})
        . _render_children($id, $events_by_id, $children_by_parent, \%next_path);
}

sub _move_node {
    my ($event_or_step) = @_;

    my ($kind, $fields) = _kind_and_fields($event_or_step);
    die 'sgf.event_kind' if $kind ne 'move';

    my $color = _sgf_color($fields->{color});
    my $action = $fields->{action};
    die 'sgf.action' if !defined $action;

    if ($action eq 'pass') {
        return ';' . _properties($color => '');
    }

    if ($action eq 'resign') {
        return ';' . _properties($color => '', C => 'resign');
    }

    my $point = $fields->{point};
    ($point) = $action =~ /\Aplay-([a-z][a-z])\z/ if !defined $point;
    die 'sgf.action' if !defined $point;

    return ';' . _properties($color => $point);
}

sub _resign_result {
    my ($steps) = @_;

    for my $step (reverse @$steps) {
        my (undef, $fields) = _kind_and_fields($step);
        next if ($fields->{action} // '') ne 'resign';
        return $fields->{color} eq 'b' ? 'W+R' : 'B+R';
    }

    return undef;
}

sub _kind_and_fields {
    my ($event_or_step) = @_;

    if (blessed($event_or_step)) {
        die 'sgf.event' if !$event_or_step->can('kind') || !$event_or_step->can('fields');
        return ($event_or_step->kind, _clone($event_or_step->fields));
    }

    die 'sgf.event' if ref($event_or_step) ne 'HASH';

    if (exists $event_or_step->{event}) {
        return _kind_and_fields($event_or_step->{event});
    }

    if (exists $event_or_step->{kind}) {
        die 'sgf.fields' if ref($event_or_step->{fields}) ne 'HASH';
        return ($event_or_step->{kind}, _clone($event_or_step->{fields}));
    }

    if (exists $event_or_step->{fields}) {
        die 'sgf.fields' if ref($event_or_step->{fields}) ne 'HASH';
        return ('move', _clone($event_or_step->{fields}));
    }

    return ('move', _clone($event_or_step));
}

sub _sgf_color {
    my ($color) = @_;

    return 'B' if defined($color) && $color eq 'b';
    return 'W' if defined($color) && $color eq 'w';
    die 'sgf.color';
}

sub _format_komi {
    my ($komi_milli) = @_;

    die 'sgf.komi' if !defined($komi_milli) || $komi_milli !~ /\A(?:0|[1-9][0-9]*)\z/;

    my $whole = int($komi_milli / 1000);
    my $milli = $komi_milli % 1000;
    return "$whole" if $milli == 0;

    my $fraction = sprintf '%03d', $milli;
    $fraction =~ s/0+\z//;

    return "$whole.$fraction";
}

sub _required_game_field {
    my ($game, $field) = @_;

    die "sgf.game.$field" if !defined $game->{$field};
    return $game->{$field};
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

1;

__END__

=head1 NAME

GobanFTP::SGF - pure SGF rendering from replay output

=cut
