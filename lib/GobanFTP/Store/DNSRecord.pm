package GobanFTP::Store::DNSRecord;

use v5.34;
use strict;
use warnings;

use parent 'GobanFTP::Store';

use Carp qw(croak);
use Cwd qw(abs_path);
use File::Spec;

use GobanFTP::GameSpec qw(parse_basename);

use constant {
    DEFAULT_MAX_FILE_BYTES => 1_048_576,
    DEFAULT_MAX_LINES      => 10_000,
    DEFAULT_MAX_RECORDS    => 10_000,
    DEFAULT_MAX_LINE_BYTES => 4_096,
};

sub new {
    my ($class, %args) = @_;

    my $record_file = delete($args{record_file}) // delete($args{file});
    my $records = delete($args{records});
    croak 'record_file or records is required'
        if (!defined($record_file) || $record_file eq '') && !defined $records;
    croak 'record_file cannot be combined with records'
        if defined($record_file) && $record_file ne '' && defined $records;
    croak 'records must be an array reference'
        if defined $records && ref($records) ne 'ARRAY';

    if (defined($record_file) && $record_file ne '') {
        my $record_file_abs = abs_path($record_file);
        croak "record file does not exist: $record_file" if !defined $record_file_abs;
        croak "record file is not a file: $record_file" if !-f $record_file_abs;
        $record_file = $record_file_abs;
    }

    my $owner_suffix = delete($args{owner_suffix}) // '';
    $owner_suffix = _canon_owner($owner_suffix) if defined($owner_suffix) && $owner_suffix ne '';
    my $max_file_bytes = delete($args{max_file_bytes}) // DEFAULT_MAX_FILE_BYTES;
    my $max_lines      = delete($args{max_lines})      // DEFAULT_MAX_LINES;
    my $max_records    = delete($args{max_records})    // DEFAULT_MAX_RECORDS;
    my $max_line_bytes = delete($args{max_line_bytes}) // DEFAULT_MAX_LINE_BYTES;
    $max_file_bytes = _positive_int_option('max_file_bytes', $max_file_bytes);
    $max_lines      = _positive_int_option('max_lines', $max_lines);
    $max_records    = _positive_int_option('max_records', $max_records);
    $max_line_bytes = _positive_int_option('max_line_bytes', $max_line_bytes);

    croak 'unknown Store::DNSRecord option(s): ' . join(', ', sort keys %args) if %args;

    return bless {
        record_file  => $record_file,
        records      => $records,
        owner_suffix => $owner_suffix,
        max_file_bytes => $max_file_bytes,
        max_lines      => $max_lines,
        max_records    => $max_records,
        max_line_bytes => $max_line_bytes,
    }, $class;
}

sub list_names {
    my ($self, $relative_path) = @_;

    my @components = _path_components($relative_path);
    return $self->_game_names if !@components;

    my $game = $components[0];
    return $self->_game_child_names($game) if @components == 1;

    if (@components == 2 && $components[1] eq 'events') {
        return $self->_event_names_for_game($game);
    }

    return ();
}

sub publish_event_name {
    croak 'dns record store is read-only';
}

sub mkdir {
    croak 'dns record store is read-only';
}

sub exists_name {
    my ($self, $path, $name) = @_;

    croak 'name is required' if !defined($name) || $name eq '';

    my $component = _name_component($name);
    return (grep { $_ eq $component } $self->list_names($path)) ? 1 : 0;
}

sub _game_names {
    my ($self) = @_;

    my %seen;
    for my $row ($self->_record_rows) {
        my $owner = _txt_owner($row);
        next if !defined $owner;

        my $game = _game_from_events_owner($owner, $self->{owner_suffix});
        $seen{$game} = 1 if defined $game;
    }

    return sort keys %seen;
}

sub _game_child_names {
    my ($self, $game) = @_;

    my @events = $self->_event_names_for_game($game);
    return @events ? ('events') : ();
}

