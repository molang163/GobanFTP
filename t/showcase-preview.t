use v5.34;
use strict;
use warnings;

use Config qw(%Config);
use FindBin;
use Digest::SHA qw(sha256_hex);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use IO::Socket::INET;
use POSIX ();
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::CLI;
use GobanFTP::Showcase::StaticPreview qw(expected_files unsupported_reason);

if (defined(my $unsupported = unsupported_reason())) {
    plan skip_all => "showcase preview unsupported on this platform: $unsupported";
}

my $HAS_FORK = _fork_available();
my $WNOHANG = eval { POSIX::WNOHANG() };
$WNOHANG = 1 if !defined $WNOHANG;

my $lib = File::Spec->catdir($FindBin::Bin, '..', 'lib');
my $script = File::Spec->catfile($FindBin::Bin, '..', 'script', 'gobanftp');

subtest 'preview validates generated showcase bundle' => sub {
    my ($out) = _generated_showcase();
    my $preview = GobanFTP::Showcase::StaticPreview->new(dir => $out, port => 0, once => 1);

    is $preview->host, '127.0.0.1', 'preview binds loopback literal';
    ok $preview->port > 0, 'preview reports actual random port';
    is $preview->url, 'http://127.0.0.1:' . $preview->port . '/', 'preview URL uses loopback literal';
    is_deeply [$preview->files], [expected_files()], 'preview uses fixed showcase file list';
};

subtest 'preview rejects non-showcase and tampered bundles' => sub {
    my ($out) = _generated_showcase();
    my $root = tempdir(CLEANUP => 1);

    my $extra = File::Spec->catdir($root, 'extra');
    _copy_dir($out, $extra);
    _write_text(File::Spec->catfile($extra, 'old.js'), "stale\n");
    like _new_error($extra), qr/not clean/, 'extra file is rejected';

    my $missing = File::Spec->catdir($root, 'missing');
    _copy_dir($out, $missing);
    unlink File::Spec->catfile($missing, 'roots.json') or die "unlink roots.json: $!";
    like _new_error($missing), qr/not clean/, 'missing expected file is rejected';

    my $dir_entry = File::Spec->catdir($root, 'dir-entry');
    _copy_dir($out, $dir_entry);
    unlink File::Spec->catfile($dir_entry, 'index.html') or die "unlink index.html: $!";
    mkdir File::Spec->catdir($dir_entry, 'index.html') or die "mkdir index.html: $!";
    like _new_error($dir_entry), qr/not clean/, 'expected-name directory is rejected';

    my $tampered_roots = File::Spec->catdir($root, 'tampered-roots');
    _copy_dir($out, $tampered_roots);
    my $roots = _slurp(File::Spec->catfile($tampered_roots, 'roots.json'));
    $roots =~ s/"boundary":"static-fixture-only"/"boundary":"hosted"/;
    _write_text(File::Spec->catfile($tampered_roots, 'roots.json'), $roots);
    like _new_error($tampered_roots), qr/not clean/, 'tampered roots.json is rejected';

    my $tampered_root_hash = File::Spec->catdir($root, 'tampered-root-hash');
    _copy_dir($out, $tampered_root_hash);
    my $root_hash_json = _slurp(File::Spec->catfile($tampered_root_hash, 'roots.json'));
    $root_hash_json =~ s/"event_set_root":"599c00f0614e400274a92ab1c96d09087a53d0d88bd8b0ecba481ac60a1f1461"/"event_set_root":"0000000000000000000000000000000000000000000000000000000000000000"/
        or die 'generated roots.json did not contain expected clean root';
    _write_text(File::Spec->catfile($tampered_root_hash, 'roots.json'), $root_hash_json);
    like _new_error($tampered_root_hash), qr/not clean/, 'tampered case root is rejected';

    my $tampered_html = File::Spec->catdir($root, 'tampered-html');
    _copy_dir($out, $tampered_html);
    _append_text(File::Spec->catfile($tampered_html, 'index.html'), "<script>alert(1)</script>\n");
    like _new_error($tampered_html), qr/not clean/, 'script-bearing HTML is rejected';

    subtest 'expected-name symlink is rejected' => sub {
        my $link_case = File::Spec->catdir($root, 'symlink');
        _copy_dir($out, $link_case);
        my $outside = File::Spec->catfile($root, 'outside-index.html');
        _write_text($outside, "outside sentinel\n");
        unlink File::Spec->catfile($link_case, 'index.html') or die "unlink index.html: $!";
        if (!eval { symlink $outside, File::Spec->catfile($link_case, 'index.html') }) {
            plan skip_all => 'symlink unavailable on this platform';
        }
        like _new_error($link_case), qr/symlink|not clean/, 'expected-name symlink is rejected';
        is _slurp($outside), "outside sentinel\n", 'outside symlink target is unchanged';
    };
};

