package GobanFTP::Projection;

use v5.34;
use strict;
use warnings;

use Exporter qw(import);
use Carp qw(croak);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempfile);
use Scalar::Util qw(blessed reftype);

use GobanFTP;
use GobanFTP::Board;
use GobanFTP::Coord qw(index_to_point);
use GobanFTP::Event qw(event_id fields from_name);
use GobanFTP::GameSpec qw(parse_basename);
use GobanFTP::Rules;

our @EXPORT_OK = qw(render_projection write_projection write_sgf_projection);

sub render_projection {
    my (%args) = @_;

    my $game_descriptor = _required($args{game_descriptor}, 'game_descriptor');
    my $result          = _required($args{replay_result},   'replay_result');
    my $events          = $args{events} // [];

    croak 'events must be an array reference' if ref($events) ne 'ARRAY';

    my ($game, $game_error) = parse_basename($game_descriptor);
    croak "game_descriptor: $game_error" if defined $game_error;

    my @canonical_ids = _canonical_ids($result);
    my %events_by_id  = _events_by_id(
        game_descriptor => $game_descriptor,
        events          => $events,
        replay_result   => $result,
    );
    my $state = _final_state($result) // _initial_state($game);

    my ($main_sgf, $variations_sgf)
        = _render_sgf($game_descriptor, $game, \@canonical_ids, \%events_by_id, $result, $events);
    my $board = _render_board($game_descriptor, $state);

    return {
        sgf                => $main_sgf,
        main_sgf           => $main_sgf,
        sgf_main           => $main_sgf,
        variations_sgf     => $variations_sgf,
        sgf_variations     => $variations_sgf,
        board              => $board,
        board_current      => $board,
        board_points       => _render_board_points($game_descriptor, $state),
        graveyard_captures => _render_captures($game_descriptor, $result),
        verdict            => _render_verdict($game_descriptor, $result, $state),
        listing            => _render_listing_transcript($game_descriptor, $events, $result),
    };
}

sub write_projection {
    my (%args) = @_;

    my $game_root = _required($args{game_root}, 'game_root');
    my $rendered  = render_projection(%args);
    my $paths     = _projection_paths($game_root);

    _assert_no_projection_symlinks($game_root, $paths);
    _make_path(
        $paths->{board_dir},
        $paths->{board_points_dir},
        $paths->{graveyard_dir},
        $paths->{sgf_dir},
        $paths->{oracle_dir},
    );
    _assert_no_projection_symlinks($game_root, $paths);

    _write_text($paths->{main_sgf},           $rendered->{sgf_main},           $game_root);
    _write_text($paths->{variations_sgf},     $rendered->{sgf_variations},     $game_root);
    _write_text($paths->{board_current},      $rendered->{board_current},      $game_root);
    _write_text($paths->{graveyard_captures}, $rendered->{graveyard_captures}, $game_root);
    _write_text($paths->{board},              $rendered->{board},              $game_root);
    _write_text($paths->{verdict},            $rendered->{verdict},            $game_root);
    _write_text($paths->{listing},            $rendered->{listing},            $game_root);

    for my $point (sort keys %{ $rendered->{board_points} }) {
        _write_text(_point_path($paths, $point), $rendered->{board_points}{$point}, $game_root);
    }

    return {
        paths    => $paths,
        rendered => $rendered,
    };
}

sub write_sgf_projection {
    my (%args) = @_;

    my $game_root = _required($args{game_root}, 'game_root');
    my $rendered  = render_projection(%args);
    my $paths     = _projection_paths($game_root);

    _assert_no_projection_symlinks($game_root, $paths);
    _make_path($paths->{sgf_dir});
    _assert_no_projection_symlinks($game_root, $paths);
    _write_text($paths->{sgf}, $rendered->{sgf}, $game_root);

    return {
        path => $paths->{sgf},
        sgf  => $rendered->{sgf},
    };
}

