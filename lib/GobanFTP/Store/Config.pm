package GobanFTP::Store::Config;

use v5.34;
use strict;
use warnings;

use Exporter qw(import);
use Carp qw(croak);
use Cwd qw(abs_path);
use File::Basename qw(basename dirname);
use File::Spec;

use GobanFTP::GameSpec qw(parse_basename);
use GobanFTP::Store::DNSRecord;
use GobanFTP::Store::FTP;
use GobanFTP::Store::GitTree;
use GobanFTP::Store::Local;
use GobanFTP::Store::WebDAV;

our @EXPORT_OK = qw(context_for_descriptor context_for_game_arg store_from_env store_mode);

sub store_mode {
    my $mode = lc($ENV{GOBANFTP_STORE} // 'local');
    $mode = 'local' if $mode eq '';

    croak 'GOBANFTP_STORE must be local, ftp, git-tree, dns-record, or webdav'
        if $mode ne 'local'
        && $mode ne 'ftp'
        && $mode ne 'git-tree'
        && $mode ne 'dns-record'
        && $mode ne 'webdav';

    return $mode;
}

sub store_from_env {
    my (%args) = @_;

    my $mode = $args{mode} // store_mode();
    return GobanFTP::Store::Local->new(root => _local_root()) if $mode eq 'local';
    return _ftp_store_from_env() if $mode eq 'ftp';
    return _git_tree_store_from_env() if $mode eq 'git-tree';
    return _dns_record_store_from_env() if $mode eq 'dns-record';
    return _webdav_store_from_env() if $mode eq 'webdav';

    croak 'GOBANFTP_STORE must be local, ftp, git-tree, dns-record, or webdav';
}

sub context_for_descriptor {
    my ($descriptor) = @_;

    _assert_descriptor($descriptor);

    my $mode = store_mode();
    my $store = store_from_env(mode => $mode);

    if ($mode eq 'ftp' || $mode eq 'git-tree' || $mode eq 'dns-record' || $mode eq 'webdav') {
        return {
            store           => $store,
            store_kind      => $mode,
            game_descriptor => $descriptor,
            store_game_root => $descriptor,
            game_root       => $descriptor,
        };
    }

    my $root_abs = _local_root_abs();
    return {
        store           => $store,
        store_kind      => 'local',
        game_descriptor => $descriptor,
        store_game_root => $descriptor,
        game_root       => File::Spec->catdir($root_abs, $descriptor),
    };
}

sub context_for_game_arg {
    my ($game_arg, %args) = @_;

    croak 'game argument is required' if !defined($game_arg) || $game_arg eq '';

    my $mode = store_mode();
    return _ftp_context_for_arg($game_arg) if $mode eq 'ftp';
    return _git_tree_context_for_arg($game_arg) if $mode eq 'git-tree';
    return _dns_record_context_for_arg($game_arg) if $mode eq 'dns-record';
    return _webdav_context_for_arg($game_arg) if $mode eq 'webdav';
    return _local_context_for_arg($game_arg, %args);
}

sub _ftp_context_for_arg {
    my ($game_arg) = @_;

    my $descriptor = basename($game_arg);
    _assert_descriptor($descriptor);
    my $store = store_from_env(mode => 'ftp');

    return {
        store           => $store,
        store_kind      => 'ftp',
        game_descriptor => $descriptor,
        store_game_root => $descriptor,
        game_root       => $descriptor,
    };
}

sub _webdav_context_for_arg {
    my ($game_arg) = @_;

    my $descriptor = basename($game_arg);
    _assert_descriptor($descriptor);
    my $store = store_from_env(mode => 'webdav');

    return {
        store           => $store,
        store_kind      => 'webdav',
        game_descriptor => $descriptor,
        store_game_root => $descriptor,
        game_root       => $descriptor,
    };
}

sub _git_tree_context_for_arg {
    my ($game_arg) = @_;

    my $descriptor = basename($game_arg);
    _assert_descriptor($descriptor);
    my $store = store_from_env(mode => 'git-tree');

    return {
        store           => $store,
        store_kind      => 'git-tree',
        game_descriptor => $descriptor,
        store_game_root => $descriptor,
        game_root       => $descriptor,
    };
}

sub _dns_record_context_for_arg {
    my ($game_arg) = @_;

    my $descriptor = basename($game_arg);
    _assert_descriptor($descriptor);
    my $store = store_from_env(mode => 'dns-record');

    return {
        store           => $store,
        store_kind      => 'dns-record',
        game_descriptor => $descriptor,
        store_game_root => $descriptor,
        game_root       => $descriptor,
    };
}

sub _local_context_for_arg {
    my ($game_arg, %args) = @_;

    my $require_exists = exists($args{require_exists}) ? $args{require_exists} : 1;
    my $path_like = File::Spec->file_name_is_absolute($game_arg) || $game_arg =~ m{[\\/]};

    if (-d $game_arg || $path_like) {
        croak "game root does not exist: $game_arg" if !-e $game_arg;
        croak "game root is not a directory: $game_arg" if !-d $game_arg;

        my $game_root = File::Spec->rel2abs($game_arg);
        my $parent = dirname($game_root);
        my $descriptor = basename($game_root);
        my $store = GobanFTP::Store::Local->new(root => $parent);

        return {
            store           => $store,
            store_kind      => 'local',
            game_descriptor => $descriptor,
            store_game_root => $descriptor,
            game_root       => $game_root,
        };
    }

    my $descriptor = $game_arg;
    _assert_descriptor($descriptor);

    my $root_abs = _local_root_abs();
    my $game_root = File::Spec->catdir($root_abs, $descriptor);

    if ($require_exists) {
        croak "game root does not exist: $game_root" if !-e $game_root;
        croak "game root is not a directory: $game_root" if !-d $game_root;
    }

    return {
        store           => store_from_env(mode => 'local'),
        store_kind      => 'local',
        game_descriptor => $descriptor,
        store_game_root => $descriptor,
        game_root       => $game_root,
    };
}

sub _assert_descriptor {
    my ($descriptor) = @_;

    my (undef, $error) = parse_basename($descriptor);
    croak "invalid game descriptor: $error" if defined $error;

    return 1;
}

sub _local_root {
    my $root = $ENV{GOBANFTP_ROOT};
    return defined($root) && $root ne '' ? $root : '.';
}

sub _local_root_abs {
    my $root = _local_root();
    my $abs = abs_path($root);
    croak "root does not exist: $root" if !defined $abs;
    croak "root is not a directory: $root" if !-d $abs;
    return $abs;
}

sub _ftp_store_from_env {
    my $host = $ENV{GOBANFTP_FTP_HOST};
    croak 'GOBANFTP_FTP_HOST is required for GOBANFTP_STORE=ftp'
        if !defined($host) || $host eq '';

    my %args = (
        host => $host,
        root => $ENV{GOBANFTP_FTP_ROOT} // '',
    );

    for my $pair (
        [ GOBANFTP_FTP_USER         => 'user' ],
        [ GOBANFTP_FTP_PASSWORD     => 'password' ],
        [ GOBANFTP_FTP_PORT         => 'port' ],
        [ GOBANFTP_FTP_TIMEOUT      => 'timeout' ],
        [ GOBANFTP_FTP_CLASS        => 'ftp_class' ],
        [ GOBANFTP_FTP_PUBLISH_MODE => 'publish_mode' ],
    ) {
        my ($env, $arg) = @$pair;
        $args{$arg} = $ENV{$env} if defined($ENV{$env}) && $ENV{$env} ne '';
    }

    $args{passive} = _env_bool($ENV{GOBANFTP_FTP_PASSIVE})
        if defined $ENV{GOBANFTP_FTP_PASSIVE};
    $args{debug} = _env_bool($ENV{GOBANFTP_FTP_DEBUG})
        if defined $ENV{GOBANFTP_FTP_DEBUG};

    return GobanFTP::Store::FTP->new(%args);
}

sub _webdav_store_from_env {
    my $url = $ENV{GOBANFTP_WEBDAV_URL};
    croak 'GOBANFTP_WEBDAV_URL is required for GOBANFTP_STORE=webdav'
        if !defined($url) || $url eq '';

    my %args = (
        url => $url,
    );

    for my $pair (
        [ GOBANFTP_WEBDAV_USER         => 'user' ],
        [ GOBANFTP_WEBDAV_PASSWORD     => 'password' ],
        [ GOBANFTP_WEBDAV_TOKEN        => 'bearer_token' ],
        [ GOBANFTP_WEBDAV_TIMEOUT      => 'timeout' ],
        [ GOBANFTP_WEBDAV_CLASS        => 'client_class' ],
        [ GOBANFTP_WEBDAV_PUBLISH_MODE => 'publish_mode' ],
    ) {
        my ($env, $arg) = @$pair;
        $args{$arg} = $ENV{$env} if defined($ENV{$env}) && $ENV{$env} ne '';
    }

    $args{debug} = _env_bool($ENV{GOBANFTP_WEBDAV_DEBUG})
        if defined $ENV{GOBANFTP_WEBDAV_DEBUG};

    return GobanFTP::Store::WebDAV->new(%args);
}

sub _git_tree_store_from_env {
    my $repo = $ENV{GOBANFTP_GIT_REPO};
    croak 'GOBANFTP_GIT_REPO is required for GOBANFTP_STORE=git-tree'
        if !defined($repo) || $repo eq '';

    my %args = (
        repo => $repo,
    );

    $args{treeish} = $ENV{GOBANFTP_GIT_TREEISH}
        if defined($ENV{GOBANFTP_GIT_TREEISH}) && $ENV{GOBANFTP_GIT_TREEISH} ne '';
    $args{git} = $ENV{GOBANFTP_GIT_BINARY}
        if defined($ENV{GOBANFTP_GIT_BINARY}) && $ENV{GOBANFTP_GIT_BINARY} ne '';

    return GobanFTP::Store::GitTree->new(%args);
}

sub _dns_record_store_from_env {
    my $record_file = $ENV{GOBANFTP_DNS_RECORD_FILE};
    croak 'GOBANFTP_DNS_RECORD_FILE is required for GOBANFTP_STORE=dns-record'
        if !defined($record_file) || $record_file eq '';

    my %args = (
        record_file => $record_file,
    );

    $args{owner_suffix} = $ENV{GOBANFTP_DNS_OWNER_SUFFIX}
        if defined($ENV{GOBANFTP_DNS_OWNER_SUFFIX}) && $ENV{GOBANFTP_DNS_OWNER_SUFFIX} ne '';

    return GobanFTP::Store::DNSRecord->new(%args);
}

sub _env_bool {
    my ($value) = @_;
    return defined($value) && $value ne '' && $value ne '0' ? 1 : 0;
}

1;

__END__

=head1 NAME

GobanFTP::Store::Config - environment-backed store selection

=cut
