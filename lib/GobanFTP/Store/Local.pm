package GobanFTP::Store::Local;

use v5.34;
use strict;
use warnings;

use parent 'GobanFTP::Store';

use Carp qw(croak);
use Cwd qw(abs_path);
use Errno qw(EEXIST);
use Fcntl qw(O_CREAT O_EXCL O_WRONLY);
use File::Spec;

sub new {
    my ($class, %args) = @_;

    croak 'root is required' if !defined($args{root}) || $args{root} eq '';

    my $root = abs_path($args{root});
    croak "root does not exist: $args{root}" if !defined $root;
    croak "root is not a directory: $args{root}" if !-d $root;

    return bless { root => $root }, $class;
}

sub list_names {
    my ($self, $relative_path) = @_;

    my @components = _path_components($relative_path);
    my $dir = $self->_checked_dir_path(@components);
    opendir my $dh, $dir or croak "opendir $dir: $!";
    _assert_no_symlink_components($self->{root}, @components);

    my @names = sort grep { $_ ne '.' && $_ ne '..' } readdir $dh;

    closedir $dh or croak "closedir $dir: $!";
    return @names;
}

sub publish_event_name {
    my ($self, $game_root, $event_name) = @_;

    croak 'game_root is required'  if !defined($game_root) || $game_root eq '';
    croak 'event_name is required' if !defined($event_name) || $event_name eq '';

    my $event_component = _name_component($event_name);
    my @events_components = (_path_components($game_root), 'events');
    my $events_dir = $self->_mkdir_checked(@events_components);

    my $target = File::Spec->catfile($events_dir, $event_component);

    my $fh;
    if (!sysopen $fh, $target, O_WRONLY | O_CREAT | O_EXCL) {
        if ($! == EEXIST) {
            _assert_no_symlink_components($self->{root}, @events_components, $event_component);
            return 1;
        }
        croak "create $target: $!";
    }

    close $fh or croak "close $target: $!";
    return 1;
}

sub mkdir {
    my ($self, $path) = @_;

    $self->_mkdir_checked(_path_components($path));

    return 1;
}

sub exists_name {
    my ($self, $path, $name) = @_;

    croak 'name is required' if !defined($name) || $name eq '';

    my ($exists) = $self->_checked_child(_path_components($path), _name_component($name));
    return $exists ? 1 : 0;
}

sub _path {
    my ($self, @paths) = @_;

    my @components;
    for my $path (@paths) {
        push @components, _path_components($path);
    }

    return File::Spec->catdir($self->{root}, @components);
}

sub _checked_dir_path {
    my ($self, @components) = @_;

    _assert_no_symlink_components($self->{root}, @components);
    my $dir = File::Spec->catdir($self->{root}, @components);
    croak "path is not a directory: $dir" if !-d $dir;

    return $dir;
}

sub _checked_child {
    my ($self, @components) = @_;

    my $leaf = pop @components;
    croak 'name component is required' if !defined($leaf) || $leaf eq '';

    _assert_no_symlink_components($self->{root}, @components);

    my $parent = File::Spec->catdir($self->{root}, @components);
    my $target = File::Spec->catfile($parent, $leaf);
    return (0, $target) if !-e $target && !-l $target;

    croak "path component is a symlink: $target" if -l $target;
    return (1, $target);
}

sub _mkdir_checked {
    my ($self, @components) = @_;

    my $path = $self->{root};
    for my $component (@components) {
        $path = File::Spec->catdir($path, $component);

        croak "path component is a symlink: $path" if -l $path;

        if (-e $path) {
            croak "path component is not a directory: $path" if !-d $path;
            next;
        }

        if (!CORE::mkdir($path)) {
            if ($! == EEXIST) {
                croak "path component is a symlink: $path" if -l $path;
                croak "path component is not a directory: $path" if !-d $path;
                next;
            }
            croak "mkdir $path: $!";
        }

        croak "path component is a symlink: $path" if -l $path;
        croak "path component is not a directory: $path" if !-d $path;
    }

    return $path;
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
    croak 'name component contains invalid character' if $name =~ /[\0\\]/;
    croak 'name component may not be dot' if $name eq '.' || $name eq '..';

    return $name;
}

sub _assert_no_symlink_components {
    my ($root, @components) = @_;

    my $path = $root;
    for my $component (@components) {
        $path = File::Spec->catdir($path, $component);
        next if !-e $path && !-l $path;
        croak "path component is a symlink: $path" if -l $path;
    }

    return 1;
}

1;

__END__

=head1 NAME

GobanFTP::Store::Local - local filesystem store backend

=cut
