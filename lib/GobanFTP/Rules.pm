package GobanFTP::Rules;

use v5.34;
use strict;
use warnings;

use Carp qw(croak);
use Digest::SHA qw(sha256_hex);
use Scalar::Util qw(blessed);

use GobanFTP::Board;
use GobanFTP::Coord qw(index_to_point point_to_index);

sub new {
    my ($class, @args) = @_;

    my %args = @args == 1 ? (size => $args[0]) : @args;
    my $size = $args{size};
    croak 'rules.size'
        if !defined($size) || $size !~ /\A(?:0|[1-9][0-9]*)\z/ || $size < 2 || $size > 26;

    my $rules = $args{rules} // 'chinese-area-v1';
    croak 'rules.id' if $rules ne 'chinese-area-v1';

    my $engine = $args{engine} // $ENV{GOBANFTP_RULES_ENGINE} // 'perl';
    croak 'rules.engine' if $engine !~ /\A(?:perl|auto|c|shadow)\z/;

    my $self = bless {
        size   => 0 + $size,
        rules  => $rules,
        engine => $engine,
    }, $class;

    if ($engine eq 'c') {
        my ($available, $error) = $self->_c_available;
        croak 'rules.c.unavailable' . (defined($error) ? ": $error" : '')
            if !$available;
    }

    return $self;
}

sub size {
    my ($self) = @_;
    return $self->{size};
}

sub rules {
    my ($self) = @_;
    return $self->{rules};
}

sub engine {
    my ($self) = @_;
    return $self->{engine};
}

sub engine_status {
    my ($self) = @_;

    my $requested = $self->{engine};
    return {
        requested   => $requested,
        effective   => 'perl',
        c_available => undef,
        diagnostics => [],
    } if $requested eq 'perl';

    my ($available, $error) = $self->_c_available;
    my $effective = $available
        ? ($requested eq 'shadow' ? 'perl+shadow-c' : 'c')
        : 'perl';

    my @diagnostics;
    if (!$available) {
        push @diagnostics, {
            code  => 'rules_c_unavailable',
            error => $error,
        };
    }

    return {
        requested   => $requested,
        effective   => $effective,
        c_available => $available ? 1 : 0,
        c_error     => $available ? undef : $error,
        diagnostics => \@diagnostics,
    };
}

sub initial_state {
    my ($self) = @_;

    my $board = GobanFTP::Board->new(size => $self->{size});
    my $hash  = $self->position_hash($board);

    return {
        size               => $self->{size},
        rules              => $self->{rules},
        board              => $board,
        captures           => [],
        position_hash      => $hash,
        ancestor_hashes    => { $hash => 1 },
        consecutive_passes => 0,
        terminal           => 0,
        next_color         => 'b',
    };
}

sub position_hash {
    my ($self, $board) = @_;

    croak 'rules.board'
        if !blessed($board) || !$board->can('canonical_bytes') || !$board->can('size');
    croak 'rules.board_size' if $board->size != $self->{size};

    my $bytes = $board->canonical_bytes;
    croak 'rules.board_bytes' if length($bytes) != $self->{size} * $self->{size};

    return sha256_hex('GOFTP-BOARD/1' . "\0" . $self->{size} . "\0" . $bytes);
}

sub apply_move {
    my ($self, $state, $event_or_fields) = @_;
    return $self->_apply_event_or_fields($state, $event_or_fields);
}

sub apply_action {
    my ($self, $state, @args) = @_;

    my $event_or_fields;
    if (@args == 1 && ref($args[0])) {
        $event_or_fields = $args[0];
    }
    elsif (@args == 1) {
        $event_or_fields = { action => $args[0] };
    }
    elsif (@args % 2 == 0) {
        $event_or_fields = {@args};
    }
    else {
        $event_or_fields = undef;
    }

    return $self->_apply_event_or_fields($state, $event_or_fields);
}

sub _apply_event_or_fields {
    my ($self, $state, $event_or_fields) = @_;

    $self->{_engine_diagnostics} = [];

    my $parent = $self->_normalize_state($state);
    my ($fields, $field_error) = _fields_from($event_or_fields);
    return $self->_reject($parent, $field_error) if defined $field_error;

    return $self->_apply_fields($parent, $fields);
}