sub _render_sgf {
    my ($game_descriptor, $game, $canonical_ids, $events_by_id, $result, $events) = @_;

    my $main = _render_main_sgf_with_module(
        game_descriptor => $game_descriptor,
        game            => $game,
        canonical_ids   => $canonical_ids,
        events_by_id    => $events_by_id,
        replay_result   => $result,
        events          => $events,
    );
    $main //= _render_sgf_fallback($game, $canonical_ids, $events_by_id);

    my $variations = _render_variations_sgf_with_module(
        game_descriptor          => $game_descriptor,
        game                     => $game,
        events_by_id             => $events_by_id,
        legal_children_by_parent => _legal_children_by_parent($result),
        replay_result            => $result,
    );
    $variations //= $main;

    return ($main, $variations);
}

sub _render_main_sgf_with_module {
    my (%args) = @_;

    return undef if !eval { require GobanFTP::SGF; 1 };

    for my $function (qw(main_sgf render_main)) {
        my $code = GobanFTP::SGF->can($function);
        next if !defined $code;

        my $sgf = eval { $code->($args{replay_result}) };
        return $sgf if defined($sgf) && !ref($sgf);

        my @canonical_events = _canonical_events($args{canonical_ids}, $args{events_by_id});
        if (@canonical_events == @{ $args{canonical_ids} }) {
            $sgf = eval {
                $code->(
                    game_descriptor  => $args{game_descriptor},
                    canonical_events => \@canonical_events,
                );
            };
            return $sgf if defined($sgf) && !ref($sgf);
        }
    }

    for my $function (qw(render_sgf render main_line to_sgf sgf)) {
        my $code = GobanFTP::SGF->can($function);
        next if !defined $code;

        my $sgf = eval { $code->(%args) };
        return $sgf if defined($sgf) && !ref($sgf);
    }

    for my $method (qw(render_sgf render main_line to_sgf sgf)) {
        my $code = GobanFTP::SGF->can($method);
        next if !defined $code;

        my $sgf = eval { GobanFTP::SGF->$method(%args) };
        return $sgf if defined($sgf) && !ref($sgf);
    }

    return undef;
}

sub _render_variations_sgf_with_module {
    my (%args) = @_;

    return undef if !eval { require GobanFTP::SGF; 1 };

    for my $function (qw(variations_sgf render_variations)) {
        my $code = GobanFTP::SGF->can($function);
        next if !defined $code;

        my $sgf = eval { $code->($args{replay_result}) };
        return $sgf if defined($sgf) && !ref($sgf);

        $sgf = eval {
            $code->(
                game                     => $args{game},
                events_by_id             => $args{events_by_id},
                legal_children_by_parent => $args{legal_children_by_parent},
            );
        };
        return $sgf if defined($sgf) && !ref($sgf);
    }

    return undef;
}

sub _canonical_events {
    my ($canonical_ids, $events_by_id) = @_;

    my @events;
    for my $id (@$canonical_ids) {
        return () if !exists $events_by_id->{$id};
        push @events, $events_by_id->{$id};
    }

    return @events;
}

