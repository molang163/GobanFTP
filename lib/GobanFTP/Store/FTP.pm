package GobanFTP::Store::FTP;

use v5.34;
use strict;
use warnings;

use parent 'GobanFTP::Store';

use Carp qw(croak);
use File::Temp qw(tempfile);
use Net::FTP ();

sub new {
    my ($class, %args) = @_;

    my $ftp = delete $args{ftp};
    my $root = delete($args{root}) // '';
    my $publish_mode = delete($args{publish_mode}) // 'rename';
    my $publish_confirm_attempts = delete($args{publish_confirm_attempts}) // 3;
    my $publish_rename_attempts  = delete($args{publish_rename_attempts})  // 2;
    my $publish_confirm_delay    = delete($args{publish_confirm_delay})    // 0;

    croak 'publish_mode must be rename or mkdir'
        if $publish_mode ne 'rename' && $publish_mode ne 'mkdir';
    $publish_confirm_attempts = _positive_int_option('publish_confirm_attempts', $publish_confirm_attempts);
    $publish_rename_attempts  = _positive_int_option('publish_rename_attempts',  $publish_rename_attempts);
    $publish_confirm_delay    = _nonnegative_number_option('publish_confirm_delay', $publish_confirm_delay);

    my ($root_absolute, @root_components) = _root_components($root);

    if (!defined $ftp) {
        my $host = delete $args{host};
        croak 'host is required' if !defined($host) || $host eq '';

        my $ftp_class = delete($args{ftp_class}) // 'Net::FTP';
        _load_class($ftp_class);

        my %connect_args = %{ delete($args{ftp_args}) // {} };
        for my $pair (
            [ port => 'Port' ],
            [ passive => 'Passive' ],
            [ timeout => 'Timeout' ],
            [ debug => 'Debug' ],
        ) {
            my ($from, $to) = @$pair;
            $connect_args{$to} = delete $args{$from} if exists $args{$from};
        }
        for my $key (qw(Port Passive Timeout Debug SSL LocalAddr Domain Family BlockSize Firewall FirewallType)) {
            $connect_args{$key} = delete $args{$key} if exists $args{$key};
        }
        for my $key (grep { /\ASSL_/ } keys %args) {
            $connect_args{$key} = delete $args{$key};
        }

        my $user = delete $args{user};
        my $password = delete $args{password};
        my $account = delete $args{account};

        croak 'unknown Store::FTP option(s): ' . join(', ', sort keys %args) if %args;

        $ftp = $ftp_class->new($host, %connect_args)
            or croak "connect FTP $host failed: $@";

        my @login_args;
        push @login_args, $user if defined $user;
        push @login_args, $password if defined $password;
        push @login_args, $account if defined $account;

        $ftp->login(@login_args)
            or croak 'FTP login failed' . _ftp_message_suffix($ftp);
    }

    croak 'unknown Store::FTP option(s): ' . join(', ', sort keys %args) if %args;

    return bless {
        ftp           => $ftp,
        root_absolute => $root_absolute,
        root_parts    => \@root_components,
        publish_mode  => $publish_mode,
        publish_confirm_attempts => $publish_confirm_attempts,
        publish_rename_attempts  => $publish_rename_attempts,
        publish_confirm_delay    => $publish_confirm_delay,
    }, $class;
}

sub list_names {
    my ($self, $relative_path) = @_;

    my $remote = $self->_remote_path($relative_path);
    my @raw = $self->_listing($remote);

    my %seen;
    my @names = grep { !$seen{$_}++ }
        grep { defined && $_ ne '' && $_ ne '.' && $_ ne '..' }
        map { _direct_listing_name($_, $remote) } @raw;

    return sort @names;
}

sub publish_event_name {
    my ($self, $game_root, $event_name) = @_;

    croak 'game_root is required'  if !defined($game_root) || $game_root eq '';
    croak 'event_name is required' if !defined($event_name) || $event_name eq '';

    my @game_components = _path_components($game_root);
    croak 'game_root is required' if !@game_components;

    my $event_component = _name_component($event_name);
    my $events_path = join '/', @game_components, 'events';

    if ($self->{publish_mode} eq 'mkdir') {
        return $self->mkdir(join '/', @game_components, 'events', $event_component);
    }

    $self->mkdir($events_path);
    $self->mkdir(join '/', @game_components, 'tmp');

    return 1 if $self->exists_name($events_path, $event_component);

    my $tmp_component = _tmp_component_for_event($event_component);
    my $tmp_remote = $self->_remote_path(join('/', @game_components, 'tmp'), $tmp_component);
    my $target_remote = $self->_remote_path($events_path, $event_component);

    $self->{ftp}->binary
        or $self->_croak_ftp('set binary mode');

    my ($fh, $local_tmp) = tempfile();
    close $fh or croak "close temporary upload file: $!";

    my $put_ok = eval { $self->{ftp}->put($local_tmp, $tmp_remote) };
    my $put_error = $@;
    unlink $local_tmp;

    die $put_error if $put_error;
    $put_ok or $self->_croak_ftp("put $tmp_remote");

    my ($last_rename_message, $last_confirm_error) = ('', undef);
    for my $attempt (1 .. $self->{publish_rename_attempts}) {
        if ($self->{ftp}->rename($tmp_remote, $target_remote)) {
            my ($confirmed, $confirm_error) = $self->_confirm_event_visible($events_path, $event_component);
            return 1 if $confirmed;
            $self->_croak_confirm_failed($target_remote, $confirm_error);
        }

        $last_rename_message = _ftp_message($self->{ftp});
        my ($confirmed, $confirm_error) = $self->_confirm_event_visible($events_path, $event_component);
        return 1 if $confirmed;
        $last_confirm_error = $confirm_error if defined $confirm_error && $confirm_error ne '';
    }

    $self->_croak_rename_failed($tmp_remote, $target_remote, $last_rename_message, $last_confirm_error);
}

sub mkdir {
    my ($self, $path) = @_;

    my @components = _path_components($path);
    return 1 if !@components;

    my $remote = $self->_remote_path(join '/', @components);
    my $made = $self->{ftp}->mkdir($remote, 1);
    return 1 if $made;

    my $name = $components[-1];
    my $parent = join '/', @components[0 .. $#components - 1];
    return 1 if $self->exists_name($parent, $name);

    $self->_croak_ftp("mkdir $remote");
}

sub exists_name {
    my ($self, $path, $name) = @_;

    croak 'name is required' if !defined($name) || $name eq '';

    my $component = _name_component($name);
    return (grep { $_ eq $component } $self->list_names($path)) ? 1 : 0;
}

sub quit {
    my ($self) = @_;

    return $self->{ftp}->quit if $self->{ftp}->can('quit');
    return 1;
}

sub _listing {
    my ($self, $remote) = @_;

    my @raw = $self->_raw_listing($remote);
    my $message = _ftp_message($self->{ftp});

    if (!@raw && _message_looks_like_empty_listing($message)) {
        return () if $self->_remote_entry_listed_by_parent($remote);
        croak "list $remote failed: $message";
    }

    croak "list $remote failed: $message" if _message_looks_like_error($message);

    return grep { defined } @raw;
}

sub _raw_listing {
    my ($self, $remote) = @_;

    my $ftp = $self->{ftp};
    my $method = $ftp->can('ls') ? 'ls'
        : $ftp->can('listing') ? 'listing'
        : undef;

    croak 'FTP object must implement ls or listing' if !defined $method;

    my @raw;
    my $ok = eval {
        @raw = $remote eq ''
            ? $ftp->$method()
            : $ftp->$method($remote);
        1;
    };
    croak "list $remote failed: $@" if !$ok;

    @raw = @{ $raw[0] } if @raw == 1 && ref($raw[0]) eq 'ARRAY';
    return grep { defined } @raw;
}

sub _remote_entry_listed_by_parent {
    my ($self, $remote) = @_;

    return 1 if !defined($remote) || $remote eq '' || $remote eq '/';

    $remote =~ s{/+\z}{};
    return 1 if $remote eq '' || $remote eq '/';

    my ($parent, $child) = $remote =~ m{\A(.*/)?([^/]+)\z};
    $parent //= '';
    $parent =~ s{/+\z}{};

    my @parent_raw = eval { $self->_raw_listing($parent) };
    return 0 if $@;

    my $message = _ftp_message($self->{ftp});
    return 0 if _message_looks_like_error($message);

    for my $entry (@parent_raw) {
        my $name = _direct_listing_name($entry, $parent);
        return 1 if defined($name) && $name eq $child;
    }

    return 0;
}

sub _message_looks_like_error {
    my ($message) = @_;
    return 0 if !defined($message) || $message eq '';
    return $message =~ /(?:\b(?:4|5)[0-9][0-9]\b|fail|denied|error|not found|no such|unavailable|timeout)/i ? 1 : 0;
}

sub _message_looks_like_empty_listing {
    my ($message) = @_;
    return 0 if !defined($message) || $message eq '';
    return $message =~ /\b(?:no files?|no matching files?|no entries|empty directory|directory empty)\b/i ? 1 : 0;
}

sub _confirm_event_visible {
    my ($self, $events_path, $event_component) = @_;

    my $last_error;
    for my $attempt (1 .. $self->{publish_confirm_attempts}) {
        my $visible = eval { $self->exists_name($events_path, $event_component) };
        if ($@) {
            $last_error = $@;
        }
        elsif ($visible) {
            return (1, undef);
        }
        else {
            $last_error = undef;
        }

        $self->_wait_for_publish_confirm if $attempt < $self->{publish_confirm_attempts};
    }

    return (0, $last_error);
}

sub _wait_for_publish_confirm {
    my ($self) = @_;

    return 1 if $self->{publish_confirm_delay} <= 0;
    select undef, undef, undef, $self->{publish_confirm_delay};
    return 1;
}

sub _remote_path {
    my ($self, @paths) = @_;

    my @components = @{ $self->{root_parts} };
    for my $path (@paths) {
        push @components, _path_components($path);
    }

    my $path = join '/', @components;
    return '/' if $path eq '' && $self->{root_absolute};
    return $self->{root_absolute} ? "/$path" : $path;
}

sub _direct_listing_name {
    my ($entry, $remote) = @_;

    return undef if !defined $entry;

    my $name = "$entry";
    $name =~ s/\r?\n\z//;
    $name =~ s/\A\s+//;
    $name =~ s/\s+\z//;
    return undef if $name eq '';
    return undef if $name =~ /\Atotal\s+\d+\z/i;

    $name = _name_from_long_listing($name);
    $name =~ s{\A\./+}{};
    $name =~ s{/+\z}{};
    $name =~ s{\A/+}{} if defined($remote) && $remote eq '/';

    my @prefixes = _listing_prefixes($remote);
    for my $prefix (@prefixes) {
        next if $prefix eq '';
        return undef if $name eq $prefix;
        if ($name =~ s{\A\Q$prefix\E/+}{}) {
            last;
        }
    }

    $name =~ s{/+\z}{};
    return undef if $name eq '' || $name eq '.' || $name eq '..';
    return undef if $name =~ m{/};

    return $name;
}

sub _listing_prefixes {
    my ($remote) = @_;

    return () if !defined($remote) || $remote eq '';

    my %seen;
    my @prefixes;
    for my $prefix ($remote, _without_leading_slash($remote)) {
        next if !defined($prefix) || $prefix eq '' || $seen{$prefix}++;
        push @prefixes, $prefix;
    }

    return sort { length($b) <=> length($a) } @prefixes;
}

sub _name_from_long_listing {
    my ($line) = @_;

    if ($line =~ /\A[bcdlps-][rwxSsTt-]{9}[+.@]?\s+/) {
        my @fields = split /\s+/, $line, 9;
        if (defined $fields[8]) {
            $fields[8] =~ s/\s+->\s+.*\z// if substr($line, 0, 1) eq 'l';
            return $fields[8];
        }
    }

    if ($line =~ /\A\d{2}-\d{2}-\d{2,4}\s+\d{2}:\d{2}\s*(?:AM|PM)\s+(?:<DIR>|\d+)\s+(.+)\z/i) {
        return $1;
    }

    return $line;
}

sub _without_leading_slash {
    my ($path) = @_;
    $path =~ s{\A/+}{};
    return $path;
}

sub _root_components {
    my ($root) = @_;

    return (0) if !defined($root) || $root eq '';

    croak 'root contains invalid character' if $root =~ /[\0\\\r\n]/;

    my $absolute = $root =~ m{\A/} ? 1 : 0;
    $root =~ s{\A/+}{};
    $root =~ s{/+\z}{};

    return ($absolute) if $root eq '';
    return ($absolute, map { _name_component($_) } split m{/+}, $root);
}

sub _path_components {
    my ($path) = @_;

    return () if !defined($path) || $path eq '';

    croak 'path must be relative' if $path =~ m{\A/};
    croak 'path contains invalid character' if $path =~ /[\0\\\r\n]/;

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
    croak 'name component contains invalid character' if $name =~ /[\0\\\r\n]/;
    croak 'name component may not be dot' if $name eq '.' || $name eq '..';

    return $name;
}

sub _tmp_component_for_event {
    my ($event_name) = @_;

    return "$1-$2.part"
        if $event_name =~ /(?:\A|\.)by-([a-z0-9_-]+)\.n-([a-z0-9_-]+)(?:\.|\z)/;

    my $tmp = $event_name;
    $tmp =~ s/[^a-z0-9._-]+/-/g;
    return "$tmp.part";
}

sub _load_class {
    my ($class) = @_;

    return 1 if $class->can('new');

    (my $file = "$class.pm") =~ s{::}{/}g;
    require $file;

    return 1;
}

sub _positive_int_option {
    my ($name, $value) = @_;

    croak "$name must be a positive integer"
        if !defined($value) || ref($value) || $value !~ /\A[1-9][0-9]*\z/;

    return 0 + $value;
}

sub _nonnegative_number_option {
    my ($name, $value) = @_;

    croak "$name must be a non-negative number"
        if !defined($value) || ref($value) || $value !~ /\A(?:0|[1-9][0-9]*)(?:\.[0-9]+)?\z/;

    return 0 + $value;
}

sub _croak_ftp {
    my ($self, $operation) = @_;

    croak "$operation failed" . _ftp_message_suffix($self->{ftp});
}

sub _croak_confirm_failed {
    my ($self, $target_remote, $confirm_error) = @_;

    croak "confirm $target_remote failed after $self->{publish_confirm_attempts} listing attempt(s)"
        . _error_suffix($confirm_error);
}

sub _croak_rename_failed {
    my ($self, $tmp_remote, $target_remote, $rename_message, $confirm_error) = @_;

    my $suffix = _error_suffix($confirm_error) || _message_text_suffix($rename_message);
    croak "rename $tmp_remote to $target_remote failed$suffix";
}

sub _ftp_message_suffix {
    my ($ftp) = @_;

    my $message = _ftp_message($ftp);
    return _message_text_suffix($message);
}

sub _message_text_suffix {
    my ($message) = @_;

    return '' if !defined($message) || $message eq '';
    $message =~ s/\s+\z//;
    return '' if $message eq '';
    return ": $message";
}

sub _error_suffix {
    my ($error) = @_;

    return '' if !defined($error) || $error eq '';
    $error =~ s/\s+\z//;
    return '' if $error eq '';
    return ": $error";
}

sub _ftp_message {
    my ($ftp) = @_;

    return '' if !$ftp || !$ftp->can('message');

    my $message = eval { scalar $ftp->message };
    return '' if !defined($message) || $message eq '';

    $message =~ s/\s+\z//;
    return $message;
}

1;

__END__

=head1 NAME

GobanFTP::Store::FTP - FTP store backend for listing-first game state

=head1 DESCRIPTION

The FTP store reads authoritative state through directory listings only. Event
publishing defaults to a zero-byte temporary upload followed by a rename into
C<events/>; C<publish_mode =E<gt> 'mkdir'> publishes directory-shaped events.

Rename publishing confirms the final event basename through bounded
C<events/> listings. C<publish_confirm_attempts>,
C<publish_rename_attempts>, and C<publish_confirm_delay> tune that boundary
without changing or regenerating the event name.

=cut