sub _apply_fields {
    my ($self, $parent, $fields) = @_;

    return $self->_reject($parent, 'terminal') if $parent->{terminal};

    my $color = $fields->{color};
    return $self->_reject($parent, 'color') if !defined($color) || ($color ne 'b' && $color ne 'w');
    return $self->_reject($parent, 'color') if $color ne $parent->{next_color};

    my $action = $fields->{action};
    return $self->_reject($parent, 'move.action') if !defined $action;

    if ($action eq 'pass') {
        return $self->_accept_non_play(
            $parent,
            consecutive_passes => $parent->{consecutive_passes} + 1,
            terminal           => $parent->{consecutive_passes} + 1 >= 2 ? 1 : 0,
            terminal_reason    => $parent->{consecutive_passes} + 1 >= 2 ? 'two_passes' : undef,
        );
    }

    if ($action eq 'resign') {
        return $self->_accept_non_play(
            $parent,
            consecutive_passes => 0,
            terminal           => 1,
            terminal_reason    => 'resign',
        );
    }

    my ($point) = $action =~ /\Aplay-([a-z][a-z])\z/;
    return $self->_reject($parent, 'move.action') if !defined $point;
    return $self->_reject($parent, 'move.point') if defined($fields->{point}) && $fields->{point} ne $point;

    return $self->_apply_play($parent, $color, $point);
}

sub _apply_play {
    my ($self, $parent, $color, $point) = @_;

    my ($index, $point_error) = point_to_index($point, $self->{size});
    return $self->_reject($parent, $point_error) if defined $point_error;

    my $mechanics = $self->_apply_play_mechanics(
        board_bytes => $parent->{board}->canonical_bytes,
        index       => $index,
        stone       => _stone_for_color($color),
    );
    return $self->_reject($parent, $mechanics->{reason}) if !$mechanics->{ok};

    my @captured_indices = @{ $mechanics->{captures} };
    my $board            = _board_from_bytes($self->{size}, $mechanics->{board_bytes});
    my $position_hash = $self->position_hash($board);
    return $self->_reject($parent, 'superko') if $parent->{ancestor_hashes}{$position_hash};

    my $ancestor_hashes = { %{ $parent->{ancestor_hashes} } };
    $ancestor_hashes->{$position_hash} = 1;

    return $self->_accepted_state(
        parent             => $parent,
        board              => $board,
        captures           => [ map { scalar index_to_point($_, $self->{size}) } @captured_indices ],
        position_hash      => $position_hash,
        ancestor_hashes    => $ancestor_hashes,
        consecutive_passes => 0,
        terminal           => 0,
        terminal_reason    => undef,
    );
}

sub _accept_non_play {
    my ($self, $parent, %args) = @_;

    return $self->_accepted_state(
        parent             => $parent,
        board              => $parent->{board}->copy,
        captures           => [],
        position_hash      => $parent->{position_hash},
        ancestor_hashes    => { %{ $parent->{ancestor_hashes} } },
        consecutive_passes => $args{consecutive_passes},
        terminal           => $args{terminal},
        terminal_reason    => $args{terminal_reason},
    );
}

sub _accepted_state {
    my ($self, %args) = @_;

    my $terminal_reason = $args{terminal_reason};

    my $state = {
        ok                 => 1,
        size               => $self->{size},
        rules              => $self->{rules},
        board              => $args{board},
        captures           => $args{captures},
        position_hash      => $args{position_hash},
        ancestor_hashes    => $args{ancestor_hashes},
        consecutive_passes => $args{consecutive_passes},
        terminal           => $args{terminal} ? 1 : 0,
        next_color         => _opponent_color($args{parent}{next_color}),
    };
    $state->{terminal_reason} = $terminal_reason if defined $terminal_reason;
    $self->_attach_engine_diagnostics($state);

    return $state;
}

sub _reject {
    my ($self, $parent, $reason) = @_;

    my $state = {
        ok                 => 0,
        size               => $self->{size},
        rules              => $self->{rules},
        board              => $parent->{board}->copy,
        captures           => [],
        reason             => $reason,
        position_hash      => $parent->{position_hash},
        ancestor_hashes    => { %{ $parent->{ancestor_hashes} } },
        consecutive_passes => $parent->{consecutive_passes},
        terminal           => $parent->{terminal} ? 1 : 0,
        next_color         => $parent->{next_color},
    };
    $self->_attach_engine_diagnostics($state);

    return $state;
}

