package GobanFTP::Showcase::StaticPreview;

use v5.34;
use strict;
use warnings;

use Carp qw(croak);
use Cwd qw(abs_path);
use Errno qw(EINTR);
use Exporter qw(import);
use Fcntl qw(O_RDONLY);
use File::Spec;
use IO::Select;
use IO::Socket::INET;
use JSON::PP qw(decode_json);
use POSIX qw(strftime);
use Time::HiRes qw(time);

our @EXPORT_OK = qw(
    expected_files
    load_static_bundle
    preview_static_bundle
    serve_static_bundle
);

use constant {
    HOST             => '127.0.0.1',
    MAX_HEADER_BYTES => 8192,
    MAX_REQUEST_LINE_BYTES => 1024,
    MAX_HEADER_LINE_BYTES  => 2048,
    REQUEST_TIMEOUT  => 5,
    MAX_FILE_BYTES   => 1_048_576,
};

my @EXPECTED_FILES = qw(
    index.html
    witness-clean.html
    witness-fork.html
    demo-transcript.txt
    release-evidence.txt
    roots.json
);

my %CONTENT_TYPE = (
    'index.html'           => 'text/html; charset=utf-8',
    'witness-clean.html'   => 'text/html; charset=utf-8',
    'witness-fork.html'    => 'text/html; charset=utf-8',
    'demo-transcript.txt'  => 'text/plain; charset=utf-8',
    'release-evidence.txt' => 'text/plain; charset=utf-8',
    'roots.json'           => 'application/json; charset=utf-8',
);

my %EXPECTED_CASE_ROOT = (
    clean => '599c00f0614e400274a92ab1c96d09087a53d0d88bd8b0ecba481ac60a1f1461',
    fork  => '02dac396696a1a3806d89819aadf672d02399426106b25bbbd4f36d9dd178b76',
);

my $CSP = join '; ',
    q(default-src 'none'),
    q(script-src 'none'),
    q(connect-src 'none'),
    q(img-src 'self'),
    q(style-src 'unsafe-inline'),
    q(font-src 'none'),
    q(base-uri 'none'),
    q(form-action 'none'),
    q(frame-ancestors 'none');

sub expected_files {
    return @EXPECTED_FILES;
}

sub load_static_bundle {
    my (%args) = @_;

    my $dir = $args{bundle_dir} // $args{dir};
    croak 'storage: preview dir is required' if !defined($dir) || $dir eq '';
    return _load_bundle($dir);
}

sub preview_static_bundle {
    return serve_static_bundle(@_);
}

sub serve_static_bundle {
    my (%args) = @_;

    my $server = __PACKAGE__->new(%args);
    if (my $ready = $args{on_ready} // $args{ready}) {
        croak 'storage: on_ready must be a code reference' if ref($ready) ne 'CODE';
        $ready->($server->info);
    }
    return $server->serve;
}

sub new {
    my ($class, %args) = @_;

    my $port = defined($args{port}) ? $args{port} : 0;
    croak 'storage: preview port is invalid' if $port !~ /\A(?:0|[1-9][0-9]{0,4})\z/ || $port > 65535;

    my $bundle = $args{bundle} ? _loaded_bundle($args{bundle}) : load_static_bundle(%args);
    my $socket = IO::Socket::INET->new(
        LocalAddr => HOST,
        LocalPort => $port,
        Listen    => 5,
        Proto     => 'tcp',
        ReuseAddr => 1,
    ) or croak "storage: bind " . HOST . ":$port: $!";
    $socket->autoflush(1);

    return bless {
        bundle       => $bundle,
        host         => HOST,
        port         => 0 + $socket->sockport,
        socket       => $socket,
        once         => $args{once} ? 1 : 0,
        max_requests => _optional_positive_int($args{max_requests}, 'max_requests'),
    }, $class;
}

sub host {
    my ($self) = @_;
    return $self->{host};
}

sub port {
    my ($self) = @_;
    return $self->{port};
}

sub url {
    my ($self) = @_;
    return 'http://' . $self->{host} . ':' . $self->{port} . '/';
}

sub info {
    my ($self) = @_;
    return {
        host  => $self->{host},
        port  => $self->{port},
        url   => $self->url,
        once  => $self->{once},
        files => [expected_files()],
    };
}

