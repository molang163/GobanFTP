use v5.34;
use strict;
use warnings;

use FindBin;
use Test::More;

use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/lib";

use GobanFTP::Store::WebDAV;
use GobanFTP::Test::StoreContract qw(run_store_contract);

my $root_url = 'https://dav.example.test/goftp';
my $game = 'g1.id-webdav-mock.s9.r-chinese-area-v1.k7500.pb-alice.pw-bob';
my $move_b = 'm1.p000001.b.play-dd.pa-genesis.by-alice.n-k31v.h-f98qai37nace5spg';
my $move_w = 'm1.p000002.w.play-ee.pa-f98qai37nace5spg.by-bob.n-q9az.h-5ivvsvtid3j6u1pg';

subtest 'Store::WebDAV satisfies the shared store contract with a mock server' => sub {
    my $http = MockWebDAV->new(root => 'goftp');
    my $store = GobanFTP::Store::WebDAV->new(url => $root_url, client => $http);

    run_store_contract(
        name  => 'Store::WebDAV mock move',
        store => $store,
        game  => $game,
    );

    no_forbidden_reads($http, 'contract uses PROPFIND only for reads');
};

subtest 'move publish mode uses zero-byte temp PUT and MOVE target' => sub {
    my $http = MockWebDAV->new(root => 'goftp');
    my $store = GobanFTP::Store::WebDAV->new(url => $root_url, client => $http);

    ok $store->mkdir($game), 'created game root';
    ok $store->publish_event_name($game, $move_b), 'published event through MOVE mode';

    my @calls = $http->calls;
    my @ops = map { $_->[0] } @calls;
    my $put_at = first_index(\@ops, 'PUT');
    my $move_at = first_index(\@ops, 'MOVE');

    ok defined($put_at), 'temporary resource was uploaded';
    ok defined($move_at), 'temporary resource was moved';
    ok $put_at < $move_at, 'PUT happens before MOVE';

    my ($put_call) = grep { $_->[0] eq 'PUT' } @calls;
    my ($move_call) = grep { $_->[0] eq 'MOVE' } @calls;

    is $put_call->[1], "$root_url/$game/tmp/alice-k31v.part", 'temp upload path uses player and nonce';
    is $move_call->[1], "$root_url/$game/tmp/alice-k31v.part", 'MOVE source is the temp path';
    is $move_call->[2]{headers}{Destination}, "$root_url/$game/events/$move_b",
        'MOVE destination is events/event_name';
    is $move_call->[2]{headers}{Overwrite}, 'F', 'MOVE does not overwrite an existing event';
    is_deeply [ $http->put_sizes ], [0], 'temp upload is zero bytes';
    is $http->entry_type("goftp/$game/events/$move_b"), 'file', 'MOVE mode publishes a file resource';

    my $before = scalar $http->calls;
    ok $store->publish_event_name($game, $move_b), 'existing event name is idempotent success';
    my @after = ($http->calls)[$before .. ($http->calls) - 1];
    is_deeply [ grep { $_->[0] =~ /\A(?:PUT|MOVE)\z/ } @after ],
        [],
        'existing final event does not upload or move again';

    no_forbidden_reads($http, 'MOVE publish did not use resource-content reads');
};

subtest 'lost MOVE response treats an already-created final event as success' => sub {
    my $http = MockWebDAV->new(
        root      => 'goftp',
        move_hook => sub {
            my ($http, $source, $target) = @_;
            $http->create_file($target);
            return response(500, 'MOVE response lost');
        },
    );
    my $store = GobanFTP::Store::WebDAV->new(url => $root_url, client => $http);

    ok $store->mkdir($game), 'created game root';
    ok $store->publish_event_name($game, $move_w), 'MOVE failure with existing final is success';
    ok $store->exists_name("$game/events", $move_w), 'final event exists after MOVE race';

    no_forbidden_reads($http, 'MOVE race check uses PROPFIND only');
};

subtest 'MOVE failure uses bounded PROPFIND confirm without changing the event name' => sub {
    my $http = MockWebDAV->new(
        root      => 'goftp',
        move_hook => sub {
            my ($http, $source, $target) = @_;
            $http->schedule_create_file($target, after_propfinds => 2);
            return response(500, 'MOVE response lost');
        },
    );
    my $store = GobanFTP::Store::WebDAV->new(
        url => $root_url,
        client => $http,
        publish_confirm_attempts => 3,
        publish_move_attempts    => 1,
    );

    ok $store->mkdir($game), 'created game root';
    ok $store->publish_event_name($game, $move_w), 'delayed final event is confirmed through PROPFIND';
    ok $store->exists_name("$game/events", $move_w), 'final event exists after delayed confirm';

    my @move_calls = grep { $_->[0] eq 'MOVE' } $http->calls;
    is scalar(@move_calls), 1, 'MOVE was not retried when confirm found the target';
    is_deeply [ map { $_->[2]{headers}{Destination} } @move_calls ],
        [ "$root_url/$game/events/$move_w" ],
        'confirm keeps the originally requested event name';

    no_forbidden_reads($http, 'delayed MOVE confirm uses PROPFIND only');
};