sub _apply_play_mechanics {
    my ($self, %args) = @_;

    my $engine = $self->{engine};
    return $self->_normalize_mechanics_result(_perl_play_mechanics($self->{size}, %args))
        if $engine eq 'perl';

    if ($engine eq 'c') {
        return $self->_normalize_mechanics_result($self->_c_play_mechanics(%args));
    }

    if ($engine eq 'auto') {
        my ($available) = $self->_c_available;
        return $self->_normalize_mechanics_result($self->_c_play_mechanics(%args))
            if $available;
        return $self->_normalize_mechanics_result(_perl_play_mechanics($self->{size}, %args));
    }

    if ($engine eq 'shadow') {
        my $perl_result = $self->_normalize_mechanics_result(_perl_play_mechanics($self->{size}, %args));
        my ($available, $error) = $self->_c_available;
        if (!$available) {
            push @{ $self->{_engine_diagnostics} }, {
                code  => 'rules_c_unavailable',
                error => $error,
            };
            return $perl_result;
        }

        my $c_result = $self->_normalize_mechanics_result($self->_c_play_mechanics(%args));
        if (defined(my $mismatch = _mechanics_mismatch($perl_result, $c_result))) {
            croak "rules.c.shadow_mismatch.$mismatch";
        }

        return $perl_result;
    }

    croak 'rules.engine';
}