sub dir {
    my ($self) = @_;
    return $self->{bundle}{dir};
}

sub bundle {
    my ($self) = @_;
    return $self->{bundle};
}

sub files {
    return expected_files();
}

sub serve {
    my ($self) = @_;

    my $served = 0;
    while (1) {
        my $success = $self->serve_once_request;
        $served++;
        last if $self->{once} && $success;
        last if defined($self->{max_requests}) && $served >= $self->{max_requests};
    }

    return 1;
}

sub serve_once_request {
    my ($self) = @_;

    my $client;
    while (1) {
        $client = $self->{socket}->accept;
        last if $client;
        next if $! == EINTR;
        croak "storage: accept preview connection: $!";
    }

    $client->autoflush(1);
    my $success = eval { $self->_handle_client($client) };
    my $error = $@;
    CORE::close $client;
    die $error if $error;
    return $success ? 1 : 0;
}

sub close {
    my ($self) = @_;

    if (my $socket = delete $self->{socket}) {
        CORE::close $socket;
    }
    return 1;
}

sub DESTROY {
    my ($self) = @_;
    eval { $self->close; 1 };
    return;
}

sub _load_bundle {
    my ($dir) = @_;

    _reject_control_text($dir, 'dir');

    my $abs = File::Spec->rel2abs($dir);
    _assert_no_symlink_components($abs);

    my $resolved = abs_path($abs);
    croak "storage: preview dir does not exist: $dir" if !defined $resolved;
    croak "storage: preview dir is not a directory: $dir" if !-d $resolved;
    croak "storage: preview dir is a symlink: $dir" if -l $abs || -l $resolved;

    opendir my $dh, $resolved or croak "storage: opendir $resolved: $!";
    my @entries = sort grep { $_ ne '.' && $_ ne '..' } readdir $dh;
    closedir $dh or croak "storage: closedir $resolved: $!";

    my @expected = expected_files();
    _croak_bundle('unexpected file set') if join("\0", @entries) ne join("\0", sort @expected);

    my %content;
    for my $file (@expected) {
        _reject_control_text($file, 'file');
        _croak_bundle("invalid file name: $file") if $file =~ m{/|\\|\A[.][.]?\z};
        my $path = File::Spec->catfile($resolved, $file);
        _croak_bundle("non-regular file: $file") if !_is_regular_file_path($path);
        $content{$file} = _read_regular_file($path, $file);
    }

    _validate_roots_json($content{'roots.json'});
    _validate_static_html($content{'index.html'}, 'index.html');
    _validate_static_html($content{'witness-clean.html'}, 'witness-clean.html');
    _validate_static_html($content{'witness-fork.html'}, 'witness-fork.html');

    return {
        __static_preview_bundle => 1,
        dir     => $resolved,
        content => \%content,
    };
}

sub _loaded_bundle {
    my ($bundle) = @_;

    croak 'storage: preview bundle is invalid' if ref($bundle) ne 'HASH';
    croak 'storage: preview bundle is invalid' if ref($bundle->{content}) ne 'HASH';

    my @expected = expected_files();
    my @files = sort keys %{ $bundle->{content} };
    _croak_bundle('unexpected file set') if join("\0", @files) ne join("\0", sort @expected);
    for my $file (@expected) {
        _croak_bundle("invalid preloaded file: $file")
            if !defined($bundle->{content}{$file}) || ref($bundle->{content}{$file});
    }

    _validate_roots_json($bundle->{content}{'roots.json'});
    _validate_static_html($bundle->{content}{'index.html'}, 'index.html');
    _validate_static_html($bundle->{content}{'witness-clean.html'}, 'witness-clean.html');
    _validate_static_html($bundle->{content}{'witness-fork.html'}, 'witness-fork.html');

    return {
        dir     => $bundle->{dir} // '',
        content => { %{ $bundle->{content} } },
    };
}