subtest 'preview serves allowed GET and exits after --once without mutating read-only manifest' => sub {
    _skip_without_fork();

    my ($out) = _generated_showcase();
    my $roots_path = File::Spec->catfile($out, 'roots.json');
    chmod 0444, $roots_path or die "chmod roots.json read-only: $!";
    my $before = _manifest($out);
    my $process = _start_preview($out);

    my $response = _http_request($process->{port}, _request('GET', '/', $process->{port}));
    like $response, qr{\AHTTP/1[.]1 200 OK\r\n}, 'GET / succeeds';
    like $response, qr{\r\nX-Content-Type-Options: nosniff\r\n}, 'nosniff header is present';
    like $response, qr{\r\nCache-Control: no-store\r\n}, 'no-store header is present';
    like $response, qr{\r\nContent-Security-Policy: [^\r\n]*script-src 'none'}, 'CSP disables scripts';
    like $response, qr{<!doctype html>\n<html lang="en" data-boundary="static-fixture-only">},
        'GET / returns generated index HTML';
    unlike $response, qr{Access-Control-Allow-Origin}i, 'response does not enable CORS';

    _wait_preview($process);
    like $process->{stdout}, qr/^gobanftp[.]showcase[.]preview=ok$/m, 'ready output reports ok';
    like $process->{stdout}, qr/^boundary=localhost-static-preview-only$/m, 'ready output reports preview boundary';
    like $process->{stdout}, qr/^remote_access=0$/m, 'ready output reports no remote access';
    like $process->{stdout}, qr/^hosted_web_ui=0$/m, 'ready output reports no hosted UI claim';
    is _manifest($out), $before, 'GET preview leaves bundle unchanged';
    is((lstat($roots_path))[2] & 07777, 0444, 'read-only roots manifest mode is unchanged');
    chmod 0644, $roots_path or die "restore roots.json mode: $!";
};

