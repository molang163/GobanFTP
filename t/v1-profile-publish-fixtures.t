use v5.34;
use strict;
use warnings;

use FindBin;
use File::Spec;
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::Store::WebDAV;
use GobanFTP::Witness qw(witness_for_listing);

my $fixture_dir = "$FindBin::Bin/fixtures/v1/publish-failures/webdav-publish-failure";
my $root_url = 'https://dav.example.test/goftp';
my $root_path = 'goftp';

my $game = _read_single(File::Spec->catfile($fixture_dir, 'game.name'));
my $event = _read_single(File::Spec->catfile($fixture_dir, 'event.name'));
my $expected = _read_verdict(File::Spec->catfile($fixture_dir, 'expected.verdict'));

is $expected->{case}, 'webdav-publish-failure', 'fixture declares publish failure case';
is $expected->{profile}, 'webdav-goftp1', 'fixture declares WebDAV profile';
is $expected->{game}, $game, 'fixture verdict game matches game.name';
is $expected->{event}, $event, 'fixture verdict event matches event.name';
ok $expected->{ignored_inputs} ne '', 'fixture declares ignored publish inputs';
ok $expected->{note} ne '', 'fixture has a judgment note';

subtest 'existing final name is idempotent and does not upload again' => sub {
    my $http = PublishFixtureWebDAV->new(root => $root_path);
    $http->create_file("$root_path/$game/events/$event");
    $http->create_file("$root_path/$game/tmp/alice-pub1.part");
    my $store = _store($http);

    ok $store->publish_event_name($game, $event), 'existing final event is publish success';

    my @write_calls = grep { $_->[0] =~ /\A(?:PUT|MOVE)\z/ } $http->calls;
    is_deeply \@write_calls, [], 'existing final event does not upload or move';
    _assert_webdav_witness($http, 0 + $expected->{success_accepted_count}, $expected->{published_event_set_root});
    _assert_no_forbidden_reads($http, 'existing-final confirm stays listing-first');
};

subtest 'lost MOVE response succeeds only after fresh PROPFIND visibility' => sub {
    my $http = PublishFixtureWebDAV->new(
        root => $root_path,
        move_hook => sub {
            my ($http, $source, $target) = @_;
            $http->schedule_create_file($target, after_propfinds => 2);
            return _response(500, 'MOVE response lost');
        },
    );
    my $store = _store(
        $http,
        publish_confirm_attempts => 3,
        publish_move_attempts    => 1,
    );

    ok $store->publish_event_name($game, $event),
        'delayed final event is accepted after PROPFIND confirmation';

    is_deeply [ $http->put_sizes ], [0], 'temporary publish resource is zero bytes';
    is scalar(grep { $_->[0] eq 'MOVE' } $http->calls), 1, 'lost MOVE response is not retried after visibility';
    ok $http->exists_path("$root_path/$game/events/$event"), 'final event is visible';
    _assert_webdav_witness($http, 0 + $expected->{success_accepted_count}, $expected->{published_event_set_root});
    _assert_no_forbidden_reads($http, 'delayed confirm uses PROPFIND, not resource reads');
};

subtest 'hard MOVE failure leaves only temporary debris outside witness truth' => sub {
    my $http = PublishFixtureWebDAV->new(
        root => $root_path,
        move_hook => sub {
            return _response(423, 'Locked');
        },
    );
    my $store = _store(
        $http,
        publish_confirm_attempts => 2,
        publish_move_attempts    => 2,
    );

    like _exception(sub { $store->publish_event_name($game, $event) }),
        qr/\A\Q$expected->{hard_failure_error}\E/,
        'hard publish failure reports stable storage surface';

    is_deeply [ $http->put_sizes ], [0], 'failed publish uploaded one zero-byte temporary resource';
    is scalar(grep { $_->[0] eq 'MOVE' } $http->calls), 2, 'hard failure uses bounded MOVE retries';
    ok !$http->exists_path("$root_path/$game/events/$event"), 'final event is not visible';
    ok $http->exists_path("$root_path/$game/tmp/alice-pub1.part"), 'temporary debris remains visible outside events';
    _assert_webdav_witness($http, 0 + $expected->{failure_accepted_count}, $expected->{empty_event_set_root});
    _assert_no_forbidden_reads($http, 'hard failure still avoids resource-content reads');
};

done_testing;

sub _store {
    my ($http, %args) = @_;
    return GobanFTP::Store::WebDAV->new(
        url => $root_url,
        client => $http,
        %args,
    );
}