sub _handle_client {
    my ($self, $client) = @_;

    my ($request, $too_large, $timeout) = _read_request($client);
    return _send_response($client, 408, 'Request Timeout', 'request timeout') if $timeout;
    return _send_response($client, 431, 'Request Header Fields Too Large', 'request too large') if $too_large;
    return _send_response($client, 400, 'Bad Request', 'bad request') if !defined $request;

    my ($method, $target, $version, $headers) = @$request;
    return _send_response($client, 405, 'Method Not Allowed', 'method not allowed', allow => 1)
        if $method ne 'GET' && $method ne 'HEAD';

    return _send_response($client, 400, 'Bad Request', 'bad host', method => $method)
        if $version ne 'HTTP/1.1';
    return _send_response($client, 400, 'Bad Request', 'bad host', method => $method)
        if !defined($headers->{host}) || $headers->{host} ne $self->{host} . ':' . $self->{port};
    return _send_response($client, 400, 'Bad Request', 'bad request', method => $method)
        if exists $headers->{'transfer-encoding'};
    if (exists $headers->{'content-length'} && $headers->{'content-length'} !~ /\A0+\z/) {
        return _send_response($client, 400, 'Bad Request', 'bad request', method => $method);
    }

    my $file = _target_file($target);
    return _send_response($client, 404, 'Not Found', 'not found', method => $method) if !defined $file;

    my $body = $self->{bundle}{content}{$file};
    return _send_response(
        $client,
        200,
        'OK',
        $body,
        method       => $method,
        content_type => $CONTENT_TYPE{$file},
    );
}

