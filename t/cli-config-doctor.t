use v5.34;
use strict;
use warnings;

use FindBin;
use JSON::PP qw(decode_json);
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::CLI;

subtest '--version and help expose P1 commands for the v1.1.0-beta.1 package' => sub {
    my ($version_exit, $version_stdout, $version_stderr) = _run_cli('--version');
    is $version_exit, 0, '--version exits success';
    is $version_stdout, "gobanftp 1.100_001\n", '--version reports the package version';
    is $version_stderr, '', '--version has no diagnostics';

    my ($help_exit, $help_stdout, $help_stderr) = _run_cli('--help');
    is $help_exit, 0, '--help exits success';
    like $help_stdout, qr/^  config show \[--json\]$/m, 'help lists config show';
    like $help_stdout, qr/^  doctor \[--json\] \[--connect\]$/m, 'help lists doctor';
    like $help_stdout, qr/^  showcase --out dir \[--json\]$/m, 'help lists showcase';
    like $help_stdout, qr/^  watch \[--live\] \[--compact\]/m, 'help lists compact watch';
    is $help_stderr, '', '--help has no diagnostics';
};

subtest 'config show --json reports capabilities and redacts secrets' => sub {
    local %ENV = ();
    $ENV{GOBANFTP_STORE} = 'ftp';
    $ENV{GOBANFTP_FTP_HOST} = 'ftp.example.test';
    $ENV{GOBANFTP_FTP_PASSWORD} = 'top-secret';

    my ($exit, $stdout, $stderr) = _run_cli('config', 'show', '--json');
    is $exit, 0, 'config show exits success';
    is $stderr, '', 'config show has no diagnostics';
    my $doc = decode_json($stdout);

    is $doc->{schema}, 'gobanftp.config.show.v1', 'config JSON has scoped schema';
    is $doc->{version}, '1.1', 'config JSON has version 1.1';
    is $doc->{store_mode}, 'ftp', 'config JSON reports selected store';
    is $doc->{capabilities}{network_required}, 1, 'config JSON reports network boundary';
    is_deeply $doc->{missing_required_env}, [], 'config JSON reports complete required env';
    my %env = map { $_->{name} => $_ } @{ $doc->{env} };
    is $env{GOBANFTP_FTP_PASSWORD}{value}, 'REDACTED', 'config JSON redacts password';
    unlike $stdout, qr/top-secret/, 'secret does not appear in JSON stdout';
};