sub _assert_webdav_witness {
    my ($http, $accepted_count, $event_set_root) = @_;

    my @raw = $http->profile_listing_rows($root_path, $game);
    my $witness = witness_for_listing(
        profile_id      => 'webdav-goftp1',
        game_descriptor => $game,
        raw_names       => \@raw,
    );

    is $witness->{accepted_count}, $accepted_count, 'accepted count matches fixture verdict';
    is $witness->{event_set_root}, $event_set_root, 'event_set_root matches fixture verdict';
    is $witness->{replay_status}, 'ok', 'accepted event set replays cleanly';
    ok !grep({ m{/} } @{ $witness->{accepted_events} }), 'accepted events remain basenames';
    unlike join(',', @{ $witness->{normalized_events} }), qr/tmp|part|payload/,
        'temporary publish debris does not survive WebDAV profile normalization';
}

sub _assert_no_forbidden_reads {
    my ($http, $description) = @_;

    my @forbidden = grep { $_->[0] =~ /\A(?:GET|HEAD|LOCK|UNLOCK|PROPPATCH|DELETE)\z/ } $http->calls;
    is_deeply \@forbidden, [], $description;
}

sub _exception {
    my ($code) = @_;

    my $error = '';
    eval { $code->(); 1 } or $error = $@;
    chomp $error;
    return $error;
}

sub _read_verdict {
    my ($path) = @_;

    my %verdict;
    open my $fh, '<:encoding(UTF-8)', $path or die "open $path: $!";
    while (my $line = <$fh>) {
        chomp $line;
        next if $line =~ /\A\s*\z/;
        my ($key, $value) = split /=/, $line, 2;
        die "bad verdict line in $path: $line" if !defined($key) || !defined($value);
        $verdict{$key} = $value;
    }
    close $fh or die "close $path: $!";

    return \%verdict;
}

sub _read_single {
    my ($path) = @_;

    open my $fh, '<:encoding(UTF-8)', $path or die "open $path: $!";
    my @lines;
    while (my $line = <$fh>) {
        chomp $line;
        next if $line =~ /\A\s*\z/;
        push @lines, $line;
    }
    close $fh or die "close $path: $!";

    die "$path must contain exactly one nonblank line" if @lines != 1;
    return $lines[0];
}

sub _response {
    my ($status, $reason, %args) = @_;
    return {
        status  => $status,
        reason  => $reason,
        success => $status >= 200 && $status < 300 ? 1 : 0,
        headers => $args{headers} // {},
        content => $args{content} // '',
    };
}

package PublishFixtureWebDAV;

use v5.34;
use strict;
use warnings;