sub _read_request {
    my ($client) = @_;

    my $select = IO::Select->new($client);
    my $buffer = '';
    my $deadline = time + REQUEST_TIMEOUT;

    while (index($buffer, "\r\n\r\n") < 0) {
        my $remaining = $deadline - time;
        return (undef, 0, 1) if $remaining <= 0;
        return (undef, 0, 1) if !$select->can_read($remaining);

        my $chunk = '';
        my $read = sysread $client, $chunk, 1024;
        if (!defined($read) && $! == EINTR) {
            next;
        }
        return (undef, 0, 0) if !defined($read);
        last if $read == 0;

        $buffer .= $chunk;
        return (undef, 1, 0) if length($buffer) > MAX_HEADER_BYTES;
    }

    return (undef, 0, 0) if $buffer !~ /\A([^\r\n]*)\r\n(.*?)\r\n\r\n/s;
    my ($request_line, $header_text) = ($1, $2);
    return (undef, 0, 0) if $request_line =~ /[\x00-\x1f\x7f]/;
    return (undef, 1, 0) if length($request_line) > MAX_REQUEST_LINE_BYTES;

    my @request_parts = split / /, $request_line, -1;
    return (undef, 0, 0) if @request_parts != 3 || grep { $_ eq '' } @request_parts;
    my ($method, $target, $version) = @request_parts;
    return (undef, 0, 0) if $version ne 'HTTP/1.1';
    return (undef, 0, 0) if $method !~ /\A[A-Z]+\z/;

    my %headers;
    for my $line (split /\r\n/, $header_text) {
        next if $line eq '';
        return (undef, 1, 0) if length($line) > MAX_HEADER_LINE_BYTES;
        return (undef, 0, 0) if $line =~ /\A[ \t]/;
        return (undef, 0, 0) if $line =~ /[\x00-\x08\x0a-\x1f\x7f]/;
        return (undef, 0, 0) if $line !~ /\A([^:]+):[ \t]*(.*?)\s*\z/;
        my ($name, $value) = (lc($1), $2);
        return (undef, 0, 0) if $name !~ /\A[a-z0-9!#$%&'*+.^_`|~-]+\z/;
        return (undef, 0, 0) if $name eq 'host' && exists $headers{host};
        $headers{$name} = $value;
    }

    return ([$method, $target, $version, \%headers], 0, 0);
}

sub _target_file {
    my ($target) = @_;

    return undef if !defined($target) || $target eq '';
    return undef if $target =~ /[\x00-\x20\x7f\\%?#]/;
    return undef if $target =~ /\A[A-Za-z][A-Za-z0-9+.-]*:/;
    return undef if $target =~ m{\A//};
    return undef if $target =~ /\.\./;
    return 'index.html' if $target eq '/';
    return undef if $target !~ m{\A/([A-Za-z0-9_.-]+)\z};

    my $file = $1;
    my %allowed = map { $_ => 1 } expected_files();
    return $allowed{$file} ? $file : undef;
}

sub _send_response {
    my ($client, $code, $reason, $body, %opts) = @_;

    my $method = $opts{method} // 'GET';
    $body = '' if !defined $body;

    my @headers = (
        "HTTP/1.1 $code $reason",
        'Date: ' . strftime('%a, %d %b %Y %H:%M:%S GMT', gmtime()),
        'Connection: close',
        'Cache-Control: no-store',
        'Pragma: no-cache',
        'X-Content-Type-Options: nosniff',
        "Content-Security-Policy: $CSP",
        'Cross-Origin-Resource-Policy: same-origin',
    );
    push @headers, 'Allow: GET, HEAD' if $opts{allow};
    push @headers, 'Content-Type: ' . ($opts{content_type} // 'text/plain; charset=utf-8');
    push @headers, 'Content-Length: ' . length($body);
    push @headers, '', '';

    my $response = join("\r\n", @headers);
    $response .= $body if $method ne 'HEAD';
    _write_all($client, $response);

    return $code == 200 ? 1 : 0;
}

sub _write_all {
    my ($fh, $bytes) = @_;

    local $SIG{PIPE} = 'IGNORE';
    while (length $bytes) {
        my $written = syswrite($fh, $bytes);
        return 0 if !defined($written) || $written == 0;
        substr($bytes, 0, $written, '');
    }
    return 1;
}

sub _validate_roots_json {
    my ($text) = @_;

    my $doc = eval { decode_json($text) };
    _croak_bundle('roots.json is not valid JSON') if $@ || ref($doc) ne 'HASH';
    _croak_bundle('roots.json has wrong schema') if ($doc->{schema} // '') ne 'gobanftp.showcase.v1';
    _croak_bundle('roots.json has wrong version') if ($doc->{version} // '') ne '1.1';
    _croak_bundle('roots.json has wrong status') if ($doc->{status} // '') ne 'ok';
    _croak_bundle('roots.json has wrong boundary') if ($doc->{boundary} // '') ne 'static-fixture-only';

    _croak_bundle('roots.json files is not an array') if ref($doc->{files}) ne 'ARRAY';
    my @files = @{ $doc->{files} // [] };
    _croak_bundle('roots.json has wrong file list')
        if join("\0", @files) ne join("\0", expected_files());

    _croak_bundle('roots.json cases is not an array') if ref($doc->{cases}) ne 'ARRAY';
    _croak_bundle('roots.json must contain clean and fork cases') if @{ $doc->{cases} } != 2;
    my %case_by_id;
    for my $case (@{ $doc->{cases} // [] }) {
        _croak_bundle('roots.json case is not an object') if ref($case) ne 'HASH';
        my $id = $case->{id};
        _croak_bundle('roots.json case id must be clean or fork')
            if !defined($id) || ref($id) || ($id ne 'clean' && $id ne 'fork');
        _croak_bundle("roots.json duplicate case: $id") if $case_by_id{$id};
        _croak_bundle("roots.json case has invalid root: $id")
            if !defined($case->{event_set_root})
            || ref($case->{event_set_root})
            || $case->{event_set_root} !~ /\A[0-9a-f]{64}\z/;
        $case_by_id{$id} = $case;
    }
    _croak_bundle('roots.json missing case: clean') if !$case_by_id{clean};
    _croak_bundle('roots.json missing case: fork') if !$case_by_id{fork};
    for my $id (sort keys %EXPECTED_CASE_ROOT) {
        _croak_bundle("roots.json has wrong root for case: $id")
            if ($case_by_id{$id}{event_set_root} // '') ne $EXPECTED_CASE_ROOT{$id};
    }

    return 1;
}

sub _validate_static_html {
    my ($html, $file) = @_;

    my @forbidden = (
        ['script tag',        qr/<script\b/i],
        ['event handler attr', qr/\bon[a-z]+\s*=/i],
        ['javascript/data URL', qr/\b(?:href|src|srcset|action)\s*=\s*["']?\s*(?:javascript|data):/i],
        ['fetch API',         qr/\bfetch\s*\(/i],
        ['WebSocket API',     qr/\bWebSocket\b/],
        ['EventSource API',   qr/\bEventSource\b/],
        ['XMLHttpRequest API', qr/\bXMLHttpRequest\b/],
        ['worker API',        qr/\b(?:Worker|SharedWorker|ServiceWorker|navigator[.]serviceWorker)\b/],
        ['CSS url loader',    qr/\burl\s*\(/i],
        ['resource loader tag', qr/<(?:iframe|object|embed|link|img|audio|video|source|track)\b/i],
        ['form/input/button', qr/<(?:form|input|button)\b/i],
        ['meta refresh',      qr/<meta\b[^>]*\bhttp-equiv\s*=\s*["']?refresh/i],
        ['remote http URL',   qr{http://}i],
        ['remote https URL',  qr{https://}i],
        ['protocol-relative URL', qr{(?<!:)//}],
    );

    for my $case (@forbidden) {
        my ($label, $pattern) = @$case;
        _croak_bundle("$file contains $label") if $html =~ /$pattern/;
    }

    return 1;
}

sub _is_regular_file_path {
    my ($path) = @_;

    return 0 if !lstat($path);
    return 0 if -l _;
    return -f _;
}

sub _read_regular_file {
    my ($path, $file) = @_;

    my @before = lstat($path);
    _croak_bundle("non-regular file: $file") if !@before || -l _ || !-f _;

    my $flags = O_RDONLY | _o_nofollow();
    sysopen my $fh, $path, $flags or croak "storage: open $path: $!";
    binmode $fh;

    my @opened = stat($fh);
    _croak_bundle("non-regular file: $file") if !@opened || !-f $fh;
    _croak_bundle("file changed while opening: $file")
        if $before[0] != $opened[0] || $before[1] != $opened[1];
    _croak_bundle("file too large: $file") if $opened[7] > MAX_FILE_BYTES;

    my $text = '';
    while (1) {
        my $chunk = '';
        my $read = sysread $fh, $chunk, 65536;
        croak "storage: read $path: $!" if !defined $read;
        last if $read == 0;
        $text .= $chunk;
        _croak_bundle("file too large: $file") if length($text) > MAX_FILE_BYTES;
    }
    CORE::close $fh or croak "storage: close $path: $!";

    return $text;
}

sub _assert_no_symlink_components {
    my ($path) = @_;

    my $abs = File::Spec->rel2abs($path);
    my $current = File::Spec->rootdir;
    for my $component (grep { $_ ne '' } split m{/+}, $abs) {
        $current = File::Spec->catdir($current, $component);
        croak "storage: path component is a symlink: $current" if -l $current;
        croak "storage: path component does not exist: $current" if !-e $current;
    }

    return 1;
}

sub _reject_control_text {
    my ($text, $field) = @_;

    croak "storage: $field contains control character" if defined($text) && $text =~ /[\x00-\x1f\x7f]/;
    return 1;
}

sub _croak_bundle {
    my ($message) = @_;
    croak 'storage: showcase preview bundle is not clean: ' . ($message // 'invalid bundle');
}

sub _o_nofollow {
    state $flag = eval { Fcntl::O_NOFOLLOW() };
    croak 'storage: O_NOFOLLOW is required for showcase preview' if !defined $flag;
    return $flag;
}

sub _optional_positive_int {
    my ($value, $name) = @_;

    return undef if !defined $value;
    croak "storage: $name must be a positive integer"
        if ref($value) || $value !~ /\A[1-9][0-9]*\z/;
    return 0 + $value;
}

1;

__END__

=head1 NAME

GobanFTP::Showcase::StaticPreview - loopback-only showcase preview helper

=head1 INTERNAL INTERFACE

=over 4

=item expected_files()

Returns the fixed six-file static showcase allowlist.

=item load_static_bundle(bundle_dir => $dir)

Admits a generated showcase bundle, validates C<roots.json> and static HTML
boundaries, opens every file with C<O_NOFOLLOW>, verifies regular files after
open, and preloads the bundle into memory.

=item GobanFTP::Showcase::StaticPreview->new(bundle_dir => $dir, port => 0, once => 0)

Creates a blocking loopback preview server bound only to C<127.0.0.1>.
Useful methods are C<host>, C<port>, C<url>, C<info>, C<serve>,
C<serve_once_request>, and C<close>.

=item serve_static_bundle(%args)

Convenience wrapper for C<new(...)->serve>. C<preview_static_bundle> is an
alias for callers that want the CLI-facing name.

=back

=cut
