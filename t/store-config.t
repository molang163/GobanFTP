use v5.34;
use strict;
use warnings;

use FindBin;
use File::Spec;
use File::Temp qw(tempdir);
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::Store::Config qw(
    context_for_game_arg
    doctor_report
    store_capabilities
    store_config_summary
    store_from_env
);

subtest 'local path game roots must still be valid game descriptors' => sub {
    my $root = tempdir(CLEANUP => 1);
    local $ENV{GOBANFTP_STORE};
    local $ENV{GOBANFTP_ROOT};
    delete @ENV{qw(GOBANFTP_STORE GOBANFTP_ROOT)};

    my $valid = 'g1.id-local-path.s9.r-chinese-area-v1.k7500.pb-alice.pw-bob';
    my $valid_path = File::Spec->catdir($root, $valid);
    mkdir $valid_path or die "mkdir $valid_path: $!";

    my $context = context_for_game_arg($valid_path);
    is $context->{game_descriptor}, $valid, 'valid path basename is accepted';
    is $context->{store_game_root}, $valid, 'store root remains descriptor basename';
    is $context->{game_root}, File::Spec->rel2abs($valid_path), 'game root remains the absolute local path';

    my $invalid_path = File::Spec->catdir($root, 'not-a-game');
    mkdir $invalid_path or die "mkdir $invalid_path: $!";

    like exception(sub { context_for_game_arg($invalid_path) }),
        qr/invalid game descriptor:/,
        'invalid path basename is rejected before replay or auth material can use it';
};

subtest 'local descriptors are validated even when existence is optional' => sub {
    local $ENV{GOBANFTP_STORE};
    local $ENV{GOBANFTP_ROOT};
    delete @ENV{qw(GOBANFTP_STORE GOBANFTP_ROOT)};

    like exception(sub { context_for_game_arg('not-a-game', require_exists => 0) }),
        qr/invalid game descriptor:/,
        'invalid bare descriptor is rejected before optional existence checks';
};

subtest 'WebDAV credentials from the environment require HTTPS' => sub {
    local @ENV{qw(
        GOBANFTP_STORE
        GOBANFTP_WEBDAV_URL
        GOBANFTP_WEBDAV_USER
        GOBANFTP_WEBDAV_PASSWORD
        GOBANFTP_WEBDAV_TOKEN
        GOBANFTP_WEBDAV_TIMEOUT
        GOBANFTP_WEBDAV_CLASS
        GOBANFTP_WEBDAV_PUBLISH_MODE
        GOBANFTP_WEBDAV_DEBUG
    )};

    $ENV{GOBANFTP_STORE} = 'webdav';
    $ENV{GOBANFTP_WEBDAV_URL} = 'http://dav.example.test/goftp';
    delete @ENV{qw(GOBANFTP_WEBDAV_USER GOBANFTP_WEBDAV_PASSWORD GOBANFTP_WEBDAV_TOKEN)};

    ok store_from_env(), 'unauthenticated HTTP WebDAV can still be configured for cleartext fixtures';

    $ENV{GOBANFTP_WEBDAV_USER} = 'alice';
    $ENV{GOBANFTP_WEBDAV_PASSWORD} = 'secret';
    like exception(sub { store_from_env() }),
        qr/webdav credentials require https url/,
        'Basic credentials from environment are rejected over HTTP';

    delete @ENV{qw(GOBANFTP_WEBDAV_USER GOBANFTP_WEBDAV_PASSWORD)};
    $ENV{GOBANFTP_WEBDAV_TOKEN} = 'secret-token';
    like exception(sub { store_from_env() }),
        qr/webdav credentials require https url/,
        'Bearer token from environment is rejected over HTTP';

    $ENV{GOBANFTP_WEBDAV_URL} = 'https://dav.example.test/goftp';
    ok store_from_env(), 'Bearer token from environment is accepted over HTTPS';
};

subtest 'network timeout environment values reach mock clients' => sub {
    local @ENV{qw(
        GOBANFTP_STORE
        GOBANFTP_FTP_HOST
        GOBANFTP_FTP_TIMEOUT
        GOBANFTP_FTP_CLASS
        GOBANFTP_WEBDAV_URL
        GOBANFTP_WEBDAV_TIMEOUT
        GOBANFTP_WEBDAV_CLASS
    )};

    delete @ENV{qw(
        GOBANFTP_STORE
        GOBANFTP_FTP_HOST
        GOBANFTP_FTP_TIMEOUT
        GOBANFTP_FTP_CLASS
        GOBANFTP_WEBDAV_URL
        GOBANFTP_WEBDAV_TIMEOUT
        GOBANFTP_WEBDAV_CLASS
    )};

    $ENV{GOBANFTP_STORE} = 'ftp';
    $ENV{GOBANFTP_FTP_HOST} = 'ftp.example.test';
    $ENV{GOBANFTP_FTP_TIMEOUT} = '7';
    $ENV{GOBANFTP_FTP_CLASS} = 'StoreConfigMockFTP';
    $StoreConfigMockFTP::LAST_TIMEOUT = undef;
    ok store_from_env(), 'FTP mock store can be created from env';
    is $StoreConfigMockFTP::LAST_TIMEOUT, '7', 'FTP timeout is passed to the client constructor';

    $ENV{GOBANFTP_STORE} = 'webdav';
    $ENV{GOBANFTP_WEBDAV_URL} = 'https://dav.example.test/goftp';
    $ENV{GOBANFTP_WEBDAV_TIMEOUT} = '9';
    $ENV{GOBANFTP_WEBDAV_CLASS} = 'StoreConfigMockWebDAV';
    $StoreConfigMockWebDAV::LAST_TIMEOUT = undef;
    ok store_from_env(), 'WebDAV mock store can be created from env';
    is $StoreConfigMockWebDAV::LAST_TIMEOUT, '9', 'WebDAV timeout is passed to the client constructor';
};