sub _render_sgf_fallback {
    my ($game, $canonical_ids, $events_by_id) = @_;

    my @properties = (
        'FF[4]',
        'GM[1]',
        'CA[UTF-8]',
        'AP[' . _sgf_escape('GobanFTP:' . ($GobanFTP::VERSION // '0')) . ']',
        'SZ[' . _sgf_escape($game->{size}) . ']',
        'KM[' . _sgf_escape(_komi_text($game->{komi_milli})) . ']',
        'RU[' . _sgf_escape($game->{rules}) . ']',
        'PB[' . _sgf_escape($game->{black}) . ']',
        'PW[' . _sgf_escape($game->{white}) . ']',
    );

    my $sgf = '(;' . join('', @properties);

    for my $id (@$canonical_ids) {
        my $event = $events_by_id->{$id};
        croak "canonical event not available: $id" if !defined $event;

        my $fields = _event_fields($event);
        my $color  = uc($fields->{color} // '');
        croak "canonical event has invalid color: $id" if $color ne 'B' && $color ne 'W';

        my $action = $fields->{action} // '';
        if ($action =~ /\Aplay-([a-z][a-z])\z/) {
            $sgf .= ';' . $color . '[' . _sgf_escape($1) . ']';
        }
        elsif ($action eq 'pass') {
            $sgf .= ';' . $color . '[]';
        }
        elsif ($action eq 'resign') {
            $sgf .= ';' . $color . '[]C[resign]';
        }
        else {
            croak "canonical event has invalid action: $id";
        }
    }

    return $sgf . ")\n";
}

sub _render_board {
    my ($game_descriptor, $state) = @_;

    my $board = $state->{board};
    croak 'replay state does not include a board'
        if !blessed($board) || !$board->can('size') || !$board->can('get');

    my $size        = $board->size;
    my $label_width = length($size);
    my @letters     = map { chr(ord('a') + $_) } 0 .. $size - 1;
    my @lines = (
        "game=$game_descriptor",
        "size=$size",
        'next_color=' . ($state->{next_color} // ''),
        'terminal=' . ($state->{terminal} ? 1 : 0),
        (' ' x ($label_width + 1)) . join(' ', @letters),
    );

    for my $y (0 .. $size - 1) {
        my @cells = map { _stone_text($board->get($_, $y)) } 0 .. $size - 1;
        push @lines, sprintf('%*d %s', $label_width, $size - $y, join(' ', @cells));
    }

    return join("\n", @lines) . "\n";
}

sub _render_board_points {
    my ($game_descriptor, $state) = @_;

    my $board = $state->{board};
    croak 'replay state does not include a board'
        if !blessed($board) || !$board->can('size') || !$board->can('get');

    my $size = $board->size;
    my %points;
    for my $index (0 .. ($size * $size) - 1) {
        my ($point, $error) = index_to_point($index, $size);
        croak "board point: $error" if defined $error;

        my $x = $index % $size;
        my $y = int($index / $size);
        $points{$point} = join("\n",
            "game=$game_descriptor",
            "point=$point",
            "x=$x",
            "y=$y",
            'row=' . ($size - $y),
            'column=' . substr($point, 0, 1),
            'stone=' . _stone_name($board->get($x, $y)),
            '',
        );
    }

    return \%points;
}

sub _render_captures {
    my ($game_descriptor, $result) = @_;

    my @lines = (
        "game=$game_descriptor",
    );
    my @capture_lines;
    my $capture_number = 0;

    for my $step (_canonical_steps($result)) {
        next if ref($step) ne 'HASH';
        my $captures = ref($step->{captures}) eq 'ARRAY' ? $step->{captures} : [];
        next if !@$captures;

        my $fields = ref($step->{fields}) eq 'HASH' ? $step->{fields} : {};
        my $move_color = $fields->{color} // '';
        my $captured_color = _opponent_color($move_color) // '';

        for my $point (@$captures) {
            $capture_number++;
            push @capture_lines,
                "capture.$capture_number.event_id=" . ($step->{event_id} // $step->{id} // ''),
                "capture.$capture_number.ply=" . ($fields->{ply} // ''),
                "capture.$capture_number.move_color=$move_color",
                "capture.$capture_number.captured_color=$captured_color",
                "capture.$capture_number.point=$point";
        }
    }

    push @lines, "captures=$capture_number", @capture_lines;
    return join("\n", @lines) . "\n";
}

sub _render_verdict {
    my ($game_descriptor, $result, $state) = @_;

    my @diagnostics = _diagnostics($result);
    my $fork        = _fork($result);
    my @canonical   = _canonical_ids($result);
    my @legal       = _legal_ids($result);
    my $has_validation_error = grep { ($_->{code} // '') ne 'fork' } @diagnostics;
    my $status = $has_validation_error ? 'validation' : defined($fork) ? 'fork' : 'ok';

    my @lines = (
        "game=$game_descriptor",
        "status=$status",
        'canonical_moves=' . scalar(@canonical),
        'legal_moves=' . scalar(@legal),
        'diagnostics=' . scalar(@diagnostics),
        'canonical_ids=' . join(',', @canonical),
        'legal_ids=' . join(',', @legal),
        'next_color=' . ($state->{next_color} // ''),
        'terminal=' . ($state->{terminal} ? 1 : 0),
    );
    push @lines, 'terminal_reason=' . $state->{terminal_reason} if defined $state->{terminal_reason};

    if (defined $fork) {
        push @lines, 'fork.parent_id=' . ($fork->{parent_id} // '');
        push @lines, 'fork.child_ids=' . join(',', @{ $fork->{child_ids} // [] });
    }

    my $i = 0;
    for my $diagnostic (@diagnostics) {
        $i++;
        for my $key (sort keys %$diagnostic) {
            my $value = _diagnostic_value($diagnostic->{$key});
            next if !defined $value;
            push @lines, "diagnostic.$i.$key=$value";
        }
    }

    return join("\n", @lines) . "\n";
}

sub _render_listing_transcript {
    my ($game_descriptor, $events, $result) = @_;

    my @event_names = _listing_event_names($events);
    my @diagnostics = _diagnostics($result);
    my @lines = (
        'GOFTP/1 FTP LISTING TRANSCRIPT',
        '',
        'This file is a projection for readers. It is not a consensus input.',
        'Core replay reads the game descriptor basename and the direct event basenames',
        'returned by NLST events/. It does not read event file bytes.',
        '',
        'Game descriptor basename:',
        $game_descriptor,
        '',
        'Transcript:',
        '',
        '220 GobanFTP fixture service ready.',
        'USER anonymous',
        '331 Anonymous login accepted for fixture access.',
        'PASS anonymous@',
        '230 Login successful.',
        'TYPE I',
        '200 Type set to I.',
        "CWD /goftp/$game_descriptor",
        '250 Directory changed.',
        'NLST events/',
        '150 Opening data connection for events/.',
    );

    push @lines, @event_names;
    push @lines,
        '226 NLST complete.',
        'QUIT',
        '221 Goodbye.',
        '',
        'Commands not sent by GOFTP/1 replay:',
        '',
        'SIZE events/<event-basename>',
        'MDTM events/<event-basename>',
        'RETR events/<event-basename>',
        '',
        'Replay note:',
        '',
        'The ' . _count_word(scalar(@event_names)) . ' names printed by NLST events/ are the current event basenames.',
        'GOFTP/1 replay uses those basenames and the game descriptor basename.',
        'RETR, SIZE, MDTM, entry type, file size, file bytes, FTP mtime, and server',
        'listing order do not participate in replay.';

    if (@diagnostics) {
        push @lines,
            '',
            'Replay diagnostics:',
            '',
            _diagnostic_lines(@diagnostics);
    }

    return join("\n", @lines) . "\n";
}

sub _projection_paths {
    my ($game_root) = @_;

    my $projections = File::Spec->catdir($game_root, 'projections');
    my $sgf_dir     = File::Spec->catdir($projections, 'sgf');
    my $board_dir   = File::Spec->catdir($projections, 'board');
    my $oracle_dir  = File::Spec->catdir($projections, 'oracle');

    return {
        board_dir     => $board_dir,
        board_points_dir => File::Spec->catdir($board_dir, 'points'),
        graveyard_dir => File::Spec->catdir($projections, 'graveyard'),
        sgf_dir       => $sgf_dir,
        oracle_dir    => $oracle_dir,
        sgf           => File::Spec->catfile($sgf_dir, 'main.sgf'),
        main_sgf      => File::Spec->catfile($sgf_dir, 'main.sgf'),
        variations_sgf => File::Spec->catfile($sgf_dir, 'variations.sgf'),
        sgf_variations => File::Spec->catfile($sgf_dir, 'variations.sgf'),
        board_current => File::Spec->catfile($board_dir, 'current.txt'),
        graveyard_captures => File::Spec->catfile($projections, 'graveyard', 'captures.txt'),
        board         => File::Spec->catfile($oracle_dir, 'board.txt'),
        verdict       => File::Spec->catfile($oracle_dir, 'verdict.txt'),
        listing       => File::Spec->catfile($oracle_dir, 'listing.txt'),
    };
}

sub _point_path {
    my ($paths, $point) = @_;
    return File::Spec->catfile($paths->{board_points_dir}, "$point.txt");
}

sub _write_text {
    my ($path, $text, $game_root) = @_;

    my $dir = _parent_dir($path);
    _assert_no_symlink_path($dir, $game_root);
    _make_path($dir);
    _assert_no_symlink_path($dir, $game_root);

    my ($fh, $tmp) = tempfile('.gobanftp-tmp-XXXXXX', DIR => $dir, UNLINK => 0);
    binmode $fh, ':encoding(UTF-8)';
    print {$fh} $text;
    close $fh or do {
        my $error = $!;
        unlink $tmp;
        croak "storage: close $tmp: $error";
    };

    rename $tmp, $path or do {
        my $error = $!;
        unlink $tmp;
        croak "storage: rename $tmp to $path: $error";
    };

    return 1;
}

sub _make_path {
    my (@dirs) = @_;

    eval { make_path(@dirs); 1 } or do {
        my $error = $@ || $!;
        chomp $error;
        croak "storage: mkdir " . join(', ', @dirs) . ": $error";
    };

    return 1;
}

sub _parent_dir {
    my ($path) = @_;

    my ($volume, $directories) = File::Spec->splitpath($path);
    return File::Spec->catpath($volume, $directories, '');
}

sub _assert_no_projection_symlinks {
    my ($game_root, $paths) = @_;

    for my $dir (
        $game_root,
        File::Spec->catdir($game_root, 'projections'),
        $paths->{board_dir},
        $paths->{board_points_dir},
        $paths->{graveyard_dir},
        $paths->{sgf_dir},
        $paths->{oracle_dir},
    ) {
        _assert_no_symlink_path($dir);
    }

    return 1;
}

sub _assert_no_symlink_path {
    my ($path, $game_root) = @_;

    if (defined $game_root && $game_root ne '') {
        return _assert_no_symlink_path_under($game_root, $path);
    }

    my @parts = File::Spec->splitdir($path);
    my $current = File::Spec->file_name_is_absolute($path) ? File::Spec->rootdir : '';
    for my $part (@parts) {
        next if !defined($part) || $part eq '' || $part eq File::Spec->rootdir;
        $current = $current eq '' || $current eq File::Spec->rootdir
            ? File::Spec->catdir($current, $part)
            : File::Spec->catdir($current, $part);
        next if !-e $current && !-l $current;
        croak "storage: path component is a symlink: $current" if -l $current;
    }

    return 1;
}

sub _assert_no_symlink_path_under {
    my ($game_root, $path) = @_;

    my $base = File::Spec->rel2abs($game_root);
    my $abs  = File::Spec->rel2abs($path);
    my $rel  = File::Spec->abs2rel($abs, $base);

    croak "storage: projection path escapes game root: $path"
        if File::Spec->file_name_is_absolute($rel)
        || $rel eq File::Spec->updir
        || $rel =~ m{\A[.][.](?:\z|[\\/])};

    croak "storage: path component is a symlink: $base" if -l $base;

    my $current = $base;
    for my $part (File::Spec->splitdir($rel)) {
        next if !defined($part) || $part eq '' || $part eq File::Spec->curdir;
        croak "storage: projection path escapes game root: $path" if $part eq File::Spec->updir;
        $current = File::Spec->catdir($current, $part);
        next if !-e $current && !-l $current;
        croak "storage: path component is a symlink: $current" if -l $current;
    }

    return 1;
}

sub _events_by_id {
    my (%args) = @_;

    my %events;
    my $result = $args{replay_result};

    if (blessed($result) && $result->can('events_by_id')) {
        my $value = $result->events_by_id;
        if (ref($value) eq 'HASH') {
            %events = %$value;
        }
        else {
            %events = $result->events_by_id;
        }
    }
    elsif (ref($result) eq 'HASH' && ref($result->{events_by_id}) eq 'HASH') {
        %events = %{ $result->{events_by_id} };
    }

    for my $raw (@{ $args{events} }) {
        next if ref $raw;

        my ($event, $error) = from_name($raw, game_descriptor => $args{game_descriptor});
        next if defined $error;
        $events{ event_id($event) } //= $event;
    }

    return %events;
}

sub _canonical_ids {
    my ($result) = @_;
    return $result->canonical_ids if blessed($result) && $result->can('canonical_ids');
    return @{ $result->{canonical_ids} // [] } if _hash_like($result);
    return ();
}

sub _legal_ids {
    my ($result) = @_;
    return $result->legal_ids if blessed($result) && $result->can('legal_ids');
    return @{ $result->{legal_ids} // [] } if _hash_like($result);
    return ();
}

sub _legal_children_by_parent {
    my ($result) = @_;
    return $result->legal_children_by_parent if blessed($result) && $result->can('legal_children_by_parent');
    return $result->{legal_children_by_parent} if _hash_like($result) && ref($result->{legal_children_by_parent}) eq 'HASH';
    return {};
}

sub _canonical_steps {
    my ($result) = @_;
    return $result->canonical_steps if blessed($result) && $result->can('canonical_steps');
    return @{ $result->{canonical_steps} // [] } if _hash_like($result);
    return ();
}

sub _diagnostics {
    my ($result) = @_;
    return $result->diagnostics if blessed($result) && $result->can('diagnostics');
    return @{ $result->{diagnostics} // [] } if _hash_like($result);
    return ();
}

sub _fork {
    my ($result) = @_;
    return $result->fork if blessed($result) && $result->can('fork');
    return $result->{fork} if _hash_like($result);
    return undef;
}

sub _final_state {
    my ($result) = @_;
    return $result->final_state if blessed($result) && $result->can('final_state');
    return $result->{final_state} if _hash_like($result);
    return undef;
}

sub _initial_state {
    my ($game) = @_;
    return GobanFTP::Rules->new(size => $game->{size}, rules => $game->{rules})->initial_state;
}

sub _event_fields {
    my ($event) = @_;
    return $event->fields if blessed($event) && $event->can('fields');
    return fields($event);
}

sub _stone_text {
    my ($stone) = @_;
    return $stone == 1 ? 'B' : $stone == 2 ? 'W' : '.';
}

sub _stone_name {
    my ($stone) = @_;
    return $stone == 1 ? 'black' : $stone == 2 ? 'white' : 'empty';
}

sub _opponent_color {
    my ($color) = @_;
    return 'w' if defined($color) && $color eq 'b';
    return 'b' if defined($color) && $color eq 'w';
    return undef;
}

sub _diagnostic_value {
    my ($value) = @_;

    return '' if !defined $value;
    return join(',', @$value) if ref($value) eq 'ARRAY';
    return undef if ref($value);

    return $value;
}

sub _listing_event_names {
    my ($events) = @_;

    my @names;
    for my $raw (@$events) {
        if (!ref $raw) {
            push @names, $raw;
            next;
        }

        if (ref($raw) eq 'HASH' && exists $raw->{name} && !ref($raw->{name})) {
            push @names, $raw->{name};
        }
    }

    return sort { $a cmp $b } @names;
}

sub _diagnostic_lines {
    my (@diagnostics) = @_;

    my @lines;
    for my $diagnostic (@diagnostics) {
        next if ref($diagnostic) ne 'HASH';

        my @fields;
        for my $key (sort keys %$diagnostic) {
            my $value = _diagnostic_value($diagnostic->{$key});
            next if !defined $value;
            push @fields, "$key=$value";
        }

        push @lines, 'diagnostic ' . join(' ', @fields) if @fields;
    }

    return @lines;
}

sub _count_word {
    my ($count) = @_;

    my @words = qw(zero one two three four five six seven eight nine ten);
    return $words[$count] if defined($count) && $count >= 0 && $count <= $#words;
    return $count;
}

sub _komi_text {
    my ($komi_milli) = @_;

    return '0' if !$komi_milli;
    return int($komi_milli / 1000) if $komi_milli % 1000 == 0;

    my $text = sprintf('%.3f', $komi_milli / 1000);
    $text =~ s/0+\z//;
    $text =~ s/\.\z//;
    return $text;
}

sub _sgf_escape {
    my ($value) = @_;

    $value //= '';
    $value =~ s/\\/\\\\/g;
    $value =~ s/\]/\\]/g;
    $value =~ s/\r\n|\r|\n/\\n/g;

    return $value;
}

sub _required {
    my ($value, $name) = @_;
    croak "$name is required" if !defined $value || $value eq '';
    return $value;
}

sub _hash_like {
    my ($value) = @_;
    return defined($value) && ref($value) && (reftype($value) // '') eq 'HASH';
}

1;

__END__

=head1 NAME

GobanFTP::Projection - rebuild local projection files from replay output

=cut