subtest 'MOVE failure is bounded and retries the same temp and target paths' => sub {
    my $http = MockWebDAV->new(
        root      => 'goftp',
        move_hook => sub {
            return response(423, 'Locked');
        },
    );
    my $store = GobanFTP::Store::WebDAV->new(
        url => $root_url,
        client => $http,
        publish_confirm_attempts => 2,
        publish_move_attempts    => 2,
    );

    my $tmp_path = "$game/tmp/alice-k31v.part";
    my $target_path = "$game/events/$move_b";

    like exception(sub { $store->publish_event_name($game, $move_b) }),
        qr/move \Q$tmp_path\E to \Q$target_path\E failed: HTTP 423 Locked/,
        'MOVE failure reports the fixed temp and target paths';

    my @put_calls = grep { $_->[0] eq 'PUT' } $http->calls;
    my @move_calls = grep { $_->[0] eq 'MOVE' } $http->calls;

    is scalar(@put_calls), 1, 'failed MOVE is not re-uploaded';
    is scalar(@move_calls), 2, 'MOVE retry count is bounded';
    is_deeply [ map { $_->[1] } @move_calls ], [ ("$root_url/$tmp_path") x 2 ],
        'MOVE retries the same temporary path';
    is_deeply [ map { $_->[2]{headers}{Destination} } @move_calls ],
        [ ("$root_url/$target_path") x 2 ],
        'MOVE retries the same event target';

    no_forbidden_reads($http, 'bounded MOVE retry does not use resource-content reads');
};

subtest 'mkcol publish mode creates directory-shaped events without upload' => sub {
    my $http = MockWebDAV->new(root => 'goftp');
    my $store = GobanFTP::Store::WebDAV->new(url => $root_url, client => $http, publish_mode => 'mkcol');

    ok $store->publish_event_name($game, $move_b), 'published event through MKCOL mode';
    ok $store->exists_name("$game/events", $move_b), 'MKCOL mode event is listed';
    is $http->entry_type("goftp/$game/events/$move_b"), 'dir', 'MKCOL mode publishes a collection';

    my @write_ops = grep { $_->[0] =~ /\A(?:PUT|MOVE)\z/ } $http->calls;
    is_deeply \@write_ops, [], 'MKCOL mode does not upload or move';
};

subtest 'list_names handles empty collections without treating missing paths as empty' => sub {
    my $http = MockWebDAV->new(root => 'goftp');
    my $store = GobanFTP::Store::WebDAV->new(url => $root_url, client => $http);

    ok $store->mkdir("$game/events/empty"), 'created empty child collection';
    is_deeply [ $store->list_names("$game/events/empty") ], [],
        'empty collection listing is accepted';

    like exception(sub { $store->list_names('missing') }), qr/propfind missing failed: HTTP 404 Not Found/,
        'missing collection is surfaced as a missing path';
};

subtest 'PROPFIND href parsing ignores metadata, duplicates, and recursive descendants' => sub {
    my $http = MockWebDAV->new(root => 'goftp');
    my $store = GobanFTP::Store::WebDAV->new(url => $root_url, client => $http);

    $http->create_file("goftp/$game/events/$move_b");
    $http->add_href("goftp/$game/events", "$root_url/$game/events/$move_b");
    $http->add_href("goftp/$game/events", "$root_url/$game/events/$move_b/child");
    $http->add_href("goftp/$game/events", "$root_url/$game/events/bad%2Fslash");
    $http->add_href("goftp/$game/events", "$root_url/$game/events/$move_b%2Fchild");
    $http->add_href("goftp/$game/events", "$root_url/$game/events/$move_b%252Fchild");
    $http->add_href("goftp/$game/events", "$root_url/$game/events/bad%zz");

    is_deeply [ $store->list_names("$game/events") ], [$move_b],
        'only the direct decoded event basename survives';
    no_forbidden_reads($http, 'href parsing uses PROPFIND only');
};