sub new {
    my ($class, %args) = @_;

    my $root = _canon($args{root} // '');
    my $entries = { '' => 'dir' };
    $entries->{$root} = 'dir' if $root ne '';

    return bless {
        entries => $entries,
        calls   => [],
        put_sizes => [],
        move_hook => $args{move_hook},
        scheduled_creates => [],
    }, $class;
}

sub calls {
    my ($self) = @_;
    return @{ $self->{calls} };
}

sub put_sizes {
    my ($self) = @_;
    return @{ $self->{put_sizes} };
}

sub exists_path {
    my ($self, $path) = @_;
    return exists $self->{entries}{ _canon($path) } ? 1 : 0;
}

sub create_file {
    my ($self, $path) = @_;

    $path = _canon($path);
    my $parent = _parent($path);
    $self->_mkdir_internal($parent) if !exists $self->{entries}{$parent};
    $self->{entries}{$path} = 'file';
    return 1;
}

sub schedule_create_file {
    my ($self, $path, %args) = @_;

    push @{ $self->{scheduled_creates} }, {
        path      => _canon($path),
        parent    => _parent($path),
        remaining => $args{after_propfinds} // 1,
    };
    return 1;
}

sub profile_listing_rows {
    my ($self, $root, $game) = @_;

    my $prefix = _canon("$root/$game");
    return map { 'href=' . _href_for_path($_) }
        sort grep { $_ eq $prefix || /\A\Q$prefix\E\// } keys %{ $self->{entries} };
}

sub request {
    my ($self, $method, $url, $opts) = @_;
    $opts //= {};

    my $call_opts = {
        headers => { %{ $opts->{headers} // {} } },
        exists($opts->{content}) ? (content => $opts->{content}) : (),
    };
    push @{ $self->{calls} }, [ $method, $url, $call_opts ];

    my $path = _path_from_url($url);

    return $self->_propfind($path, $opts) if $method eq 'PROPFIND';
    return $self->_mkcol($path) if $method eq 'MKCOL';
    return $self->_put($path, $opts) if $method eq 'PUT';
    return $self->_move($path, $opts) if $method eq 'MOVE';

    return main::_response(405, 'Method Not Allowed');
}

sub _propfind {
    my ($self, $path, $opts) = @_;

    return main::_response(400, 'Bad Depth')
        if ($opts->{headers}{Depth} // '') ne '1';

    $self->_apply_scheduled_creates($path);

    return main::_response(404, 'Not Found')
        if ($self->{entries}{$path} // '') ne 'dir';

    my @children = sort
        grep { $_ ne '' && _parent($_) eq $path }
        keys %{ $self->{entries} };
    my @hrefs = (_href_for_path($path), map { _href_for_path($_) } @children);
    my $xml = qq{<?xml version="1.0" encoding="utf-8"?><D:multistatus xmlns:D="DAV:">}
        . join('', map {
            '<D:response><D:href>' . _xml_escape($_) . '</D:href>'
                . '<D:propstat><D:prop><D:getetag>"ignored"</D:getetag>'
                . '<D:getcontentlength>999</D:getcontentlength>'
                . '</D:prop></D:propstat></D:response>'
        } @hrefs)
        . '</D:multistatus>';

    return main::_response(207, 'Multi-Status', content => $xml);
}

sub _mkcol {
    my ($self, $path) = @_;

    return main::_response(405, 'Method Not Allowed') if ($self->{entries}{$path} // '') eq 'dir';
    return main::_response(409, 'Conflict') if ($self->{entries}{ _parent($path) } // '') ne 'dir';

    $self->{entries}{$path} = 'dir';
    return main::_response(201, 'Created');
}

sub _put {
    my ($self, $path, $opts) = @_;

    return main::_response(409, 'Conflict') if ($self->{entries}{ _parent($path) } // '') ne 'dir';

    push @{ $self->{put_sizes} }, length($opts->{content} // '');
    $self->{entries}{$path} = 'file';
    return main::_response(201, 'Created');
}

sub _move {
    my ($self, $source, $opts) = @_;

    my $target = _path_from_url($opts->{headers}{Destination} // '');

    if (my $hook = $self->{move_hook}) {
        return $hook->($self, $source, $target);
    }

    return main::_response(404, 'Source Missing') if !exists $self->{entries}{$source};
    return main::_response(412, 'Precondition Failed')
        if ($opts->{headers}{Overwrite} // '') eq 'F' && exists $self->{entries}{$target};
    return main::_response(409, 'Conflict') if ($self->{entries}{ _parent($target) } // '') ne 'dir';

    $self->{entries}{$target} = delete $self->{entries}{$source};
    return main::_response(201, 'Created');
}

sub _apply_scheduled_creates {
    my ($self, $listed_path) = @_;

    my @remaining;
    for my $item (@{ $self->{scheduled_creates} }) {
        if ($item->{parent} eq $listed_path) {
            $item->{remaining}--;
            if ($item->{remaining} <= 0) {
                $self->create_file($item->{path});
                next;
            }
        }
        push @remaining, $item;
    }
    $self->{scheduled_creates} = \@remaining;
    return 1;
}

sub _mkdir_internal {
    my ($self, $path) = @_;

    $path = _canon($path);
    return if $path eq '';

    my $current = '';
    for my $component (split m{/+}, $path) {
        $current = $current eq '' ? $component : "$current/$component";
        $self->{entries}{$current} = 'dir';
    }

    return;
}

sub _path_from_url {
    my ($url) = @_;

    $url =~ s{\Ahttps?://[^/]*}{}i;
    $url =~ s/[?#].*\z//;
    return _canon(_percent_decode($url));
}

sub _href_for_path {
    my ($path) = @_;
    my $href = join '/', map { _url_encode($_) } grep { $_ ne '' } split m{/+}, _canon($path);
    return "/$href";
}

sub _canon {
    my ($path) = @_;

    $path //= '';
    $path =~ s{\A/+}{};
    $path =~ s{/+\z}{};
    return $path;
}

sub _parent {
    my ($path) = @_;

    $path = _canon($path);
    return '' if $path !~ m{/};
    $path =~ s{/[^/]+\z}{};
    return $path;
}

sub _url_encode {
    my ($value) = @_;
    $value =~ s{([^A-Za-z0-9._~-])}{sprintf '%%%02X', ord($1)}eg;
    return $value;
}

sub _percent_decode {
    my ($value) = @_;
    $value =~ s/%([0-9A-Fa-f]{2})/chr hex $1/eg;
    return $value;
}

sub _xml_escape {
    my ($value) = @_;
    $value =~ s/&/&amp;/g;
    $value =~ s/</&lt;/g;
    $value =~ s/>/&gt;/g;
    return $value;
}
