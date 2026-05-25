package GobanFTP::Store::WebDAV;

use v5.34;
use strict;
use warnings;

use parent 'GobanFTP::Store';

use Carp qw(croak);
use HTTP::Tiny ();
use MIME::Base64 qw(encode_base64);

use constant {
    DEFAULT_MAX_RESPONSE_BYTES => 1_048_576,
    DEFAULT_MAX_HREF_COUNT     => 10_000,
};

sub new {
    my ($class, %args) = @_;

    my $client = delete $args{client};
    my $url = delete($args{url}) // delete($args{root_url});
    croak 'url is required' if !defined($url) || $url eq '';

    my $publish_mode = delete($args{publish_mode}) // 'move';
    my $publish_confirm_attempts = delete($args{publish_confirm_attempts}) // 3;
    my $publish_move_attempts    = delete($args{publish_move_attempts})    // 2;
    my $publish_confirm_delay    = delete($args{publish_confirm_delay})    // 0;
    my $max_response_bytes       = delete($args{max_response_bytes})       // DEFAULT_MAX_RESPONSE_BYTES;
    my $max_href_count           = delete($args{max_href_count})           // DEFAULT_MAX_HREF_COUNT;

    croak 'publish_mode must be move or mkcol'
        if $publish_mode ne 'move' && $publish_mode ne 'mkcol';
    $publish_confirm_attempts = _positive_int_option('publish_confirm_attempts', $publish_confirm_attempts);
    $publish_move_attempts    = _positive_int_option('publish_move_attempts',    $publish_move_attempts);
    $publish_confirm_delay    = _nonnegative_number_option('publish_confirm_delay', $publish_confirm_delay);
    $max_response_bytes       = _positive_int_option('max_response_bytes', $max_response_bytes);
    $max_href_count           = _positive_int_option('max_href_count', $max_href_count);

    my ($root_url, @root_segments) = _root_url($url);

    my $user = delete $args{user};
    my $password = delete $args{password};
    my $bearer_token = delete($args{bearer_token}) // delete($args{token});
    croak 'bearer token cannot be combined with user/password'
        if defined($bearer_token) && (defined($user) || defined($password));
    croak 'password requires user' if defined($password) && !defined($user);

    my %auth_headers;
    if (defined $bearer_token) {
        croak 'bearer token is required' if $bearer_token eq '';
        $auth_headers{Authorization} = "Bearer $bearer_token";
    }
    elsif (defined $user) {
        $password //= '';
        $auth_headers{Authorization} = 'Basic ' . encode_base64("$user:$password", '');
    }
    croak 'webdav credentials require https url'
        if %auth_headers && $root_url =~ m{\Ahttp://}i;

    if (!defined $client) {
        my $client_class = delete($args{client_class}) // 'HTTP::Tiny';
        _load_class($client_class);

        my %client_args;
        $client_args{timeout} = delete $args{timeout} if exists $args{timeout};
        $client_args{agent}   = delete $args{agent}   if exists $args{agent};

        $client = $client_class->new(%client_args);
    }
    else {
        delete $args{timeout};
        delete $args{agent};
        delete $args{client_class};
    }

    delete $args{debug};
    croak 'unknown Store::WebDAV option(s): ' . join(', ', sort keys %args) if %args;

    return bless {
        client         => $client,
        root_url       => $root_url,
        root_segments  => \@root_segments,
        auth_headers   => \%auth_headers,
        publish_mode   => $publish_mode,
        publish_confirm_attempts => $publish_confirm_attempts,
        publish_move_attempts    => $publish_move_attempts,
        publish_confirm_delay    => $publish_confirm_delay,
        max_response_bytes       => $max_response_bytes,
        max_href_count           => $max_href_count,
    }, $class;
}

sub list_names {
    my ($self, $relative_path) = @_;

    my @path = _path_components($relative_path);
    my $path_label = join '/', @path;
    my $response = $self->_request(
        'PROPFIND',
        $self->_collection_url(@path),
        headers => {
            Depth        => '1',
            'Content-Type' => 'application/xml; charset=utf-8',
        },
        content => _propfind_body(),
    );
    $self->_croak_response("propfind $path_label", $response)
        if !$self->_response_success($response) || ($response->{status} // 0) != 207;

    my $content = $response->{content} // '';
    croak "propfind $path_label failed: response too large"
        if length($content) > $self->{max_response_bytes};

    my @collection = (@{ $self->{root_segments} }, @path);
    my %seen;
    my @names = grep { !$seen{$_}++ }
        grep { defined && $_ ne '' }
        map { _direct_href_child($_, \@collection) }
            _hrefs_from_multistatus($content, $self->{max_href_count});

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

    if ($self->{publish_mode} eq 'mkcol') {
        return $self->mkdir(join '/', @game_components, 'events', $event_component);
    }

    $self->mkdir($events_path);
    $self->mkdir(join '/', @game_components, 'tmp');

    return 1 if $self->exists_name($events_path, $event_component);

    my $tmp_component = _tmp_component_for_event($event_component);
    my @tmp_path = (@game_components, 'tmp', $tmp_component);
    my @target_path = (@game_components, 'events', $event_component);
    my $tmp_label = join '/', @tmp_path;
    my $target_label = join '/', @target_path;

    my $put = $self->_request(
        'PUT',
        $self->_resource_url(@tmp_path),
        headers => { 'Content-Length' => '0' },
        content => '',
    );
    $self->_croak_response("put $tmp_label", $put) if !$self->_response_success($put);

    my ($last_move_response, $last_confirm_error);
    for my $attempt (1 .. $self->{publish_move_attempts}) {
        my $move = $self->_request(
            'MOVE',
            $self->_resource_url(@tmp_path),
            headers => {
                Destination => $self->_resource_url(@target_path),
                Overwrite   => 'F',
            },
        );

        if ($self->_response_success($move)) {
            my ($confirmed, $confirm_error)
                = $self->_confirm_event_visible($events_path, $event_component);
            return 1 if $confirmed;
            $self->_croak_confirm_failed($target_label, $confirm_error);
        }

        $last_move_response = $move;
        my ($confirmed, $confirm_error)
            = $self->_confirm_event_visible($events_path, $event_component);
        return 1 if $confirmed;
        $last_confirm_error = $confirm_error if defined $confirm_error && $confirm_error ne '';
    }

    $self->_croak_move_failed($tmp_label, $target_label, $last_move_response, $last_confirm_error);
}

sub mkdir {
    my ($self, $path) = @_;

    my @components = _path_components($path);
    return 1 if !@components;

    my @prefix;
    for my $component (@components) {
        my $parent = join '/', @prefix;
        push @prefix, $component;

        my $response = $self->_request('MKCOL', $self->_collection_url(@prefix));
        next if $self->_response_success($response);
        next if ($response->{status} // 0) == 405 && $self->exists_name($parent, $component);
        next if $self->exists_name($parent, $component);

        $self->_croak_response('mkcol ' . join('/', @prefix), $response);
    }

    return 1;
}

sub exists_name {
    my ($self, $path, $name) = @_;

    croak 'name is required' if !defined($name) || $name eq '';

    my $component = _name_component($name);
    return (grep { $_ eq $component } $self->list_names($path)) ? 1 : 0;
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

sub _request {
    my ($self, $method, $url, %opts) = @_;

    my %headers = (
        %{ $self->{auth_headers} },
        %{ $opts{headers} // {} },
    );

    my %request = (headers => \%headers);
    $request{content} = $opts{content} if exists $opts{content};

    my $response = eval { $self->{client}->request($method, $url, \%request) };
    croak "$method request failed" . _error_suffix($@) if !$response;
    return $response;
}

sub _response_success {
    my ($self, $response) = @_;
    return 0 if ref($response) ne 'HASH';
    return 1 if $response->{success};

    my $status = $response->{status} // 0;
    return $status >= 200 && $status < 300 ? 1 : 0;
}

sub _croak_response {
    my ($self, $operation, $response) = @_;
    my $status = ref($response) eq 'HASH' ? ($response->{status} // 0) : 0;
    my $reason = ref($response) eq 'HASH' ? ($response->{reason} // '') : '';
    croak "$operation failed" . _status_suffix($status, $reason);
}

sub _croak_confirm_failed {
    my ($self, $target_label, $confirm_error) = @_;

    croak "confirm $target_label failed after $self->{publish_confirm_attempts} propfind attempt(s)"
        . _error_suffix($confirm_error);
}

sub _croak_move_failed {
    my ($self, $tmp_label, $target_label, $move_response, $confirm_error) = @_;

    my $suffix = _error_suffix($confirm_error);
    if ($suffix eq '' && ref($move_response) eq 'HASH') {
        $suffix = _status_suffix($move_response->{status} // 0, $move_response->{reason} // '');
    }
    croak "move $tmp_label to $target_label failed$suffix";
}

sub _collection_url {
    my ($self, @components) = @_;
    my $url = $self->_resource_url(@components);
    return $url =~ m{/+\z} ? $url : "$url/";
}

sub _resource_url {
    my ($self, @components) = @_;

    my $url = $self->{root_url};
    for my $component (@components) {
        $url .= '/' . _url_encode_segment($component);
    }
    return $url;
}

sub _hrefs_from_multistatus {
    my ($content, $max_href_count) = @_;
    $max_href_count //= DEFAULT_MAX_HREF_COUNT;

    my @hrefs;
    my @stack;
    my $position = 0;
    my ($response, $capture);
    my ($root_seen, $root_closed);

    while (my $token = _next_xml_token(\$content, \$position)) {
        if ($token->{type} eq 'text') {
            _croak_malformed_xml() if !@stack && $token->{text} !~ /\A\s*\z/;
            $capture->{text} .= $token->{text}
                if $capture && @stack == $capture->{depth};
            next;
        }

        if ($token->{type} eq 'start') {
            my $name = $token->{name};
            my $empty = $token->{empty};

            if (!@stack) {
                _croak_malformed_xml() if $root_seen || $root_closed || $name ne 'multistatus';
                $root_seen = 1;
                if ($empty) {
                    $root_closed = 1;
                    next;
                }
            }
            elsif (!$empty && !$response && $name eq 'response'
                && @stack == 1 && $stack[0] eq 'multistatus') {
                $response = {
                    depth             => @stack + 1,
                    hrefs             => [],
                    direct_statuses   => [],
                    propstat_statuses => [],
                    propstat_depth    => undef,
                };
            }
            elsif (!$empty && $response && @stack == $response->{depth}
                && ($stack[-1] // '') eq 'response') {
                if ($name eq 'href' || $name eq 'status') {
                    $capture = {
                        name  => $name,
                        kind  => $name eq 'href' ? 'href' : 'direct_status',
                        depth => @stack + 1,
                        text  => '',
                    };
                }
                elsif ($name eq 'propstat') {
                    $response->{propstat_depth} = @stack + 1;
                }
            }
            elsif (!$empty && $response && defined $response->{propstat_depth}
                && @stack == $response->{propstat_depth}
                && ($stack[-1] // '') eq 'propstat'
                && $name eq 'status') {
                $capture = {
                    name  => $name,
                    kind  => 'propstat_status',
                    depth => @stack + 1,
                    text  => '',
                };
            }

            push @stack, $name if !$empty;
            next;
        }

        my $name = $token->{name};
        _croak_malformed_xml() if !@stack || $stack[-1] ne $name;

        if ($capture && $name eq $capture->{name} && @stack == $capture->{depth}) {
            if ($capture->{kind} eq 'href') {
                push @{ $response->{hrefs} }, $capture->{text};
            }
            elsif ($capture->{kind} eq 'direct_status') {
                push @{ $response->{direct_statuses} }, $capture->{text};
            }
            elsif ($capture->{kind} eq 'propstat_status') {
                push @{ $response->{propstat_statuses} }, $capture->{text};
            }
            undef $capture;
        }

        if ($response && defined $response->{propstat_depth}
            && $name eq 'propstat' && @stack == $response->{propstat_depth}) {
            $response->{propstat_depth} = undef;
        }

        if ($response && $name eq 'response' && @stack == $response->{depth}) {
            my $href = _response_success_href($response);
            if (defined $href) {
                croak 'webdav href limit exceeded' if @hrefs >= $max_href_count;
                push @hrefs, $href;
            }
            undef $response;
            undef $capture;
        }

        pop @stack;
        $root_closed = 1 if !@stack;
    }

    _croak_malformed_xml() if !$root_seen || !$root_closed || @stack || $response || $capture;
    return @hrefs;
}

sub _response_success_href {
    my ($response) = @_;

    my $success = @{ $response->{direct_statuses} }
        ? _all_statuses_success(@{ $response->{direct_statuses} })
        : _any_status_success(@{ $response->{propstat_statuses} });
    return undef if !$success;

    return $response->{hrefs}[0];
}

sub _any_status_success {
    my (@statuses) = @_;

    for my $status (@statuses) {
        return 1 if _status_is_success($status);
    }
    return 0;
}

sub _next_xml_token {
    my ($xml_ref, $position_ref) = @_;
    my $xml = $$xml_ref;
    my $length = length $xml;

    while ($$position_ref < $length) {
        my $start = index($xml, '<', $$position_ref);
        if ($start < 0) {
            my $text = substr($xml, $$position_ref);
            $$position_ref = $length;
            return { type => 'text', text => _xml_text_decode($text) } if $text ne '';
            return undef;
        }

        if ($start > $$position_ref) {
            my $text = substr($xml, $$position_ref, $start - $$position_ref);
            $$position_ref = $start;
            return { type => 'text', text => _xml_text_decode($text) };
        }

        if (substr($xml, $start, 4) eq '<!--') {
            my $end = index($xml, '-->', $start + 4);
            _croak_malformed_xml() if $end < 0;
            $$position_ref = $end + 3;
            next;
        }

        if (substr($xml, $start, 9) eq '<![CDATA[') {
            my $end = index($xml, ']]>', $start + 9);
            _croak_malformed_xml() if $end < 0;

            $$position_ref = $end + 3;
            return { type => 'text', text => substr($xml, $start + 9, $end - ($start + 9)) };
        }

        if (substr($xml, $start, 2) eq '<?') {
            my $end = index($xml, '?>', $start + 2);
            _croak_malformed_xml() if $end < 0;
            $$position_ref = $end + 2;
            next;
        }

        _croak_malformed_xml() if substr($xml, $start, 2) eq '<!';

        my $end = _xml_tag_end($xml, $start + 1);
        _croak_malformed_xml() if !defined $end;

        my $body = substr($xml, $start + 1, $end - $start - 1);
        $$position_ref = $end + 1;

        if ($body =~ s{\A/}{}) {
            my $name = _xml_end_name($body);
            _croak_malformed_xml() if !defined $name;
            return { type => 'end', name => $name };
        }

        my $empty = $body =~ s{/\s*\z}{};
        my $name = _xml_start_name($body);
        _croak_malformed_xml() if !defined $name;
        return { type => 'start', name => $name, empty => $empty ? 1 : 0 };
    }

    return undef;
}

sub _croak_malformed_xml {
    croak 'webdav multistatus XML malformed';
}

sub _xml_tag_end {
    my ($xml, $position) = @_;
    my $quote;

    for (my $index = $position; $index < length($xml); $index++) {
        my $char = substr($xml, $index, 1);
        if (defined $quote) {
            undef $quote if $char eq $quote;
            next;
        }

        if ($char eq q{"} || $char eq q{'}) {
            $quote = $char;
            next;
        }

        return $index if $char eq '>';
    }

    return undef;
}

sub _xml_start_name {
    my ($body) = @_;

    my $xml_name = qr/[A-Za-z_][A-Za-z0-9_.:-]*/;
    return undef if $body !~ s/\A\s*($xml_name)//;
    my $name = $1;
    while ($body !~ /\A\s*\z/) {
        return undef if $body !~ s/\A\s+($xml_name)\s*=\s*(["'])//;
        my $quote = $2;
        return undef if $body !~ s/\A([^$quote]*)\Q$quote\E//;
        my $value = $1;
        return undef if $value =~ /</;
        _xml_text_decode($value);
    }

    $name =~ s/\A.*://;
    return lc $name;
}

sub _xml_end_name {
    my ($body) = @_;

    return undef if $body !~ /\A\s*([A-Za-z_][A-Za-z0-9_.:-]*)\s*\z/;
    my $name = $1;
    $name =~ s/\A.*://;
    return lc $name;
}

sub _all_statuses_success {
    my (@statuses) = @_;

    return 0 if !@statuses;
    for my $status (@statuses) {
        return 0 if !_status_is_success($status);
    }
    return 1;
}

sub _status_is_success {
    my ($status) = @_;

    return $status =~ m{\bHTTP/\S+\s+2[0-9][0-9]\b}i
        || $status =~ m{\A\s*2[0-9][0-9]\b}
        ? 1
        : 0;
}

sub _direct_href_child {
    my ($href, $collection_segments) = @_;

    my @segments = _href_segments($href);
    return undef if !@segments && @$collection_segments;
    return undef if @segments < @$collection_segments;

    for my $index (0 .. $#$collection_segments) {
        return undef if !defined($segments[$index]) || $segments[$index] ne $collection_segments->[$index];
    }

    return undef if @segments == @$collection_segments;
    return undef if @segments != @$collection_segments + 1;

    my $name = $segments[-1];
    return undef if !defined $name;
    return undef if $name !~ /\A[A-Za-z0-9._-]+\z/;
    return eval { _name_component($name) };
}

sub _href_segments {
    my ($href) = @_;

    return () if !defined($href) || $href eq '';

    $href =~ s{\Ahttps?://[^/]*}{}i;
    $href =~ s/[?#].*\z//;
    $href =~ s{/+\z}{};
    $href =~ s{\A/+}{};

    return () if $href eq '';

    my @segments;
    for my $segment (split m{/+}, $href) {
        next if $segment eq '';
        my $decoded = _percent_decode_once($segment);
        return () if !defined $decoded;
        push @segments, $decoded;
    }
    return @segments;
}

sub _root_url {
    my ($url) = @_;

    croak 'url contains invalid character' if $url =~ /[\0\r\n]/;
    croak 'url must be http or https' if $url !~ m{\Ahttps?://}i;
    croak 'url must not contain credentials' if $url =~ m{\Ahttps?://[^/?#]*@}i;
    croak 'url must not contain query or fragment' if $url =~ /[?#]/;

    $url =~ s{/+\z}{};

    my @segments = _href_segments($url);
    croak 'url contains invalid percent encoding' if !@segments && $url =~ m{https?://[^/]+/.+}i;

    return ($url, @segments);
}

sub _propfind_body {
    return <<'XML';
<?xml version="1.0" encoding="utf-8"?>
<D:propfind xmlns:D="DAV:"><D:allprop/></D:propfind>
XML
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

    return "$1-$2-$3.part"
        if $event_name =~ /(?:\A|\.)by-([a-z0-9_-]+)\.n-([a-z0-9_-]+)\.h-([0-9a-v]{16})(?:\z|[.])/;

    my $tmp = $event_name;
    $tmp =~ s/[^a-z0-9._-]+/-/g;
    return "$tmp.part";
}

sub _url_encode_segment {
    my ($segment) = @_;

    $segment =~ s{([^A-Za-z0-9._~-])}{sprintf '%%%02X', ord($1)}eg;
    return $segment;
}

sub _percent_decode_once {
    my ($value) = @_;

    return undef if !defined $value;
    return undef if $value =~ /%(?![0-9A-Fa-f]{2})/;

    $value =~ s/%([0-9A-Fa-f]{2})/chr hex $1/eg;
    return $value;
}

sub _xml_text_decode {
    my ($value) = @_;

    _croak_malformed_xml()
        if $value =~ /&(?![A-Za-z][A-Za-z0-9]*;|#[0-9]+;|#x[0-9A-Fa-f]+;)/;
    $value =~ s/&([A-Za-z][A-Za-z0-9]*|#[0-9]+|#x[0-9A-Fa-f]+);/_xml_entity_decode($1)/eg;
    return $value;
}

sub _xml_entity_decode {
    my ($entity) = @_;

    my %named = (
        lt   => '<',
        gt   => '>',
        quot => '"',
        apos => "'",
        amp  => '&',
    );
    return $named{$entity} if exists $named{$entity};

    my $codepoint;
    if ($entity =~ /\A#([0-9]+)\z/) {
        $codepoint = 0 + $1;
    }
    elsif ($entity =~ /\A#x([0-9A-Fa-f]+)\z/) {
        $codepoint = hex $1;
    }
    else {
        _croak_malformed_xml();
    }

    _croak_malformed_xml()
        if $codepoint == 0
            || $codepoint > 0x10FFFF
            || ($codepoint >= 0xD800 && $codepoint <= 0xDFFF)
            || ($codepoint < 0x20 && $codepoint != 0x09 && $codepoint != 0x0A && $codepoint != 0x0D);
    return chr $codepoint;
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

sub _status_suffix {
    my ($status, $reason) = @_;

    $status //= 0;
    $reason //= '';
    $reason =~ s/\s+\z//;
    return $reason eq '' ? ": HTTP $status" : ": HTTP $status $reason";
}

sub _error_suffix {
    my ($error) = @_;

    return '' if !defined($error) || $error eq '';
    $error =~ s/\s+\z//;
    return $error eq '' ? '' : ": $error";
}

1;

__END__

=head1 NAME

GobanFTP::Store::WebDAV - WebDAV collection store backend

=cut
