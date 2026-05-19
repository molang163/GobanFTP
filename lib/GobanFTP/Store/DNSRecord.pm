package GobanFTP::Store::DNSRecord;

use v5.34;
use strict;
use warnings;

use parent 'GobanFTP::Store';

use Carp qw(croak);
use Cwd qw(abs_path);
use File::Spec;

use GobanFTP::GameSpec qw(parse_basename);

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

    croak 'unknown Store::DNSRecord option(s): ' . join(', ', sort keys %args) if %args;

    return bless {
        record_file  => $record_file,
        records      => $records,
        owner_suffix => $owner_suffix,
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

    return @{ $self->{records} } if defined $self->{records};

    open my $fh, '<:encoding(UTF-8)', $self->{record_file}
        or croak "read $self->{record_file}: $!";

    my @rows;
    while (my $line = <$fh>) {
        chomp $line;
        $line =~ s/\A\s+|\s+\z//g;
        next if $line eq '' || $line =~ /\A#/;
        push @rows, $line;
    }

    close $fh or croak "close $self->{record_file}: $!";
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
    my $event = $record{event};
    return undef if !defined($event) || $event eq '';

    return _looks_like_event_basename($event) ? $event : undef;
}

sub _txt_owner {
    my ($row) = @_;

    my %record = _record_fields($row);
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

    my %record;
    while ($row =~ /(?:\A|\s)([A-Za-z][A-Za-z0-9_-]*)=("[^"]*"|'[^']*'|[^\s]+)/g) {
        my ($key, $value) = (lc $1, $2);
        $value =~ s/\A"(.*)"\z/$1/s;
        $value =~ s/\A'(.*)'\z/$1/s;
        $record{$key} = $value;
    }

    return %record;
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
