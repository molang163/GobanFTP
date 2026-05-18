package GobanFTP::Store::WebDAV;

use v5.34;
use strict;
use warnings;

use parent 'GobanFTP::Store';

use Carp qw(croak);
use HTTP::Tiny ();
use MIME::Base64 qw(encode_base64);

sub new {
    my ($class, %args) = @_;

    my $client = delete $args{client};
    my $url = delete($args{url}) // delete($args{root_url});
    croak 'url is required' if !defined($url) || $url eq '';

    my $publish_mode = delete($args{publish_mode}) // 'move';
    my $publish_confirm_attempts = delete($args{publish_confirm_attempts}) // 3;
    my $publish_move_attempts    = delete($args{publish_move_attempts})    // 2;
    my $publish_confirm_delay    = delete($args{publish_confirm_delay})    // 0;

    croak 'publish_mode must be move or mkcol'
        if $publish_mode ne 'move' && $publish_mode ne 'mkcol';
    $publish_confirm_attempts = _positive_int_option('publish_confirm_attempts', $publish_confirm_attempts);
    $publish_move_attempts    = _positive_int_option('publish_move_attempts',    $publish_move_attempts);
    $publish_confirm_delay    = _nonnegative_number_option('publish_confirm_delay', $publish_confirm_delay);

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

    my @collection = (@{ $self->{root_segments} }, @path);
    my %seen;
    my @names = grep { !$seen{$_}++ }
        grep { defined && $_ ne '' }
        map { _direct_href_child($_, \@collection) } _hrefs_from_multistatus($response->{content} // '');

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
    my ($content) = @_;

    my @hrefs;
    while ($content =~ m{<(?:(?:[A-Za-z_][\w.-]*):)?href\b[^>]*>(.*?)</(?:(?:[A-Za-z_][\w.-]*):)?href>}gis) {
        push @hrefs, _xml_text_decode($1);
    }
    return @hrefs;
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

    return "$1-$2.part"
        if $event_name =~ /(?:\A|\.)by-([a-z0-9_-]+)\.n-([a-z0-9_-]+)(?:\.|\z)/;

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

    $value =~ s/&lt;/</g;
    $value =~ s/&gt;/>/g;
    $value =~ s/&quot;/"/g;
    $value =~ s/&apos;/'/g;
    $value =~ s/&amp;/&/g;
    return $value;
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