sub _event_names_for_game {
    my ($self, $game) = @_;

    my %seen;
    for my $row ($self->_record_rows_for_game($game)) {
        my $event = _event_value($row);
        $seen{$event} = 1 if defined $event;
    }

    return sort keys %seen;
}

sub _record_rows {
    my ($self) = @_;

    return $self->_bounded_record_rows(@{ $self->{records} }) if defined $self->{records};

    my $size = -s $self->{record_file};
    croak 'dns record file too large'
        if defined($size) && $size > $self->{max_file_bytes};

    open my $fh, '<:encoding(UTF-8)', $self->{record_file}
        or croak "read $self->{record_file}: $!";

    my @rows;
    my $line_count = 0;
    while (my $line = <$fh>) {
        $line_count++;
        croak 'dns record line count exceeded' if $line_count > $self->{max_lines};
        chomp $line;
        croak 'dns record line too long' if length($line) > $self->{max_line_bytes};
        $line =~ s/\A\s+|\s+\z//g;
        next if $line eq '' || $line =~ /\A#/;
        croak 'dns record limit exceeded' if @rows >= $self->{max_records};
        push @rows, $line;
    }

    close $fh or croak "close $self->{record_file}: $!";
    return @rows;
}

sub _bounded_record_rows {
    my ($self, @rows) = @_;

    croak 'dns record line count exceeded' if @rows > $self->{max_lines};
    croak 'dns record limit exceeded' if @rows > $self->{max_records};
    for my $row (@rows) {
        croak 'dns record line too long' if defined($row) && length($row) > $self->{max_line_bytes};
    }

    return @rows;
}

sub _record_rows_for_game {
    my ($self, $game) = @_;

    return grep {
        my $owner = _txt_owner($_);
        defined($owner) && _owner_matches_events_game($owner, $game, $self->{owner_suffix});
    } $self->_record_rows;
}

sub _event_value {
    my ($row) = @_;

    my %record = _record_fields($row);
    return undef if $record{__gobanftp_error};
    my $event = $record{event};
    return undef if !defined($event) || $event eq '';

    return _looks_like_event_basename($event) ? $event : undef;
}