subtest 'preview serves HEAD without a body' => sub {
    _skip_without_fork();

    my ($out) = _generated_showcase();
    my $process = _start_preview($out);
    my $response = _http_request($process->{port}, _request('HEAD', '/roots.json', $process->{port}));

    like $response, qr{\AHTTP/1[.]1 200 OK\r\n}, 'HEAD succeeds';
    like $response, qr{\r\nContent-Type: application/json; charset=utf-8\r\n}, 'HEAD reports JSON type';
    unlike $response, qr/\r\n\r\n\{/, 'HEAD returns no body';

    _wait_preview($process);
};

subtest 'preview rejects methods, hosts, and paths without consuming --once' => sub {
    _skip_without_fork();

    for my $case (
        ['POST is rejected',     _request('POST', '/', 0),                      qr/\AHTTP\/1[.]1 405 Method Not Allowed/],
        ['bad Host is rejected', "GET / HTTP/1.1\r\nHost: evil.test:PORT\r\nConnection: close\r\n\r\n", qr/\AHTTP\/1[.]1 400 Bad Request/],
        ['duplicate Host rejected', "GET / HTTP/1.1\r\nHost: 127.0.0.1:PORT\r\nHost: 127.0.0.1:PORT\r\nConnection: close\r\n\r\n", qr/\AHTTP\/1[.]1 400 Bad Request/],
        ['traversal is rejected', _request('GET', '/../secret', 0),             qr/\AHTTP\/1[.]1 404 Not Found/],
        ['encoded traversal rejected', _request('GET', '/%2e%2e/secret', 0),    qr/\AHTTP\/1[.]1 404 Not Found/],
        ['query trick rejected', _request('GET', '/index.html?x=1', 0),         qr/\AHTTP\/1[.]1 404 Not Found/],
        ['absolute URI rejected', "GET http://127.0.0.1:PORT/index.html HTTP/1.1\r\nHost: 127.0.0.1:PORT\r\nConnection: close\r\n\r\n", qr/\AHTTP\/1[.]1 404 Not Found/],
    ) {
        my ($label, $request, $pattern) = @$case;
        my ($out) = _generated_showcase();
        my $before = _manifest($out);
        my $process = _start_preview($out);
        $request =~ s/PORT/$process->{port}/g;
        $request =~ s/Host: 127[.]0[.]0[.]1:0/Host: 127.0.0.1:$process->{port}/g;

        my $rejected = _http_request($process->{port}, $request);
        like $rejected, $pattern, $label;
        is _manifest($out), $before, "$label leaves bundle unchanged";

        my $ok = _http_request($process->{port}, _request('GET', '/index.html', $process->{port}));
        like $ok, qr{\AHTTP/1[.]1 200 OK\r\n}, "$label did not consume --once";
        _wait_preview($process);
    }
};

subtest 'preview long-running mode stays foreground and terminates cleanly' => sub {
    _skip_without_fork();

    my ($out) = _generated_showcase();
    my $process = _start_preview($out, once => 0);
    my $response = _http_request($process->{port}, _request('GET', '/release-evidence.txt', $process->{port}));

    like $response, qr{\AHTTP/1[.]1 200 OK\r\n}, 'foreground preview serves a request';
    ok _process_running($process->{pid}), 'foreground preview remains running after a request';
    _terminate_preview($process);
    ok !_process_running($process->{pid}), 'foreground preview terminates on TERM';
};

subtest 'preview CLI rejects JSON mode' => sub {
    my ($out) = _generated_showcase();
    my ($exit, $stdout, $stderr) = _run_cli('showcase', 'preview', '--dir', $out, '--json');

    is $exit, 1, 'preview --json exits usage';
    is $stdout, '', 'preview --json writes no stdout';
    like $stderr, qr/^usage:/m, 'preview --json reports usage';

    my ($host_exit, $host_stdout, $host_stderr) = _run_cli('showcase', 'preview', '--dir', $out, '--host', '0.0.0.0');
    is $host_exit, 1, 'preview --host exits usage';
    is $host_stdout, '', 'preview --host writes no stdout';
    like $host_stderr, qr/^usage:/m, 'preview --host reports usage';
};

done_testing;

sub _generated_showcase {
    my $root = tempdir(CLEANUP => 1);
    my $out = File::Spec->catdir($root, 'showcase');
    my ($exit, $stdout, $stderr) = _run_cli('showcase', '--out', $out);
    die "showcase failed: exit=$exit stdout=$stdout stderr=$stderr" if $exit != 0;
    return ($out, $root);
}

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

sub _start_preview {
    my ($out, %opts) = @_;

    my $run_root = tempdir(CLEANUP => 1);
    my $stdout_path = File::Spec->catfile($run_root, 'preview.stdout');
    my $stderr_path = File::Spec->catfile($run_root, 'preview.stderr');

    my @cmd = (
        $^X, '-I', $lib, $script,
        'showcase', 'preview',
        '--dir', $out,
        '--port', '0',
    );
    push @cmd, '--once' if $opts{once} // 1;

    my $pid = fork();
    die "fork unavailable for showcase preview process tests: $!" if !defined $pid;
    if ($pid == 0) {
        open STDOUT, '>', $stdout_path or die "open preview stdout: $!";
        open STDERR, '>', $stderr_path or die "open preview stderr: $!";
        if (!exec @cmd) {
            print STDERR "exec preview failed: $!\n";
            exit 127;
        }
    }

    my $port;
    my $deadline = time + 10;
    while (time < $deadline) {
        if (waitpid($pid, $WNOHANG) == $pid) {
            die "preview exited before ready; stdout="
                . _slurp_maybe($stdout_path)
                . " stderr="
                . _slurp_maybe($stderr_path);
        }
        my $stdout = _slurp_maybe($stdout_path);
        $port = 0 + $1 if !defined($port) && $stdout =~ /^port=([0-9]+)$/m;
        last if defined($port) && _can_connect($port);
        select undef, undef, undef, 0.1;
    }
    die "preview did not accept connections; stdout="
        . _slurp_maybe($stdout_path)
        . " stderr="
        . _slurp_maybe($stderr_path)
        if !defined($port) || !_can_connect($port);

    return {
        pid         => $pid,
        stdout_path => $stdout_path,
        stderr_path => $stderr_path,
        stdout      => _slurp_maybe($stdout_path),
        stderr      => _slurp_maybe($stderr_path),
        port        => $port,
    };
}

sub _http_request {
    my ($port, $request) = @_;

    my $socket = IO::Socket::INET->new(
        PeerAddr => '127.0.0.1',
        PeerPort => $port,
        Proto    => 'tcp',
        Timeout  => 5,
    ) or die "connect preview port $port: $!";
    print {$socket} $request;
    shutdown $socket, 1;

    my $response = '';
    while (1) {
        my $chunk = '';
        my $read = sysread $socket, $chunk, 4096;
        die "read response: $!" if !defined $read;
        last if $read == 0;
        $response .= $chunk;
    }
    close $socket or die "close preview socket: $!";

    return $response;
}

sub _request {
    my ($method, $target, $port) = @_;
    return "$method $target HTTP/1.1\r\nHost: 127.0.0.1:$port\r\nConnection: close\r\n\r\n";
}

sub _wait_preview {
    my ($process) = @_;

    for (1 .. 50) {
        my $done = waitpid($process->{pid}, $WNOHANG);
        if ($done == $process->{pid}) {
            $process->{stdout} = _slurp_maybe($process->{stdout_path});
            $process->{stderr} = _slurp_maybe($process->{stderr_path});
            return 1;
        }
        select undef, undef, undef, 0.1;
    }

    _terminate_preview($process);
    die "preview did not exit after --once";
}

sub _terminate_preview {
    my ($process) = @_;

    return if !_process_running($process->{pid});
    kill 'TERM', $process->{pid};
    for (1 .. 30) {
        my $done = waitpid($process->{pid}, $WNOHANG);
        if ($done == $process->{pid}) {
            $process->{stdout} = _slurp_maybe($process->{stdout_path});
            $process->{stderr} = _slurp_maybe($process->{stderr_path});
            return;
        }
        select undef, undef, undef, 0.1;
    }
    kill 'KILL', $process->{pid};
    waitpid($process->{pid}, 0);
}

sub _process_running {
    my ($pid) = @_;
    return kill(0, $pid) ? 1 : 0;
}

sub _skip_without_fork {
    plan skip_all => 'fork unavailable on this platform; preview CLI process tests skipped'
        if !$HAS_FORK;
    return;
}

sub _fork_available {
    return 0 if ($Config{d_fork} // '') ne 'define';

    my $pid = fork();
    return 0 if !defined $pid;
    if ($pid == 0) {
        eval { POSIX::_exit(0) };
        exit 0;
    }
    waitpid($pid, 0);
    return 1;
}

sub _can_connect {
    my ($port) = @_;

    my $socket = IO::Socket::INET->new(
        PeerAddr => '127.0.0.1',
        PeerPort => $port,
        Proto    => 'tcp',
        Timeout  => 1,
    );
    return 0 if !$socket;
    close $socket;
    return 1;
}

sub _new_error {
    my ($dir) = @_;

    my $error;
    local $@;
    eval {
        my $preview = GobanFTP::Showcase::StaticPreview->new(dir => $dir, port => 0, once => 1);
        undef $preview;
        1;
    } or $error = $@;
    return $error // '';
}

sub _manifest {
    my ($dir) = @_;

    my @rows;
    for my $file (expected_files()) {
        my $path = File::Spec->catfile($dir, $file);
        my @st = lstat($path);
        push @rows, join "\t", $file, @st[2, 7, 9], sha256_hex(_slurp($path));
    }
    return join "\n", @rows, '';
}

sub _copy_dir {
    my ($src, $dst) = @_;

    make_path($dst);
    for my $file (expected_files()) {
        _write_text(File::Spec->catfile($dst, $file), _slurp(File::Spec->catfile($src, $file)));
    }
}

sub _slurp {
    my ($path) = @_;

    open my $fh, '<', $path or die "open $path: $!";
    binmode $fh;
    my $text = do { local $/; <$fh> };
    close $fh or die "close $path: $!";
    return $text // '';
}

sub _slurp_maybe {
    my ($path) = @_;
    return '' if !defined($path) || !-e $path;
    return _slurp($path);
}

sub _write_text {
    my ($path, $text) = @_;

    open my $fh, '>', $path or die "write $path: $!";
    binmode $fh;
    print {$fh} $text;
    close $fh or die "close $path: $!";
}

sub _append_text {
    my ($path, $text) = @_;

    open my $fh, '>>', $path or die "append $path: $!";
    binmode $fh;
    print {$fh} $text;
    close $fh or die "close $path: $!";
}