subtest 'store capabilities describe read/write and network boundaries' => sub {
    is_deeply store_capabilities('local'), {
        store_mode       => 'local',
        can_read_events  => 1,
        can_publish      => 1,
        can_mkdir        => 1,
        read_only        => 0,
        network_required => 0,
        projection_write => 1,
    }, 'local store can publish and write projections';

    is store_capabilities('ftp')->{network_required}, 1, 'FTP is a network substrate';
    is store_capabilities('webdav')->{network_required}, 1, 'WebDAV is a network substrate';
    is store_capabilities('git-tree')->{read_only}, 1, 'Git tree runtime substrate is read-only';
    is store_capabilities('dns-record')->{can_publish}, 0, 'DNS record substrate cannot publish';
};

subtest 'config summary redacts secrets without constructing a network store' => sub {
    local @ENV{qw(
        GOBANFTP_STORE
        GOBANFTP_FTP_HOST
        GOBANFTP_FTP_USER
        GOBANFTP_FTP_PASSWORD
        GOBANFTP_FTP_CLASS
    )};

    $ENV{GOBANFTP_STORE} = 'ftp';
    $ENV{GOBANFTP_FTP_HOST} = 'ftp.example.test';
    $ENV{GOBANFTP_FTP_USER} = 'alice';
    $ENV{GOBANFTP_FTP_PASSWORD} = 'secret-password';
    $ENV{GOBANFTP_FTP_CLASS} = 'NoSuchFTPClassForSummary';
    $StoreConfigMockFTP::LAST_TIMEOUT = 'sentinel';

    my $summary = store_config_summary();
    is $summary->{schema}, 'gobanftp.config.show.v1', 'config summary has scoped schema';
    is $summary->{store_mode}, 'ftp', 'config summary reports selected mode';
    is_deeply $summary->{missing_required_env}, [], 'required FTP env is present';
    my %env = map { $_->{name} => $_ } @{ $summary->{env} };
    is $env{GOBANFTP_FTP_PASSWORD}{value}, 'REDACTED', 'FTP password is redacted';
    is $env{GOBANFTP_FTP_HOST}{value}, 'ftp.example.test', 'non-secret env value remains visible';
    is $StoreConfigMockFTP::LAST_TIMEOUT, 'sentinel', 'summary did not instantiate the configured FTP class';
};