subtest 'config show redacts URL userinfo in JSON and plain output' => sub {
    my @cases = (
        {
            label  => 'https webdav basic userinfo',
            mode   => 'webdav',
            env    => 'GOBANFTP_WEBDAV_URL',
            value  => 'https://alice:top-secret@webdav.example.test/path',
            leaks  => [qw(alice: alice top-secret alice:top-secret)],
        },
        {
            label  => 'http webdav basic userinfo',
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
            label  => 'git remote basic userinfo',
            mode   => 'git-tree',
            env    => 'GOBANFTP_GIT_REPO',
            value  => 'https://git-user:git-secret@example.test/repo.git',
            leaks  => [qw(git-user: git-user git-secret git-user:git-secret)],
        },
        {
            label  => 'git remote token userinfo',
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

        my ($json_exit, $json_stdout, $json_stderr) = _run_cli('config', 'show', '--json');
        is $json_exit, 0, "$label: JSON config exits success";
        is $json_stderr, '', "$label: JSON config has no diagnostics";
        _assert_redacted_url_userinfo($json_stdout . $json_stderr, $label, 'JSON output', @$leaks);

        my $doc = _decode_json_or_fail($json_stdout, "$label: JSON config");
        my %env = map { $_->{name} => $_ } @{ $doc->{env} // [] };
        ok exists($env{$env_name}), "$label: JSON includes selected env row";
        _assert_redacted_url_userinfo($env{$env_name}{value} // '', $label, 'JSON env value', @$leaks);
        like $env{$env_name}{value} // '', qr{://REDACTED\@},
            "$label: JSON env value marks redaction";

        my ($plain_exit, $plain_stdout, $plain_stderr) = _run_cli('config', 'show');
        is $plain_exit, 0, "$label: plain config exits success";
        is $plain_stderr, '', "$label: plain config has no diagnostics";
        _assert_redacted_url_userinfo($plain_stdout . $plain_stderr, $label, 'plain output', @$leaks);
        like $plain_stdout, qr/^env[.]\Q$env_name\E[.]value=.*:\/\/REDACTED\@/m,
            "$label: plain env value marks redaction";
    }
};

subtest 'config show keeps key/value output compatible' => sub {
    local %ENV = ();

    my ($exit, $stdout, $stderr) = _run_cli('config', 'show');
    is $exit, 0, 'plain config show exits success';
    like $stdout, qr/^gobanftp\.config\.show=ok$/m, 'plain config show prints status';
    like $stdout, qr/^capability\.can_publish=1$/m, 'plain config show prints capability lines';
    is $stderr, '', 'plain config show has no diagnostics';
};

subtest 'plain config output escapes control characters without forged lines' => sub {
    local %ENV = ();
    $ENV{GOBANFTP_STORE} = 'local';
    $ENV{GOBANFTP_ROOT} = "alpha\nforged.independent=1\rbravo\tcharlie";

    my ($exit, $stdout, $stderr) = _run_cli('config', 'show');
    is $exit, 0, 'plain config show exits success with control-bearing env';
    is $stderr, '', 'plain config show has no diagnostics';
    like $stdout, qr/^env[.]GOBANFTP_ROOT[.]value=alpha\\nforged[.]independent=1\\rbravo\\tcharlie$/m,
        'plain env value escapes newline, carriage return, and tab';
    unlike $stdout, qr/^forged[.]independent=1$/m, 'embedded newline cannot forge an independent key/value line';
    unlike $stdout, qr/\r/, 'plain output contains no raw carriage return';
    unlike $stdout, qr/\t/, 'plain output contains no raw tab';
};

subtest 'doctor --json is dry-run by default and fails missing required env' => sub {
    local %ENV = ();
    $ENV{GOBANFTP_STORE} = 'webdav';

    my ($exit, $stdout, $stderr) = _run_cli('doctor', '--json');
    is $exit, 2, 'doctor exits validation when required env is missing';
    is $stderr, '', 'doctor reports missing env on stdout JSON';
    my $doc = decode_json($stdout);

    is $doc->{schema}, 'gobanftp.doctor.v1', 'doctor JSON has scoped schema';
    is $doc->{version}, '1.1', 'doctor JSON has version 1.1';
    is $doc->{status}, 'failed', 'doctor JSON status is failed';
    is $doc->{dry_run}, 1, 'doctor does not connect by default';
    is_deeply $doc->{missing_required_env}, ['GOBANFTP_WEBDAV_URL'], 'doctor names missing env';
};

subtest 'invalid GOBANFTP_STORE is validation JSON, not an internal croak' => sub {
    my $invalid = 'https://alice:URL-SECRET@host/path';
    my @json_cases = (
        {
            label  => 'config show --json',
            args   => ['config', 'show', '--json'],
            schema => 'gobanftp.config.show.v1',
        },
        {
            label  => 'doctor --json',
            args   => ['doctor', '--json'],
            schema => 'gobanftp.doctor.v1',
        },
    );

    for my $case (@json_cases) {
        local %ENV = ();
        $ENV{GOBANFTP_STORE} = $invalid;

        my ($exit, $stdout, $stderr) = _run_cli(@{ $case->{args} });
        is $exit, 2, "$case->{label}: invalid store is validation failure";
        is $stderr, '', "$case->{label}: JSON diagnostics stay on stdout";
        _assert_invalid_store_output_is_safe($stdout, $stderr, "$case->{label}: JSON output");

        my $doc = _decode_json_or_fail($stdout, "$case->{label}: invalid store JSON");
        is $doc->{schema}, $case->{schema}, "$case->{label}: JSON has scoped schema";
        is $doc->{version}, '1.1', "$case->{label}: JSON pins version";
        is $doc->{status}, 'failed', "$case->{label}: JSON reports failed status";
        is $doc->{diagnostics}[0]{code}, 'invalid_store_mode',
            "$case->{label}: JSON reports stable invalid store code";
        _assert_doc_has_no_invalid_store_leaks($doc, "$case->{label}: parsed JSON");
    }

    for my $case (
        ['config show', 'config', 'show'],
        ['doctor', 'doctor'],
    ) {
        local %ENV = ();
        $ENV{GOBANFTP_STORE} = $invalid;

        my ($exit, $stdout, $stderr) = _run_cli(@$case[1 .. $#$case]);
        is $exit, 2, "$case->[0]: invalid store is validation failure";
        is $stderr, '', "$case->[0]: plain validation stays on stdout";
        _assert_invalid_store_output_is_safe($stdout, $stderr, "$case->[0]: plain output");

        my %kv = _parse_kv($stdout);
        is $kv{schema}, $case->[0] eq 'config show' ? 'gobanftp.config.show.v1' : 'gobanftp.doctor.v1',
            "$case->[0]: plain output pins schema";
        is $kv{version}, '1.1', "$case->[0]: plain output pins version";
        if ($case->[0] eq 'config show') {
            is $kv{'gobanftp.config.show'}, 'failed', 'plain config reports failed status';
            is $kv{'diagnostic.invalid_store_mode'}, 'failed',
                'plain config reports stable invalid-store diagnostic';
        }
        else {
            is $kv{'gobanftp.doctor'}, 'failed', 'plain doctor reports failed status';
            is $kv{'check.store.mode'}, 'failed', 'plain doctor reports failed store-mode check';
            is $kv{'check.store.mode.code'}, 'invalid_store_mode',
                'plain doctor reports stable invalid-store check code';
            is $kv{'diagnostic.invalid_store_mode'}, 'failed',
                'plain doctor reports stable invalid-store diagnostic';
        }
    }
};

done_testing;

sub _run_cli {
    my (@args) = @_;

    my ($stdout, $stderr) = ('', '');
    open my $out_fh, '>', \$stdout or die "open stdout scalar: $!";
    open my $err_fh, '>', \$stderr or die "open stderr scalar: $!";

    my $exit;
    {
        local *STDOUT = $out_fh;
        local *STDERR = $err_fh;
        $exit = GobanFTP::CLI->run(@args);
    }

    return ($exit, $stdout, $stderr);
}

sub _decode_json_or_fail {
    my ($text, $label) = @_;

    my $doc = eval { decode_json($text) };
    if ($@) {
        fail "$label decodes JSON";
        diag "decode error: $@";
        diag "stdout was: $text";
        return {};
    }

    pass "$label decodes JSON";
    return $doc;
}

sub _parse_kv {
    my ($text) = @_;

    my %kv;
    for my $line (split /\n/, $text // '') {
        next if $line eq '';
        my ($key, $value) = split /=/, $line, 2;
        fail "plain output line has key=value shape: $line" if !defined($value);
        $kv{$key} = $value;
    }

    return %kv;
}

sub _assert_redacted_url_userinfo {
    my ($text, $label, $where, @leaks) = @_;

    like $text, qr{://REDACTED\@}, "$label: $where uses URL userinfo redaction marker";
    unlike $text, qr{://(?!REDACTED\@)[^/?#\s"'=]+\@},
        "$label: $where has no unredacted URL userinfo";
    for my $leak (@leaks) {
        unlike $text, qr/\Q$leak\E/i, "$label: $where does not leak $leak";
    }
}

sub _assert_invalid_store_output_is_safe {
    my ($stdout, $stderr, $label) = @_;

    my $combined = ($stdout // '') . ($stderr // '');
    unlike $combined, qr/URL-SECRET/i, "$label does not leak URL secret";
    unlike $combined, qr/alice:/i, "$label does not leak username delimiter";
    unlike $combined, qr/alice:URL-SECRET\@/i, "$label does not leak complete userinfo";
    unlike $combined, qr{https://alice:URL-SECRET\@host/path}i,
        "$label does not leak full invalid store URL";
    unlike $combined, qr/internal:/, "$label does not expose internal failure prefix";
    unlike $combined, qr/GOBANFTP_STORE must be| at \S+ line [0-9]+/,
        "$label does not expose Perl croak text or stack";
}

sub _assert_doc_has_no_invalid_store_leaks {
    my ($value, $label) = @_;

    if (ref($value) eq 'HASH') {
        _assert_doc_has_no_invalid_store_leaks($value->{$_}, "$label.$_") for sort keys %$value;
        return;
    }
    if (ref($value) eq 'ARRAY') {
        for my $idx (0 .. $#$value) {
            _assert_doc_has_no_invalid_store_leaks($value->[$idx], "$label\[$idx]");
        }
        return;
    }
    return if ref($value) || !defined($value);

    _assert_invalid_store_output_is_safe($value, '', $label);
}
