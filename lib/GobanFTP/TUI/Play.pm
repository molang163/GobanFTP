package GobanFTP::TUI::Play;

use v5.34;
use strict;
use warnings;

use Carp qw(croak);
use Exporter qw(import);
use IO::Select;
use POSIX qw(:termios_h);

our @EXPORT_OK = qw(
    apply_tui_event
    board_layout
    feed_tui_input
    hit_test_board
    new_input_state
    point_for_cursor
    render_play_frame
    run_play_tui
);

sub new_input_state {
    return { pending => '' };
}

sub feed_tui_input {
    my ($state, $bytes) = @_;
    croak 'tui.input_state' if ref($state) ne 'HASH';

    $state->{pending} .= defined($bytes) ? $bytes : '';
    my @events;

    while (length $state->{pending}) {
        my $pending = $state->{pending};
        my $first = substr($pending, 0, 1);

        if ($first eq "\e") {
            last if length($pending) == 1;

            if ($pending =~ /\A(\e\[([ABCD]))/) {
                _consume($state, $1);
                push @events, _arrow_event($2);
                next;
            }

            if ($pending =~ /\A(\eO([ABCD]))/) {
                _consume($state, $1);
                push @events, _arrow_event($2);
                next;
            }

            if ($pending =~ /\A(\e\[<([0-9]+);([0-9]+);([0-9]+)([Mm]))/) {
                my ($sequence, $button, $col, $row, $final) = ($1, 0 + $2, 0 + $3, 0 + $4, $5);
                _consume($state, $sequence);
                push @events, {
                    type   => 'mouse_press',
                    button => $button,
                    col    => $col,
                    row    => $row,
                } if $final eq 'M' && ($button & 3) == 0;
                next;
            }

            if ($pending =~ /\A(\e\[<[0-9;]*)([qQpPrRhjkl \r\n])/) {
                _consume($state, $1);
                next;
            }

            last if $pending =~ /\A\eO\z/;
            last if $pending =~ /\A\e\[[0-9;?<]*\z/;

            if ($pending =~ /\A(\e\[[0-9;?<]*[A-Za-z~])/) {
                _consume($state, $1);
                next;
            }

            _consume($state, substr($pending, 0, 2));
            next;
        }

        _consume($state, $first);
        if ($first eq "\r" || $first eq "\n" || $first eq ' ') {
            push @events, { type => 'submit' };
            next;
        }
        if ($first eq 'q' || $first eq 'Q') {
            push @events, { type => 'quit' };
            next;
        }
        if ($first eq 'p' || $first eq 'P') {
            push @events, { type => 'action', action => 'pass' };
            next;
        }
        if ($first eq 'R') {
            push @events, { type => 'action', action => 'resign' };
            next;
        }
        if ($first eq 'r') {
            push @events, { type => 'refresh' };
            next;
        }
        if ($first =~ /\A[hjkl]\z/) {
            push @events, _vim_event($first);
            next;
        }
    }

    return @events;
}

sub point_for_cursor {
    my ($cursor, $size) = @_;
    croak 'tui.cursor' if ref($cursor) ne 'ARRAY' || @$cursor != 2;
    _assert_size($size);

    my ($row, $col) = @$cursor;
    croak 'tui.cursor' if !_is_uint($row) || !_is_uint($col) || $row >= $size || $col >= $size;
    return chr(97 + $col) . chr(97 + $row);
}

sub board_layout {
    my (%args) = @_;
    my $size = _assert_size($args{size});
    my $label_width = length($size);

    return {
        size           => $size,
        first_cell_row => 0 + ($args{first_cell_row} // 1),
        first_cell_col => 0 + ($args{first_cell_col} // ($label_width + 2)),
        cell_step      => 0 + ($args{cell_step} // 3),
    };
}

sub hit_test_board {
    my ($layout, $col, $row) = @_;
    croak 'tui.layout' if ref($layout) ne 'HASH';
    return undef if !_is_uint($col) || !_is_uint($row);

    my $size = _assert_size($layout->{size});
    my $first_row = $layout->{first_cell_row};
    my $first_col = $layout->{first_cell_col};
    my $step = $layout->{cell_step} || 3;

    return undef if $row < $first_row || $row >= $first_row + $size;
    my $offset = $col - $first_col;
    return undef if $offset < -1;

    my $x = int(($offset + int($step / 2)) / $step);
    return undef if $x < 0 || $x >= $size;
    return undef if abs($offset - ($x * $step)) > 1;

    my $y = $row - $first_row;
    return chr(97 + $x) . chr(97 + $y);
}

sub apply_tui_event {
    my (%args) = @_;
    my $event = $args{event};
    my $cursor = $args{cursor};
    my $size = _assert_size($args{size});

    croak 'tui.event' if ref($event) ne 'HASH';
    croak 'tui.cursor' if ref($cursor) ne 'ARRAY' || @$cursor != 2;

    my ($row, $col) = @$cursor;
    ($row, $col) = (_clamp($row, 0, $size - 1), _clamp($col, 0, $size - 1));

    if (($event->{type} // '') eq 'move_cursor') {
        $row = _clamp($row + ($event->{dy} // 0), 0, $size - 1);
        $col = _clamp($col + ($event->{dx} // 0), 0, $size - 1);
        return { type => 'cursor', cursor => [ $row, $col ] };
    }

    if (($event->{type} // '') eq 'submit') {
        return {
            type   => 'action',
            action => point_for_cursor([ $row, $col ], $size),
            cursor => [ $row, $col ],
        };
    }

    if (($event->{type} // '') eq 'action') {
        return {
            type   => 'action',
            action => $event->{action},
            cursor => [ $row, $col ],
        };
    }

    if (($event->{type} // '') eq 'mouse_press') {
        my $point = hit_test_board($args{layout}, $event->{col}, $event->{row});
        return { type => 'noop', cursor => [ $row, $col ] } if !defined $point;

        my $mouse_cursor = _cursor_for_point($point);
        return {
            type   => 'action',
            action => $point,
            cursor => $mouse_cursor,
        };
    }

    return {
        type   => $event->{type} // 'noop',
        cursor => [ $row, $col ],
    };
}

sub render_play_frame {
    my (%args) = @_;
    my $context = $args{context};
    croak 'context is required' if ref($context) ne 'HASH';

    my $result = $context->{replay_result};
    my $state = _final_state($result);
    my $board = ref($state) eq 'HASH' ? $state->{board} : undef;
    croak 'play.tui.board'
        if !ref($board) || !$board->can('size') || !$board->can('get');

    my $size = _assert_size($board->size);
    my $cursor = _normal_cursor($args{cursor} // [ 0, 0 ], $size);
    my $ansi = exists($args{ansi}) ? $args{ansi} ? 1 : 0 : 1;

    my $status = _status_for_result($result);
    my $game = _game($result);
    my $event_set = ref($context->{event_set}) eq 'HASH' ? $context->{event_set} : {};
    my @canonical = _canonical_ids($result);
    my @diagnostics = _diagnostics($result);
    my $turn = _turn_text($state, $game);
    my $cursor_point = point_for_cursor($cursor, $size);

    my @lines = (
        'GOBANFTP-PLAY-TUI/1',
        'truth=event-filenames',
        'game=' . ($context->{game_descriptor} // ''),
        'now=' . _now_text($state, $game),
        'verdict=' . _verdict_text($status, @diagnostics),
        'action=Click a point or press Enter to publish ' . $cursor_point,
        'status=' . $status
            . ' events=' . scalar(@{ $context->{events} // [] })
            . ' accepted=' . ($event_set->{event_count} // 0)
            . ' canonical=' . scalar(@canonical),
        'root=' . ($event_set->{event_set_root} // ''),
        'turn=' . $turn . ' cursor=' . $cursor_point,
    );
    push @lines, 'message=' . _single_line($args{message}) if defined($args{message}) && $args{message} ne '';
    push @lines, 'diagnostics=' . join(',', map { $_->{code} // 'unknown' } @diagnostics) if @diagnostics;
    push @lines, 'keys=arrows/hjkl move  enter/click play  p pass  R resign  r refresh  q quit';
    push @lines, '';

    my $label_width = length($size);
    my $header_row = @lines + 1;
    my $layout = board_layout(
        size           => $size,
        first_cell_row => $header_row + 1,
        first_cell_col => $label_width + 2,
        cell_step      => 3,
    );

    my @letters = map { chr(97 + $_) } 0 .. $size - 1;
    push @lines, (' ' x ($label_width + 1)) . join('  ', @letters);
    for my $y (0 .. $size - 1) {
        my @cells;
        for my $x (0 .. $size - 1) {
            my $glyph = _stone_glyph($board->get($x, $y));
            if ($ansi && $cursor->[0] == $y && $cursor->[1] == $x) {
                $glyph = "\e[7m$glyph\e[0m";
            }
            push @cells, $glyph;
        }
        push @lines, sprintf('%*d %s', $label_width, $size - $y, join('  ', @cells));
    }

    my $frame = join("\n", @lines) . "\n";
    return wantarray ? ($frame, $layout) : $frame;
}

sub run_play_tui {
    my (%args) = @_;
    my $load_context = _required_code($args{load_context}, 'load_context');
    my $publish_action = _required_code($args{publish_action}, 'publish_action');
    my $input_fh = $args{input_fh} // \*STDIN;
    my $output_fh = $args{output_fh} // \*STDOUT;
    my $script = $args{script};
    my $ansi = exists($args{ansi}) ? $args{ansi} ? 1 : 0 : 1;
    my $cursor = _normal_cursor($args{cursor} // [ 0, 0 ], 26);
    my $input_state = new_input_state();
    my $message = $args{message} // '';
    my $context;
    my $layout;
    my $raw_guard;
    my $session;

    if (!defined $script) {
        croak 'play.tui.tty' if !-t $input_fh || !-t $output_fh;
        $raw_guard = _enter_terminal($input_fh, $output_fh);
    }

    my $signal_handler = sub {
        my ($signal) = @_;
        die "play.tui.signal.$signal\n";
    };
    local $SIG{INT}  = $signal_handler;
    local $SIG{TERM} = $signal_handler;
    local $SIG{HUP}  = $signal_handler;
    local $SIG{QUIT} = $signal_handler;

    my $ok = eval {
        ($context, $layout) = _draw_frame(
            output_fh    => $output_fh,
            load_context => $load_context,
            cursor       => $cursor,
            message      => $message,
            ansi         => $ansi,
        );

        SESSION:
        while (1) {
            my $bytes = defined($script)
                ? _shift_script_chunk(\$script)
                : _read_terminal_chunk($input_fh);
            if (!defined $bytes) {
                $session = { exit => 0, stage => 'eof' };
                last SESSION;
            }

            my @events = feed_tui_input($input_state, $bytes);
            for my $event (@events) {
                my $state = _final_state($context->{replay_result});
                my $board = ref($state) eq 'HASH' ? $state->{board} : undef;
                my $size = ref($board) && $board->can('size') ? $board->size : 19;
                my $decision = apply_tui_event(
                    event  => $event,
                    cursor => $cursor,
                    size   => $size,
                    layout => $layout,
                );
                $cursor = $decision->{cursor} if ref($decision->{cursor}) eq 'ARRAY';

                my $type = $decision->{type} // 'noop';
                if ($type eq 'quit') {
                    $session = { exit => 0, stage => 'quit' };
                    last SESSION;
                }
                if ($type eq 'refresh' || $type eq 'cursor' || $type eq 'noop') {
                    $message = $type eq 'refresh' ? 'reloaded' : '';
                    ($context, $layout) = _draw_frame(
                        output_fh    => $output_fh,
                        load_context => $load_context,
                        cursor       => $cursor,
                        message      => $message,
                        ansi         => $ansi,
                    );
                    next;
                }
                if ($type eq 'action') {
                    my $publish = $publish_action->($decision->{action});
                    if (ref($publish) eq 'HASH' && ($publish->{stage} // '') eq 'published') {
                        $session = {
                            exit    => $publish->{exit} // 0,
                            stage   => 'published',
                            publish => $publish,
                        };
                        last SESSION;
                    }

                    if (ref($publish) eq 'HASH' && ($publish->{stage} // '') ne 'candidate') {
                        $session = {
                            exit    => $publish->{exit} // 1,
                            stage   => 'publish',
                            publish => $publish,
                        };
                        last SESSION;
                    }

                    $context = ref($publish) eq 'HASH' && ref($publish->{context}) eq 'HASH'
                        ? $publish->{context}
                        : $load_context->();
                    $message = _publish_message($publish);
                    my $rendered;
                    ($rendered, $layout) = render_play_frame(
                        context => $context,
                        cursor  => $cursor,
                        message => $message,
                        ansi    => $ansi,
                    );
                    _write_frame($output_fh, $rendered);
                    next;
                }
            }
        }

        $session //= { exit => 0, stage => 'eof' };
        1;
    };
    my $error = $@;

    _leave_terminal($raw_guard) if $raw_guard;
    die $error if !$ok;
    return $session;
}

sub _draw_frame {
    my (%args) = @_;
    my $context = $args{load_context}->();
    my ($frame, $layout) = render_play_frame(
        context => $context,
        cursor  => $args{cursor},
        message => $args{message},
        ansi    => $args{ansi},
    );
    _write_frame($args{output_fh}, $frame);
    return ($context, $layout);
}

sub _write_frame {
    my ($fh, $frame) = @_;
    print {$fh} "\e[H\e[2J", $frame;
}

sub _read_terminal_chunk {
    my ($fh) = @_;
    my $buffer = '';
    my $read = sysread($fh, $buffer, 64);
    return undef if !defined($read) || $read == 0;

    my $select = IO::Select->new($fh);
    while ($select->can_read(0.001)) {
        my $more = '';
        my $more_read = sysread($fh, $more, 64);
        last if !defined($more_read) || $more_read == 0;
        $buffer .= $more;
        last if length($more) < 64;
    }
    return $buffer;
}

sub _shift_script_chunk {
    my ($script_ref) = @_;
    return undef if !defined($$script_ref) || $$script_ref eq '';
    my $chunk = substr($$script_ref, 0, 1, '');
    return $chunk;
}

sub _enter_terminal {
    my ($input_fh, $output_fh) = @_;
    my $fd = fileno($input_fh);
    croak 'play.tui.tty' if !defined $fd;

    my $old = POSIX::Termios->new;
    $old->getattr($fd);

    my $raw = POSIX::Termios->new;
    $raw->getattr($fd);
    $raw->setiflag($raw->getiflag & ~(BRKINT | ICRNL | INPCK | ISTRIP | IXON));
    $raw->setoflag($raw->getoflag & ~OPOST);
    $raw->setcflag($raw->getcflag | CS8);
    $raw->setlflag($raw->getlflag & ~(ECHO | ICANON | IEXTEN));
    $raw->setcc(VMIN, 1);
    $raw->setcc(VTIME, 0);
    $raw->setattr($fd, TCSANOW);

    print {$output_fh} "\e[?1049h\e[?25l\e[?1000h\e[?1006h";
    return {
        fd        => $fd,
        termios   => $old,
        output_fh => $output_fh,
    };
}

sub _leave_terminal {
    my ($guard) = @_;
    return if ref($guard) ne 'HASH';

    my $output_fh = $guard->{output_fh};
    print {$output_fh} "\e[?1006l\e[?1000l\e[?25h\e[?1049l" if $output_fh;
    $guard->{termios}->setattr($guard->{fd}, TCSANOW) if $guard->{termios};
}

sub _publish_message {
    my ($publish) = @_;
    return 'publish failed' if ref($publish) ne 'HASH';
    my $stage = $publish->{stage} // 'unknown';
    my $exit = $publish->{exit} // '';
    return "candidate rejected exit=$exit" if $stage eq 'candidate';
    return "publish $stage exit=$exit";
}

sub _consume {
    my ($state, $sequence) = @_;
    substr($state->{pending}, 0, length($sequence), '');
}

sub _arrow_event {
    my ($arrow) = @_;
    return { type => 'move_cursor', dx => 0,  dy => -1 } if $arrow eq 'A';
    return { type => 'move_cursor', dx => 0,  dy => 1 }  if $arrow eq 'B';
    return { type => 'move_cursor', dx => 1,  dy => 0 }  if $arrow eq 'C';
    return { type => 'move_cursor', dx => -1, dy => 0 };
}

sub _vim_event {
    my ($key) = @_;
    return { type => 'move_cursor', dx => -1, dy => 0 } if $key eq 'h';
    return { type => 'move_cursor', dx => 0,  dy => 1 } if $key eq 'j';
    return { type => 'move_cursor', dx => 0,  dy => -1 } if $key eq 'k';
    return { type => 'move_cursor', dx => 1,  dy => 0 };
}

sub _normal_cursor {
    my ($cursor, $size) = @_;
    $size = _assert_size($size);
    croak 'tui.cursor' if ref($cursor) ne 'ARRAY' || @$cursor != 2;
    return [
        _clamp(_is_uint($cursor->[0]) ? $cursor->[0] : 0, 0, $size - 1),
        _clamp(_is_uint($cursor->[1]) ? $cursor->[1] : 0, 0, $size - 1),
    ];
}

sub _cursor_for_point {
    my ($point) = @_;
    croak 'tui.point' if !defined($point) || $point !~ /\A([a-z])([a-z])\z/;
    return [ ord($2) - 97, ord($1) - 97 ];
}

sub _single_line {
    my ($value) = @_;
    $value //= '';
    $value =~ s/[\r\n]+/ /g;
    return $value;
}

sub _turn_text {
    my ($state, $game) = @_;
    my $color = ref($state) eq 'HASH' ? ($state->{next_color} // '') : '';
    my $label = $color eq 'b' ? 'black' : $color eq 'w' ? 'white' : 'none';
    my $player = ref($game) eq 'HASH'
        ? $color eq 'b' ? ($game->{black} // '')
        : $color eq 'w' ? ($game->{white} // '')
        :                 ''
        : '';
    return length($player) ? "$label($player)" : $label;
}

sub _now_text {
    my ($state, $game) = @_;
    my $color = ref($state) eq 'HASH' ? ($state->{next_color} // '') : '';
    my $label = $color eq 'b' ? 'Black' : $color eq 'w' ? 'White' : 'No side';
    my $player = ref($game) eq 'HASH'
        ? $color eq 'b' ? ($game->{black} // '')
        : $color eq 'w' ? ($game->{white} // '')
        :                 ''
        : '';
    return length($player) ? "$label to play: $player" : "$label to play";
}

sub _verdict_text {
    my ($status, @diagnostics) = @_;
    return 'No fork detected' if $status eq 'ok';
    return 'Fork detected; no move will publish until it is resolved'
        if $status eq 'fork';

    my @codes = map { $_->{code} // 'unknown' } grep { ref($_) eq 'HASH' } @diagnostics;
    return @codes
        ? 'Validation blocked: ' . join(',', @codes)
        : 'Validation blocked';
}

sub _stone_glyph {
    my ($stone) = @_;
    return $stone == 1 ? 'B' : $stone == 2 ? 'W' : '.';
}

sub _status_for_result {
    my ($result) = @_;
    my @diagnostics = _diagnostics($result);
    return 'ok' if !@diagnostics;
    return (grep { ($_->{code} // '') ne 'fork' } @diagnostics) ? 'failed' : 'fork';
}

sub _canonical_ids {
    my ($result) = @_;
    return () if !ref $result;
    return $result->canonical_ids if eval { $result->can('canonical_ids') };
    return @{ $result->{canonical_ids} // [] } if ref($result) eq 'HASH';
    return ();
}

sub _diagnostics {
    my ($result) = @_;
    return () if !ref $result;
    return $result->diagnostics if eval { $result->can('diagnostics') };
    return @{ $result->{diagnostics} // [] } if ref($result) eq 'HASH';
    return ();
}

sub _final_state {
    my ($result) = @_;
    return undef if !ref $result;
    return $result->final_state if eval { $result->can('final_state') };
    return $result->{final_state} if ref($result) eq 'HASH';
    return undef;
}

sub _game {
    my ($result) = @_;
    return undef if !ref $result;
    return $result->game if eval { $result->can('game') };
    return $result->{game} if ref($result) eq 'HASH';
    return undef;
}

sub _required_code {
    my ($code, $name) = @_;
    croak "$name callback is required" if ref($code) ne 'CODE';
    return $code;
}

sub _assert_size {
    my ($size) = @_;
    croak 'tui.size' if !_is_uint($size) || $size < 1 || $size > 26;
    return 0 + $size;
}

sub _is_uint {
    my ($value) = @_;
    return defined($value) && !ref($value) && $value =~ /\A(?:0|[1-9][0-9]*)\z/;
}

sub _clamp {
    my ($value, $min, $max) = @_;
    $value = $min if $value < $min;
    $value = $max if $value > $max;
    return 0 + $value;
}

1;

__END__

=head1 NAME

GobanFTP::TUI::Play - local terminal input and board display adapter

=cut