subtest 'config summary redacts URL userinfo secrets' => sub {
    my @cases = (
        {
            label  => 'https webdav password',
            mode   => 'webdav',
            env    => 'GOBANFTP_WEBDAV_URL',
            value  => 'https://alice:top-secret@webdav.example.test/path',
            leaks  => [qw(alice: alice top-secret alice:top-secret)],
        },
        {
            label  => 'http webdav password',
            mode   => 'webdav',
            env    => 'GOBANFTP_WEBDAV_URL',
            value  => 'http://alice:top-secret@webdav.example.test/path',
            leaks  => [qw(alice: alice top-secret alice:top-secret)],
        },
        {
            label  => 'webdav username-only userinfo',
            mode   => 'webdav',
            env    => 'GOBANFTP_WEBDAV_URL',
            value  => 'https://alice@webdav.example.test/path',
            leaks  => [qw(alice@ alice)],
        },
        {
            label  => 'webdav percent-encoded userinfo',
            mode   => 'webdav',
            env    => 'GOBANFTP_WEBDAV_URL',
            value  => 'https://alice%3AURL%2DSECRET@webdav.example.test/path',
            leaks  => [qw(alice%3A URL%2DSECRET alice%3AURL%2DSECRET alice URL-SECRET)],
        },
        {
            label  => 'git remote password',
            mode   => 'git-tree',
            env    => 'GOBANFTP_GIT_REPO',
            value  => 'https://git-user:git-secret@example.test/repo.git',
            leaks  => [qw(git-user: git-user git-secret git-user:git-secret)],
        },
        {
            label  => 'git remote token',
            mode   => 'git-tree',
            env    => 'GOBANFTP_GIT_REPO',
            value  => 'https://token-value@example.test/repo.git',
            leaks  => [qw(token-value token-value@)],
        },
    );

    for my $case (@cases) {
        my ($label, $mode, $env_name, $value, $leaks) =
            @{$case}{qw(label mode env value leaks)};
        local %ENV = ();
        $ENV{GOBANFTP_STORE} = $mode;
        $ENV{$env_name} = $value;

        my $summary = store_config_summary();
        my %env = map { $_->{name} => $_ } @{ $summary->{env} };
        ok exists($env{$env_name}), "$label: selected URL env is summarized";
        _assert_redacted_url_userinfo($env{$env_name}{value} // '', $label, @$leaks);
        like $env{$env_name}{value} // '', qr{://REDACTED\@},
            "$label: redacted URL marks hidden userinfo";
    }
};

subtest 'invalid URL-shaped store mode reports stable safe model fields' => sub {
    local %ENV = ();
    $ENV{GOBANFTP_STORE} = 'https://alice:URL-SECRET@host/path';

    my $summary = store_config_summary();
    is $summary->{schema}, 'gobanftp.config.show.v1', 'config summary has scoped schema';
    is $summary->{version}, '1.1', 'config summary pins version';
    is $summary->{status}, 'failed', 'config summary reports failed status';
    is $summary->{diagnostics}[0]{code}, 'invalid_store_mode',
        'config summary reports stable invalid-store code';
    _assert_tree_has_no_invalid_store_leaks($summary, 'config summary');

    my $report = doctor_report();
    is $report->{schema}, 'gobanftp.doctor.v1', 'doctor report has scoped schema';
    is $report->{version}, '1.1', 'doctor report pins version';
    is $report->{status}, 'failed', 'doctor report reports failed status';
    is $report->{diagnostics}[0]{code}, 'invalid_store_mode',
        'doctor report reports stable invalid-store diagnostic code';
    is $report->{checks}[0]{name}, 'store.mode', 'doctor first check is store.mode';
    is $report->{checks}[0]{status}, 'failed', 'doctor store.mode check fails';
    is $report->{checks}[0]{code}, 'invalid_store_mode',
        'doctor store.mode check reports stable invalid-store code';
    _assert_tree_has_no_invalid_store_leaks($report, 'doctor report');
};

subtest 'doctor is dry-run by default and reports missing required env' => sub {
    local @ENV{qw(GOBANFTP_STORE GOBANFTP_WEBDAV_URL GOBANFTP_WEBDAV_CLASS)};

    $ENV{GOBANFTP_STORE} = 'webdav';
    delete @ENV{qw(GOBANFTP_WEBDAV_URL GOBANFTP_WEBDAV_CLASS)};

    my $report = doctor_report();
    is $report->{schema}, 'gobanftp.doctor.v1', 'doctor report has scoped schema';
    is $report->{status}, 'failed', 'doctor fails when required env is missing';
    is $report->{dry_run}, 1, 'doctor defaults to dry-run';
    is_deeply $report->{missing_required_env}, ['GOBANFTP_WEBDAV_URL'], 'doctor names missing env';
    is $report->{capabilities}{network_required}, 1, 'doctor still reports capabilities';
};

done_testing;

sub exception {
    my ($code) = @_;

    my $error;
    eval { $code->(); 1 } or $error = $@;

    return $error;
}

sub _assert_redacted_url_userinfo {
    my ($text, $label, @leaks) = @_;

    like $text, qr{://REDACTED\@}, "$label: URL userinfo redaction marker is present";
    unlike $text, qr{://(?!REDACTED\@)[^/?#\s"'=]+\@},
        "$label: no unredacted URL userinfo remains";
    for my $leak (@leaks) {
        unlike $text, qr/\Q$leak\E/i, "$label: value does not leak $leak";
    }
}

sub _assert_tree_has_no_invalid_store_leaks {
    my ($value, $label) = @_;

    if (ref($value) eq 'HASH') {
        _assert_tree_has_no_invalid_store_leaks($value->{$_}, "$label.$_") for sort keys %$value;
        return;
    }
    if (ref($value) eq 'ARRAY') {
        for my $idx (0 .. $#$value) {
            _assert_tree_has_no_invalid_store_leaks($value->[$idx], "$label\[$idx]");
        }
        return;
    }
    return if ref($value) || !defined($value);

    unlike $value, qr/URL-SECRET/i, "$label does not leak URL secret";
    unlike $value, qr/alice:/i, "$label does not leak username delimiter";
    unlike $value, qr/alice:URL-SECRET\@/i, "$label does not leak complete userinfo";
    unlike $value, qr{https://alice:URL-SECRET\@host/path}i,
        "$label does not leak full invalid store URL";
    unlike $value, qr/internal:/, "$label does not expose internal failure prefix";
    unlike $value, qr/GOBANFTP_STORE must be| at \S+ line [0-9]+/,
        "$label does not expose Perl croak text or stack";
}

package StoreConfigMockFTP;

use v5.34;
use strict;
use warnings;

our $LAST_TIMEOUT;

sub new {
    my ($class, undef, %args) = @_;
    $LAST_TIMEOUT = $args{Timeout};
    return bless {}, $class;
}

sub login { return 1 }

package StoreConfigMockWebDAV;

use v5.34;
use strict;
use warnings;

our $LAST_TIMEOUT;

sub new {
    my ($class, %args) = @_;
    $LAST_TIMEOUT = $args{timeout};
    return bless {}, $class;
}
