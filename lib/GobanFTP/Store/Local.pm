package GobanFTP::Store::Local;

use v5.34;
use strict;
use warnings;

use parent 'GobanFTP::Store';

use Carp qw(croak);
use Cwd qw(abs_path);
use Errno qw(EEXIST);
use Fcntl qw(O_CREAT O_EXCL O_WRONLY);
use File::Path qw(make_path);
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

    my $dir = $self->_path($relative_path);
    opendir my $dh, $dir or croak "opendir $dir: $!";

    my @names = sort grep { $_ ne '.' && $_ ne '..' } readdir $dh;

    closedir $dh or croak "closedir $dir: $!";
    return @names;
}

sub publish_event_name {
    my ($self, $game_root, $event_name) = @_;

    croak 'game_root is required'  if !defined($game_root) || $game_root eq '';
    croak 'event_name is required' if !defined($event_name) || $event_name eq '';

    my $event_component = _name_component($event_name);
    my $events_dir = $self->_path($game_root, 'events');
    make_path($events_dir);

    my $target = File::Spec->catfile($events_dir, $event_component);

    my $fh;
    if (!sysopen $fh, $target, O_WRONLY | O_CREAT | O_EXCL) {
        return 1 if $! == EEXIST;
        croak "create $target: $!";
    }

    close $fh or croak "close $target: $!";
    return 1;
}

sub mkdir {
    my ($self, $path) = @_;

    my $dir = $self->_path($path);
    make_path($dir);

    return 1;
}

sub exists_name {
    my ($self, $path, $name) = @_;

    croak 'name is required' if !defined($name) || $name eq '';

    my $target = File::Spec->catfile($self->_path($path), _name_component($name));
    return -e $target ? 1 : 0;
}

sub _path {
    my ($self, @paths) = @_;

    my @components;
    for my $path (@paths) {
        push @components, _path_components($path);
    }

    return File::Spec->catdir($self->{root}, @components);
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

1;

__END__

=head1 NAME

GobanFTP::Store::Local - local filesystem store backend

=cut
