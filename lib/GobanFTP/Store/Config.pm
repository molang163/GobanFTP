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
use GobanFTP::Redact qw(redact_text);
use GobanFTP::Store::DNSRecord;
use GobanFTP::Store::FTP;
use GobanFTP::Store::GitTree;
use GobanFTP::Store::Local;
use GobanFTP::Store::WebDAV;

our @EXPORT_OK = qw(
    context_for_descriptor
    context_for_game_arg
    doctor_report
    store_capabilities
    store_config_summary
    store_from_env
    store_mode
);

my @VALID_STORE_MODES = qw(local ftp git-tree dns-record webdav);
my %VALID_STORE_MODE = map { $_ => 1 } @VALID_STORE_MODES;

sub store_mode {
    my $mode = lc($ENV{GOBANFTP_STORE} // 'local');
    $mode = 'local' if $mode eq '';

    return _normalize_store_mode($mode);
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

sub store_capabilities {
    my ($mode) = @_;

    $mode = _normalize_store_mode($mode // store_mode());
    return _capabilities_for_mode($mode);
}

sub store_config_summary {
    my (%args) = @_;

    my ($mode, $diagnostic) = _report_store_mode($args{mode}, exists $args{mode});
    my @diagnostics = defined($diagnostic) ? ($diagnostic) : ();
    my @missing = defined($diagnostic) ? () : _missing_required_env($mode);
    my %requested = defined($diagnostic) && defined($diagnostic->{requested_store_mode})
        ? (requested_store_mode => $diagnostic->{requested_store_mode})
        : ();

    return {
        schema               => 'gobanftp.config.show.v1',
        version              => '1.1',
        status               => @diagnostics ? 'failed' : 'ok',
        store_mode           => $mode,
        %requested,
        capabilities         => _capabilities_for_report($mode),
        env                  => _env_summary($mode),
        missing_required_env => \@missing,
        diagnostics          => \@diagnostics,
    };
}

sub doctor_report {
    my (%args) = @_;

    my ($mode, $diagnostic) = _report_store_mode($args{mode}, exists $args{mode});
    my $connect = $args{connect} ? 1 : 0;
    my @diagnostics = defined($diagnostic) ? ($diagnostic) : ();
    my @missing = defined($diagnostic) ? () : _missing_required_env($mode);
    my %requested = defined($diagnostic) && defined($diagnostic->{requested_store_mode})
        ? (requested_store_mode => $diagnostic->{requested_store_mode})
        : ();
    my @checks = (
        {
            name   => 'store.mode',
            status => defined($diagnostic) ? 'failed' : 'ok',
            detail => $mode,
            defined($diagnostic) ? (code => $diagnostic->{code}) : (),
        },
        {
            name   => 'store.required_env',
            status => defined($diagnostic) ? 'skipped' : @missing ? 'failed' : 'ok',
            detail => defined($diagnostic) ? $diagnostic->{code} : join(',', @missing),
        },
        {
            name   => 'doctor.connect',
            status => $connect && !defined($diagnostic) ? 'requested' : 'skipped',
            detail => defined($diagnostic) ? $diagnostic->{code} : $connect ? 'explicit' : 'dry-run',
        },
    );

    if (!defined($diagnostic) && $mode eq 'local') {
        my $root = _local_root();
        push @checks, {
            name   => 'local.root',
            status => -d $root ? 'ok' : 'failed',
            detail => $root,
        };
    }

    if ($connect && !@missing && !defined($diagnostic)) {
        my $connected = eval { store_from_env(mode => $mode); 1 };
        push @checks, {
            name   => 'store.connect',
            status => $connected ? 'ok' : 'failed',
            detail => $connected ? '' : _clean_error($@),
        };
    }

    my $status = grep({ $_->{status} eq 'failed' } @checks) ? 'failed' : 'ok';

    return {
        schema               => 'gobanftp.doctor.v1',
        version              => '1.1',
        status               => $status,
        dry_run              => $connect ? 0 : 1,
        connect_requested    => $connect,
        store_mode           => $mode,
        %requested,
        capabilities         => _capabilities_for_report($mode),
        missing_required_env => \@missing,
        diagnostics          => \@diagnostics,
        checks               => \@checks,
    };
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
        _assert_descriptor($descriptor);
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

sub _normalize_store_mode {
    my ($mode) = @_;

    $mode = _store_mode_value($mode);

    croak 'GOBANFTP_STORE must be local, ftp, git-tree, dns-record, or webdav'
        if !$VALID_STORE_MODE{$mode};

    return $mode;
}

sub _report_store_mode {
    my ($mode, $has_mode_arg) = @_;

    my $requested = $has_mode_arg && defined($mode) ? $mode : $ENV{GOBANFTP_STORE};
    $mode = _store_mode_value($requested);
    return ($mode, undef) if $VALID_STORE_MODE{$mode};

    return ('invalid', _invalid_store_mode_diagnostic($requested));
}

sub _store_mode_value {
    my ($mode) = @_;

    $mode = lc($mode // 'local');
    $mode = 'local' if $mode eq '';
    return $mode;
}

sub _invalid_store_mode_diagnostic {
    my ($requested) = @_;

    return {
        code                 => 'invalid_store_mode',
        class                => 'config',
        field                => 'GOBANFTP_STORE',
        value                => 'invalid',
        requested_store_mode => _redacted_store_mode($requested),
        message              => 'unsupported store mode',
    };
}

sub _redacted_store_mode {
    my ($mode) = @_;

    return _public_redacted_text($mode);
}

sub _capabilities_for_mode {
    my ($mode) = @_;

    my %capability = (
        local => {
            can_read_events  => 1,
            can_publish      => 1,
            can_mkdir        => 1,
            read_only        => 0,
            network_required => 0,
            projection_write => 1,
        },
        ftp => {
            can_read_events  => 1,
            can_publish      => 1,
            can_mkdir        => 1,
            read_only        => 0,
            network_required => 1,
            projection_write => 0,
        },
        webdav => {
            can_read_events  => 1,
            can_publish      => 1,
            can_mkdir        => 1,
            read_only        => 0,
            network_required => 1,
            projection_write => 0,
        },
        'git-tree' => {
            can_read_events  => 1,
            can_publish      => 0,
            can_mkdir        => 0,
            read_only        => 1,
            network_required => 0,
            projection_write => 0,
        },
        'dns-record' => {
            can_read_events  => 1,
            can_publish      => 0,
            can_mkdir        => 0,
            read_only        => 1,
            network_required => 0,
            projection_write => 0,
        },
    );

    return undef if !$VALID_STORE_MODE{$mode};
    return {
        store_mode => $mode,
        %{ $capability{$mode} },
    };
}

sub _capabilities_for_report {
    my ($mode) = @_;

    return _capabilities_for_mode($mode) if $VALID_STORE_MODE{$mode};
    return {
        store_mode       => $mode,
        can_read_events  => 0,
        can_publish      => 0,
        can_mkdir        => 0,
        read_only        => 0,
        network_required => 0,
        projection_write => 0,
    };
}

sub _missing_required_env {
    my ($mode) = @_;

    my %required = (
        local        => [],
        ftp          => [qw(GOBANFTP_FTP_HOST)],
        webdav       => [qw(GOBANFTP_WEBDAV_URL)],
        'git-tree'   => [qw(GOBANFTP_GIT_REPO)],
        'dns-record' => [qw(GOBANFTP_DNS_RECORD_FILE)],
    );

    return grep { !defined($ENV{$_}) || $ENV{$_} eq '' } @{ $required{$mode} // [] };
}

sub _env_summary {
    my ($mode) = @_;

    my @keys = (
        qw(GOBANFTP_STORE GOBANFTP_ROOT),
        qw(GOBANFTP_FTP_HOST GOBANFTP_FTP_ROOT GOBANFTP_FTP_USER GOBANFTP_FTP_PASSWORD GOBANFTP_FTP_PORT GOBANFTP_FTP_TIMEOUT GOBANFTP_FTP_PASSIVE GOBANFTP_FTP_DEBUG GOBANFTP_FTP_CLASS GOBANFTP_FTP_PUBLISH_MODE),
        qw(GOBANFTP_WEBDAV_URL GOBANFTP_WEBDAV_USER GOBANFTP_WEBDAV_PASSWORD GOBANFTP_WEBDAV_TOKEN GOBANFTP_WEBDAV_TIMEOUT GOBANFTP_WEBDAV_DEBUG GOBANFTP_WEBDAV_CLASS GOBANFTP_WEBDAV_PUBLISH_MODE),
        qw(GOBANFTP_GIT_REPO GOBANFTP_GIT_TREEISH GOBANFTP_GIT_BINARY),
        qw(GOBANFTP_DNS_RECORD_FILE GOBANFTP_DNS_OWNER_SUFFIX),
        qw(GOBANFTP_PUBLISH_AUTH_TOKEN GOBANFTP_PUBLISH_AUTH_PROFILE GOBANFTP_PUBLISH_AUTH_KEY),
    );

    my %selected = map { $_ => 1 } _env_keys_for_mode($mode);
    my @rows;
    for my $key (@keys) {
        next if !$selected{$key} && !defined $ENV{$key};
        push @rows, {
            name     => $key,
            selected => $selected{$key} ? 1 : 0,
            set      => defined($ENV{$key}) && $ENV{$key} ne '' ? 1 : 0,
            value    => _redacted_env_value($key, $ENV{$key}),
        };
    }

    return \@rows;
}

sub _env_keys_for_mode {
    my ($mode) = @_;

    return qw(GOBANFTP_STORE GOBANFTP_ROOT) if $mode eq 'local';
    return qw(GOBANFTP_STORE GOBANFTP_FTP_HOST GOBANFTP_FTP_ROOT GOBANFTP_FTP_USER GOBANFTP_FTP_PASSWORD GOBANFTP_FTP_PORT GOBANFTP_FTP_TIMEOUT GOBANFTP_FTP_PASSIVE GOBANFTP_FTP_DEBUG GOBANFTP_FTP_CLASS GOBANFTP_FTP_PUBLISH_MODE)
        if $mode eq 'ftp';
    return qw(GOBANFTP_STORE GOBANFTP_WEBDAV_URL GOBANFTP_WEBDAV_USER GOBANFTP_WEBDAV_PASSWORD GOBANFTP_WEBDAV_TOKEN GOBANFTP_WEBDAV_TIMEOUT GOBANFTP_WEBDAV_DEBUG GOBANFTP_WEBDAV_CLASS GOBANFTP_WEBDAV_PUBLISH_MODE)
        if $mode eq 'webdav';
    return qw(GOBANFTP_STORE GOBANFTP_GIT_REPO GOBANFTP_GIT_TREEISH GOBANFTP_GIT_BINARY)
        if $mode eq 'git-tree';
    return qw(GOBANFTP_STORE GOBANFTP_DNS_RECORD_FILE GOBANFTP_DNS_OWNER_SUFFIX)
        if $mode eq 'dns-record';
    return qw(GOBANFTP_STORE);
}

sub _redacted_env_value {
    my ($key, $value) = @_;

    return undef if !defined($value) || $value eq '';
    return 'REDACTED'
        if $key =~ /(?:PASSWORD|TOKEN|SECRET|PRIVATE|PUBLISH_AUTH_KEY)\z/;
    return _public_redacted_text($value);
}

sub _clean_error {
    my ($error) = @_;

    return '' if !defined $error;
    chomp $error;
    $error =~ s/\s+/ /g;
    $error =~ s/\A\s+|\s+\z//g;
    return _public_redacted_text($error);
}

sub _public_redacted_text {
    my ($value) = @_;

    my $redacted = redact_text($value // '');
    $redacted =~ s{://\[REDACTED\]\@}{://REDACTED@}g;
    return $redacted;
}

1;

__END__

=head1 NAME

GobanFTP::Store::Config - environment-backed store selection

=cut
