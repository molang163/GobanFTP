package GobanFTP::Store::GitTree;

use v5.34;
use strict;
use warnings;

use parent 'GobanFTP::Store';

use Carp qw(croak);
use Cwd qw(abs_path);
use File::Spec;
use File::Temp qw(tempfile);
use POSIX qw(dup2);

sub new {
    my ($class, %args) = @_;

    my $repo = delete $args{repo};
    croak 'repo is required' if !defined($repo) || $repo eq '';

    my $repo_abs = abs_path($repo);
    croak "repo does not exist: $repo" if !defined $repo_abs;
    croak "repo is not a directory: $repo" if !-d $repo_abs;

    my $treeish = delete($args{treeish}) // 'HEAD';
    $treeish = 'HEAD' if $treeish eq '';
    _assert_treeish($treeish);

    my $git = delete($args{git}) // 'git';
    croak 'git executable is required' if !defined($git) || $git eq '';
    croak 'git executable contains invalid character' if $git =~ /[\0\r\n]/;

    croak 'unknown Store::GitTree option(s): ' . join(', ', sort keys %args) if %args;

    return bless {
        repo    => $repo_abs,
        treeish => $treeish,
        git     => $git,
    }, $class;
}

sub list_names {
    my ($self, $relative_path) = @_;

    my @components = _path_components($relative_path);
    my $tree = @components ? "$self->{treeish}:" . join('/', @components) : $self->{treeish};
    my @raw = $self->_git_ls_tree_names($tree);

    my %seen;
    return sort grep { !$seen{$_}++ } grep { _public_component($_) } @raw;
}

sub publish_event_name {
    croak 'git tree store is read-only';
}

sub mkdir {
    croak 'git tree store is read-only';
}

sub exists_name {
    my ($self, $path, $name) = @_;

    my $component = _name_component($name);
    return (grep { $_ eq $component } $self->list_names($path)) ? 1 : 0;
}

sub _git_ls_tree_names {
    my ($self, $tree) = @_;

    my @cmd = ($self->{git}, '-C', $self->{repo}, 'ls-tree', '-z', '--name-only', $tree);
    my ($stdout, undef) = _capture_command(@cmd);
    return grep { defined && $_ ne '' } split /\0/, $stdout;
}

sub _capture_command {
    my (@cmd) = @_;

    my ($out_fh, $out_path) = tempfile();
    my ($err_fh, $err_path) = tempfile();
    binmode $out_fh;
    binmode $err_fh;

    my $pid = fork;
    croak 'git ls-tree failed: ' . _clean_error($!) if !defined $pid;

    if ($pid == 0) {
        dup2(fileno($out_fh), 1) or exit 127;
        dup2(fileno($err_fh), 2) or exit 127;
        exec @cmd;
        exit 127;
    }

    close $out_fh;
    close $err_fh;
    waitpid $pid, 0;
    my $status = $?;

    my $stdout = _slurp_raw($out_path);
    my $stderr = _slurp_raw($err_path);
    unlink $out_path;
    unlink $err_path;

    if ($status != 0) {
        my $exit = $status >> 8;
        my $signal = $status & 127;
        my $suffix = _clean_error($stderr);
        $suffix = $signal ? "signal $signal" : "exit $exit" if $suffix eq '';
        croak "git ls-tree failed: $suffix";
    }

    return ($stdout, $stderr);
}

sub _slurp_raw {
    my ($path) = @_;

    open my $fh, '<:raw', $path or croak "read $path: $!";
    local $/;
    my $content = <$fh> // '';
    close $fh or croak "close $path: $!";

    return $content;
}

sub _path_components {
    my ($path) = @_;

    return () if !defined($path) || $path eq '';

    croak 'path must be relative' if File::Spec->file_name_is_absolute($path);

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
    croak 'name component is outside the git-tree public alphabet'
        if !_public_component($name);

    return $name;
}

sub _public_component {
    my ($name) = @_;
    return defined($name)
        && $name ne ''
        && $name ne '.'
        && $name ne '..'
        && $name =~ /\A[a-z0-9._-]+\z/ ? 1 : 0;
}

sub _assert_treeish {
    my ($treeish) = @_;

    croak 'treeish is required' if !defined($treeish) || $treeish eq '';
    croak 'treeish may not start with dash' if $treeish =~ /\A-/;
    croak 'treeish contains invalid character' if $treeish =~ /[\0:\r\n]/;

    return 1;
}

sub _clean_error {
    my ($error) = @_;
    return '' if !defined $error;
    chomp $error;
    $error =~ s/\s+/ /g;
    $error =~ s/\A\s+|\s+\z//g;
    return $error;
}

1;

__END__

=head1 NAME

GobanFTP::Store::GitTree - read-only Git tree store backend

=head1 DESCRIPTION

This backend enumerates direct child names from a declared Git tree-ish. It is
read-only: publish and mkdir operations fail before creating commits, refs, or
working-tree files.

=cut