subtest 'PROPFIND href order and duplicates do not affect returned names' => sub {
    my $http = MockWebDAV->new(root => 'goftp');
    my $store = GobanFTP::Store::WebDAV->new(url => $root_url, client => $http);

    ok $store->mkdir("$game/events"), 'created events collection';
    $http->add_href("goftp/$game/events", "$root_url/$game/events/$move_w");
    $http->add_href("goftp/$game/events", "$root_url/$game/events/$move_b");
    $http->add_href("goftp/$game/events", "$root_url/$game/events/$move_w");

    is_deeply [ $store->list_names("$game/events") ], [ sort ($move_b, $move_w) ],
        'unordered duplicate hrefs are deduplicated and sorted';
    no_forbidden_reads($http, 'order test uses PROPFIND only');
};

done_testing;

sub first_index {
    my ($items, $wanted) = @_;

    for my $index (0 .. $#$items) {
        return $index if $items->[$index] eq $wanted;
    }

    return undef;
}

sub no_forbidden_reads {
    my ($http, $description) = @_;

    my @forbidden = grep { $_->[0] =~ /\A(?:GET|HEAD|LOCK|UNLOCK|PROPPATCH|DELETE)\z/ } $http->calls;
    is_deeply \@forbidden, [], $description;
}

sub exception {
    my ($code) = @_;

    my $error;
    eval { $code->(); 1 } or $error = $@;

    return $error;
}

sub response {
    my ($status, $reason, %args) = @_;
    return {
        status  => $status,
        reason  => $reason,
        success => $status >= 200 && $status < 300 ? 1 : 0,
        headers => $args{headers} // {},
        content => $args{content} // '',
    };
}

package MockWebDAV;

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
        extra_hrefs => {},
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

sub entry_type {
    my ($self, $path) = @_;
    return $self->{entries}{ _canon($path) };
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

sub add_href {
    my ($self, $parent, $href) = @_;
    push @{ $self->{extra_hrefs}{ _canon($parent) } }, $href;
    return 1;
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

    return main::response(405, 'Method Not Allowed');
}

sub _propfind {
    my ($self, $path, $opts) = @_;

    return main::response(400, 'Bad Depth')
        if ($opts->{headers}{Depth} // '') ne '1';

    $self->_apply_scheduled_creates($path);

    return main::response(404, 'Not Found')
        if ($self->{entries}{$path} // '') ne 'dir';

    my @children = sort
        grep { $_ ne '' && _parent($_) eq $path }
        keys %{ $self->{entries} };
    my @hrefs = (_href_for_path($path), map { _href_for_path($_) } @children);
    push @hrefs, @{ $self->{extra_hrefs}{$path} // [] };

    my $xml = qq{<?xml version="1.0" encoding="utf-8"?><D:multistatus xmlns:D="DAV:">}
        . join('', map {
            '<D:response><D:href>' . _xml_escape($_) . '</D:href>'
                . '<D:propstat><D:prop><D:getetag>"ignored"</D:getetag>'
                . '<D:getlastmodified>Mon, 18 May 2026 00:00:00 GMT</D:getlastmodified>'
                . '<D:getcontentlength>999</D:getcontentlength>'
                . '</D:prop></D:propstat></D:response>'
        } @hrefs)
        . '</D:multistatus>';

    return main::response(207, 'Multi-Status', content => $xml);
}

sub _mkcol {
    my ($self, $path) = @_;

    return main::response(405, 'Method Not Allowed') if ($self->{entries}{$path} // '') eq 'dir';
    return main::response(409, 'Conflict') if ($self->{entries}{ _parent($path) } // '') ne 'dir';

    $self->{entries}{$path} = 'dir';
    return main::response(201, 'Created');
}

sub _put {
    my ($self, $path, $opts) = @_;

    return main::response(409, 'Conflict') if ($self->{entries}{ _parent($path) } // '') ne 'dir';

    push @{ $self->{put_sizes} }, length($opts->{content} // '');
    $self->{entries}{$path} = 'file';
    return main::response(201, 'Created');
}

sub _move {
    my ($self, $source, $opts) = @_;

    my $target = _path_from_url($opts->{headers}{Destination} // '');

    if (my $hook = $self->{move_hook}) {
        return $hook->($self, $source, $target);
    }

    return main::response(404, 'Source Missing') if !exists $self->{entries}{$source};
    return main::response(412, 'Precondition Failed')
        if ($opts->{headers}{Overwrite} // '') eq 'F' && exists $self->{entries}{$target};
    return main::response(409, 'Conflict') if ($self->{entries}{ _parent($target) } // '') ne 'dir';

    $self->{entries}{$target} = delete $self->{entries}{$source};
    return main::response(201, 'Created');
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