sub _c_available {
    my ($self) = @_;

    my $loaded = eval {
        require GobanFTP::Rules::C;
        1;
    };
    return (0, _clean_error($@ || 'require GobanFTP::Rules::C failed')) if !$loaded;

    my $available = GobanFTP::Rules::C->available ? 1 : 0;
    return (1, undef) if $available;

    return (0, GobanFTP::Rules::C->load_error // 'Inline::C unavailable');
}

sub _c_play_mechanics {
    my ($self, %args) = @_;

    my ($available, $error) = $self->_c_available;
    croak 'rules.c.unavailable' . (defined($error) ? ": $error" : '')
        if !$available;

    return GobanFTP::Rules::C->apply_play(
        board_bytes => $args{board_bytes},
        size        => $self->{size},
        index       => $args{index},
        stone       => $args{stone},
    );
}

sub _normalize_mechanics_result {
    my ($self, $result) = @_;

    croak 'rules.mechanics' if ref($result) ne 'HASH';

    my $ok = $result->{ok} ? 1 : 0;
    my @captures;
    if (ref($result->{captures}) eq 'ARRAY') {
        @captures = @{ $result->{captures} };
    }
    else {
        croak 'rules.mechanics.captures';
    }

    my $total = $self->{size} * $self->{size};
    my $last = -1;
    for my $capture (@captures) {
        croak 'rules.mechanics.captures'
            if !defined($capture)
            || ref($capture)
            || $capture !~ /\A(?:0|[1-9][0-9]*)\z/
            || $capture >= $total
            || $capture <= $last;
        $last = $capture;
    }

    if (!$ok) {
        croak 'rules.mechanics.reason' if !defined($result->{reason}) || ref($result->{reason});
        return {
            ok       => 0,
            reason   => $result->{reason},
            captures => [],
        };
    }

    my $board_bytes = $result->{board_bytes};
    croak 'rules.mechanics.board_bytes'
        if !defined($board_bytes) || ref($board_bytes) || length($board_bytes) != $total;

    for my $cell (unpack 'C*', $board_bytes) {
        croak 'rules.mechanics.board_bytes' if $cell > 2;
    }

    return {
        ok          => 1,
        board_bytes => $board_bytes,
        captures    => \@captures,
    };
}

sub _attach_engine_diagnostics {
    my ($self, $state) = @_;

    my $diagnostics = $self->{_engine_diagnostics} // [];
    $state->{engine_diagnostics} = [ map { +{%$_} } @$diagnostics ]
        if @$diagnostics;

    return;
}

sub _normalize_state {
    my ($self, $state) = @_;

    return $self->initial_state if !defined $state;
    croak 'rules.state' if ref($state) ne 'HASH';

    my $board = $state->{board};
    croak 'rules.state.board'
        if !blessed($board) || !$board->can('copy') || !$board->can('canonical_bytes') || !$board->can('size');
    croak 'rules.state.board_size' if $board->size != $self->{size};

    my $position_hash = $state->{position_hash} // $self->position_hash($board);
    my $ancestor_hashes = ref($state->{ancestor_hashes}) eq 'HASH'
        ? { %{ $state->{ancestor_hashes} } }
        : {};
    $ancestor_hashes->{$position_hash} = 1;

    my $next_color = $state->{next_color} // 'b';
    croak 'rules.state.color' if $next_color ne 'b' && $next_color ne 'w';

    return {
        board              => $board,
        position_hash      => $position_hash,
        ancestor_hashes    => $ancestor_hashes,
        consecutive_passes => 0 + ($state->{consecutive_passes} // 0),
        terminal           => $state->{terminal} ? 1 : 0,
        next_color         => $next_color,
    };
}

sub _fields_from {
    my ($event_or_fields) = @_;

    return (undef, 'event.fields') if !defined $event_or_fields;

    if (blessed($event_or_fields)) {
        if ($event_or_fields->can('kind') && $event_or_fields->kind ne 'move') {
            return (undef, 'event.kind');
        }
        return ({ %{ $event_or_fields->fields } }, undef) if $event_or_fields->can('fields');
        return (undef, 'event.fields');
    }

    return (undef, 'event.fields') if ref($event_or_fields) ne 'HASH';

    if (exists $event_or_fields->{kind}) {
        return (undef, 'event.kind') if $event_or_fields->{kind} ne 'move';
        return (undef, 'event.fields') if ref($event_or_fields->{fields}) ne 'HASH';
        return ({ %{ $event_or_fields->{fields} } }, undef);
    }

    if (exists $event_or_fields->{fields}) {
        return (undef, 'event.fields') if ref($event_or_fields->{fields}) ne 'HASH';
        return ({ %{ $event_or_fields->{fields} } }, undef);
    }

    return ({%$event_or_fields}, undef);
}

sub _perl_play_mechanics {
    my ($size, %args) = @_;

    my @cells = unpack 'C*', $args{board_bytes};
    my $index = $args{index};
    return {
        ok       => 0,
        reason   => 'occupied',
        captures => [],
    } if $cells[$index] != 0;

    my $stone    = $args{stone};
    my $opponent = _opponent_stone($stone);

    $cells[$index] = $stone;

    my %checked_opponent;
    my %captured;
    for my $neighbor (_neighbors($index, $size)) {
        next if $cells[$neighbor] != $opponent;
        next if $checked_opponent{$neighbor};

        my ($group, $liberties) = _flood_group(\@cells, $size, $neighbor);
        $checked_opponent{$_} = 1 for @$group;

        next if $liberties != 0;
        $captured{$_} = 1 for @$group;
    }

    my @captured_indices = sort { $a <=> $b } keys %captured;
    $cells[$_] = 0 for @captured_indices;

    my (undef, $own_liberties) = _flood_group(\@cells, $size, $index);
    return {
        ok       => 0,
        reason   => 'suicide',
        captures => [],
    } if $own_liberties == 0;

    return {
        ok          => 1,
        board_bytes => pack('C*', @cells),
        captures    => \@captured_indices,
    };
}

sub _mechanics_mismatch {
    my ($perl_result, $c_result) = @_;

    return 'ok' if !!$perl_result->{ok} != !!$c_result->{ok};
    if (!$perl_result->{ok}) {
        return 'reason' if $perl_result->{reason} ne $c_result->{reason};
        return undef;
    }

    return 'board_bytes' if $perl_result->{board_bytes} ne $c_result->{board_bytes};
    return 'captures'
        if join("\0", @{ $perl_result->{captures} }) ne join("\0", @{ $c_result->{captures} });

    return undef;
}

sub _clean_error {
    my ($error) = @_;

    $error //= '';
    chomp $error;
    return $error;
}

sub _board_from_bytes {
    my ($size, $bytes) = @_;

    return GobanFTP::Board->from_canonical_bytes(
        size            => $size,
        canonical_bytes => $bytes,
    );
}

sub _flood_group {
    my ($cells, $size, $start) = @_;

    my $color = $cells->[$start];
    return ([], 0) if $color == 0;

    my @stack = ($start);
    my @stones;
    my (%seen, %liberties);
    $seen{$start} = 1;

    while (@stack) {
        my $index = pop @stack;
        push @stones, $index;

        for my $neighbor (_neighbors($index, $size)) {
            my $value = $cells->[$neighbor];
            if ($value == 0) {
                $liberties{$neighbor} = 1;
                next;
            }
            next if $value != $color || $seen{$neighbor};

            $seen{$neighbor} = 1;
            push @stack, $neighbor;
        }
    }

    @stones = sort { $a <=> $b } @stones;
    return (\@stones, scalar keys %liberties);
}

sub _neighbors {
    my ($index, $size) = @_;

    my $x = $index % $size;
    my $y = int($index / $size);

    my @neighbors;
    push @neighbors, $index - 1     if $x > 0;
    push @neighbors, $index + 1     if $x < $size - 1;
    push @neighbors, $index - $size if $y > 0;
    push @neighbors, $index + $size if $y < $size - 1;

    return @neighbors;
}

sub _stone_for_color {
    my ($color) = @_;
    return $color eq 'b' ? 1 : 2;
}

sub _opponent_stone {
    my ($stone) = @_;
    return $stone == 1 ? 2 : 1;
}

sub _opponent_color {
    my ($color) = @_;
    return $color eq 'b' ? 'w' : 'b';
}

1;

__END__

=head1 NAME

GobanFTP::Rules - first chinese-area-v1 replay rule core

=cut