sub _txt_owner {
    my ($row) = @_;

    my %record = _record_fields($row);
    return undef if $record{__gobanftp_error};
    return undef if lc($record{type} // '') ne 'txt';

    my $owner = _canon_owner($record{owner} // '');
    return $owner eq '' ? undef : $owner;
}

sub _game_from_events_owner {
    my ($owner, $owner_suffix) = @_;

    my @labels = split /\./, $owner;
    my @suffix = defined($owner_suffix) && $owner_suffix ne '' ? split(/\./, $owner_suffix) : ();

    return undef if @labels < @suffix + 2;
    return undef if @suffix && !_has_suffix(\@labels, \@suffix);

    my $end = @labels - @suffix;
    for my $i (0 .. $end - 1) {
        next if $labels[$i] ne 'events';

        if (@suffix) {
            my @game = @labels[$i + 1 .. $end - 1];
            my $game = join '.', @game;
            return $game if _looks_like_game_descriptor($game);
            next;
        }

        for my $last ($i + 1 .. $end - 1) {
            my $game = join '.', @labels[$i + 1 .. $last];
            return $game if _looks_like_game_descriptor($game);
        }
    }

    return undef;
}

sub _owner_matches_events_game {
    my ($owner, $game, $owner_suffix) = @_;

    my @game_labels = split /\./, lc $game;

    my @labels = split /\./, $owner;
    my @suffix = defined($owner_suffix) && $owner_suffix ne '' ? split(/\./, $owner_suffix) : ();

    return 0 if @labels < @suffix + 2;
    return 0 if @suffix && !_has_suffix(\@labels, \@suffix);

    my $end = @labels - @suffix;
    for my $i (0 .. $end - 1) {
        next if $labels[$i] ne 'events';
        next if $i + @game_labels >= $end;
        next if @suffix && $i + 1 + @game_labels != $end;

        my $matched = 1;
        for my $j (0 .. $#game_labels) {
            if (($labels[$i + 1 + $j] // '') ne $game_labels[$j]) {
                $matched = 0;
                last;
            }
        }
        return 1 if $matched;
    }

    return 0;
}

sub _has_suffix {
    my ($labels, $suffix) = @_;

    return 1 if !@$suffix;
    return 0 if @$labels < @$suffix;

    my $offset = @$labels - @$suffix;
    for my $i (0 .. $#$suffix) {
        return 0 if $labels->[$offset + $i] ne $suffix->[$i];
    }

    return 1;
}

sub _record_fields {
    my ($row) = @_;

    $row = _strip_inline_comment($row);

    my %record;
    my %seen;
    while ($row =~ /(?:\A|\s)([A-Za-z][A-Za-z0-9_-]*)=("[^"]*"|'[^']*'|[^\s]+)/g) {
        my ($key, $value) = (lc $1, $2);
        if ($key =~ /\A(?:type|owner|event)\z/ && $seen{$key}++) {
            return (__gobanftp_error => "duplicate.$key");
        }
        $value =~ s/\A"(.*)"\z/$1/s;
        $value =~ s/\A'(.*)'\z/$1/s;
        $record{$key} = $value;
    }

    return %record;
}

sub _strip_inline_comment {
    my ($row) = @_;

    $row //= '';
    my ($out, $quote) = ('', undef);
    my @chars = split //, $row;
    while (@chars) {
        my $char = shift @chars;
        if (defined $quote) {
            $out .= $char;
            $quote = undef if $char eq $quote;
            next;
        }
        if ($char eq '"' || $char eq "'") {
            $quote = $char;
            $out .= $char;
            next;
        }
        last if $char eq '#' || $char eq ';';
        $out .= $char;
    }

    $out =~ s/\s+\z//;
    return $out;
}

sub _positive_int_option {
    my ($name, $value) = @_;

    croak "$name must be a positive integer"
        if !defined($value) || ref($value) || $value !~ /\A[1-9][0-9]*\z/;

    return 0 + $value;
}

sub _path_components {
    my ($path) = @_;

    return () if !defined($path) || $path eq '';

    croak 'path must be relative' if File::Spec->file_name_is_absolute($path);
    croak 'path contains invalid character' if $path =~ /[\0\\]/;

    my @components;
    for my $component (split m{/+}, $path) {
        next if $component eq '';
        push @components, _name_component($component);
    }

    return @components;
}

sub _name_component {
    my ($name) = @_;

    croak 'name component is required' if !defined($name) || $name eq '';
    croak 'name component must be a basename' if $name =~ m{/};
    croak 'name component contains invalid character' if $name =~ /[\0\\:\r\n]/;
    croak 'name component may not be dot' if $name eq '.' || $name eq '..';
    croak 'name component is outside the DNS record public alphabet'
        if $name !~ /\A[a-z0-9._-]+\z/;

    return $name;
}

sub _canon_owner {
    my ($owner) = @_;

    return '' if !defined $owner;
    $owner = lc $owner;
    $owner =~ s/\A\.//;
    $owner =~ s/\.\z//;
    return $owner;
}

sub _looks_like_event_basename {
    my ($name) = @_;
    return defined($name) && $name =~ /\A(?:m[0-9]+|a[0-9]+)(?:\.|\z)[a-z0-9._-]*\z/ ? 1 : 0;
}

sub _looks_like_game_descriptor {
    my ($name) = @_;
    my (undef, $error) = parse_basename($name);
    return defined($error) ? 0 : 1;
}

1;

__END__

=head1 NAME

GobanFTP::Store::DNSRecord - read-only DNS-like record-set store backend

=head1 DESCRIPTION

This backend reads DNS-like TXT record rows from a local text file. It performs
no network DNS lookups and is read-only: publish and mkdir operations always
fail.

=cut
