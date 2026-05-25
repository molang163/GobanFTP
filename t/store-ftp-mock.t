use v5.34;
use strict;
use warnings;

use FindBin;
use Test::More;

use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/lib";

use GobanFTP::Store::FTP;
use GobanFTP::MovePublisher qw(build_move_name);
use GobanFTP::Test::StoreContract qw(run_store_contract);

my $game = 'g1.id-ftp-mock.s9.r-chinese-area-v1.k7500.pb-alice.pw-bob';
my $move_b = 'm1.p000001.b.play-dd.pa-genesis.by-alice.n-k31v.h-f98qai37nace5spg';
my $move_w = 'm1.p000002.w.play-ee.pa-f98qai37nace5spg.by-bob.n-q9az.h-5ivvsvtid3j6u1pg';

subtest 'Store::FTP satisfies the shared store contract with a mock FTP server' => sub {
    my $ftp = MockFTP->new;
    my $store = GobanFTP::Store::FTP->new(ftp => $ftp);

    run_store_contract(
        name  => 'Store::FTP mock rename',
        store => $store,
        game  => $game,
    );

    no_forbidden_reads($ftp, 'contract uses FTP listing commands only for reads');
};

subtest 'rename publish mode uses binary zero-byte temp upload and RNTO target' => sub {
    my $ftp = MockFTP->new;
    my $store = GobanFTP::Store::FTP->new(ftp => $ftp);

    ok $store->mkdir($game), 'created game root';
    ok $store->publish_event_name($game, $move_b), 'published event through rename mode';

    my @calls = $ftp->calls;
    my @ops = map { $_->[0] } @calls;

    my $binary_at = first_index(\@ops, 'binary');
    my $put_at = first_index(\@ops, 'put');
    my $rename_at = first_index(\@ops, 'rename');

    ok defined($binary_at), 'binary mode was set';
    ok defined($put_at), 'temporary file was uploaded';
    ok defined($rename_at), 'temporary file was renamed';
    ok $binary_at < $put_at && $put_at < $rename_at,
        'binary, put, and rename happen in publish order';

    my ($put_call) = grep { $_->[0] eq 'put' } @calls;
    my ($rename_call) = grep { $_->[0] eq 'rename' } @calls;

    is $put_call->[2], "$game/tmp/alice-k31v-f98qai37nace5spg.part", 'temp upload path uses player, nonce, and event id';
    is $rename_call->[1], "$game/tmp/alice-k31v-f98qai37nace5spg.part", 'rename source is the temp path';
    is $rename_call->[2], "$game/events/$move_b", 'rename target is events/event_name';
    is_deeply [ $ftp->put_sizes ], [0], 'temp upload is zero bytes';
    is $ftp->entry_type("$game/events/$move_b"), 'file', 'rename mode publishes a file entry';

    my $before = scalar $ftp->calls;
    ok $store->publish_event_name($game, $move_b), 'existing event name is idempotent success';
    my @after = ($ftp->calls)[$before .. ($ftp->calls) - 1];

    is_deeply [ grep { $_->[0] =~ /\A(?:binary|put|rename)\z/ } @after ],
        [],
        'existing final event does not upload or rename again';

    no_forbidden_reads($ftp, 'rename publish did not use file-content or metadata reads');
};

subtest 'rename race treats an already-created final event as success' => sub {
    my $ftp = MockFTP->new(
        rename_hook => sub {
            my ($ftp, $source, $target) = @_;
            $ftp->create_file($target);
            return;
        },
    );
    my $store = GobanFTP::Store::FTP->new(ftp => $ftp);

    ok $store->mkdir($game), 'created game root';
    ok $store->publish_event_name($game, $move_w), 'rename failure with existing final is success';
    ok $store->exists_name("$game/events", $move_w), 'final event exists after rename race';

    no_forbidden_reads($ftp, 'rename race check uses listings only');
};

subtest 'rename failure uses bounded listing confirm without changing the event name' => sub {
    my $ftp = MockFTP->new(
        rename_hook => sub {
            my ($ftp, $source, $target) = @_;
            $ftp->schedule_create_file($target, after_listings => 2);
            $ftp->set_message('550 rename response lost');
            return;
        },
    );
    my $store = GobanFTP::Store::FTP->new(
        ftp                      => $ftp,
        publish_confirm_attempts => 3,
        publish_rename_attempts  => 1,
    );

    ok $store->mkdir($game), 'created game root';
    ok $store->publish_event_name($game, $move_w), 'delayed final event is confirmed through listings';
    ok $store->exists_name("$game/events", $move_w), 'final event exists after delayed confirm';

    my @rename_calls = grep { $_->[0] eq 'rename' } $ftp->calls;
    is scalar(@rename_calls), 1, 'rename was not retried when confirm found the target';
    is_deeply [ map { $_->[2] } @rename_calls ], [ "$game/events/$move_w" ],
        'confirm keeps the originally requested event name';

    no_forbidden_reads($ftp, 'delayed rename confirm uses listings only');
};

subtest 'rename failure is bounded and retries the same temp and target paths' => sub {
    my $ftp = MockFTP->new(
        rename_hook => sub {
            my ($ftp) = @_;
            $ftp->set_message('550 rename denied');
            return;
        },
    );
    my $store = GobanFTP::Store::FTP->new(
        ftp                      => $ftp,
        publish_confirm_attempts => 2,
        publish_rename_attempts  => 2,
    );

    my $tmp_path = "$game/tmp/alice-k31v-f98qai37nace5spg.part";
    my $target_path = "$game/events/$move_b";

    like exception(sub { $store->publish_event_name($game, $move_b) }),
        qr/rename \Q$tmp_path\E to \Q$target_path\E failed: 550 rename denied/,
        'rename failure reports the fixed temp and target paths';

    my @put_calls = grep { $_->[0] eq 'put' } $ftp->calls;
    my @rename_calls = grep { $_->[0] eq 'rename' } $ftp->calls;

    is scalar(@put_calls), 1, 'failed rename is not re-uploaded';
    is scalar(@rename_calls), 2, 'rename retry count is bounded';
    is_deeply [ map { $_->[1] } @rename_calls ], [ ($tmp_path) x 2 ],
        'rename retries the same temporary path';
    is_deeply [ map { $_->[2] } @rename_calls ], [ ($target_path) x 2 ],
        'rename retries the same event target';

    no_forbidden_reads($ftp, 'bounded rename retry does not use file-content or metadata reads');
};

subtest 'mkdir publish mode creates directory-shaped events without upload' => sub {
    my $ftp = MockFTP->new;
    my $store = GobanFTP::Store::FTP->new(ftp => $ftp, publish_mode => 'mkdir');

    ok $store->publish_event_name($game, $move_b), 'published event through mkdir mode';
    ok $store->exists_name("$game/events", $move_b), 'mkdir mode event is listed';
    is $ftp->entry_type("$game/events/$move_b"), 'dir', 'mkdir mode publishes a directory entry';

    my @write_ops = grep { $_->[0] =~ /\A(?:binary|put|rename)\z/ } $ftp->calls;
    is_deeply \@write_ops, [], 'mkdir mode does not upload or rename';
};

subtest 'list_names handles empty listings without treating missing paths as empty' => sub {
    my $empty_ftp = MockFTP->new(empty_list_message => '550 No files found');
    my $empty_store = GobanFTP::Store::FTP->new(ftp => $empty_ftp);

    ok $empty_store->mkdir("$game/events/empty"), 'created empty event child directory';
    is_deeply [ $empty_store->list_names("$game/events/empty") ], [],
        '550 no files is accepted as an empty directory listing';

    my $ftp = MockFTP->new(missing_message => '550 No such file or directory');
    my $store = GobanFTP::Store::FTP->new(ftp => $ftp);

    like exception(sub { $store->list_names('missing') }), qr/list missing failed: 550 No such/,
        '550 no such is surfaced as a missing path';

    my $missing_empty_ftp = MockFTP->new(missing_message => '550 No files found');
    my $missing_empty_store = GobanFTP::Store::FTP->new(ftp => $missing_empty_ftp);
    like exception(sub { $missing_empty_store->list_names('missing') }), qr/list missing failed: 550 No files found/,
        '550 no files is not accepted as empty for an unlisted path';
};

subtest 'list_names rejects partial listing rows with error replies' => sub {
    my $ftp = MockFTP->new(
        list_error_with_rows => ['partial'],
        list_error_message   => '426 Transfer aborted',
    );
    my $store = GobanFTP::Store::FTP->new(ftp => $ftp);

    like exception(sub { $store->list_names('') }), qr/list  failed: 426 Transfer aborted/,
        'partial rows plus an FTP error are not accepted as authoritative';
};

subtest 'absolute root and absolute listing prefixes are normalized to basenames' => sub {
    my $ftp = MockFTP->new(list_prefix => 'absolute');
    my $store = GobanFTP::Store::FTP->new(ftp => $ftp, root => '/mock-root');

    ok $store->publish_event_name($game, $move_b), 'published under an absolute FTP root';
    is_deeply [ $store->list_names('') ], [$game], 'absolute root listing strips root prefix';
    is_deeply [ $store->list_names($game) ], [qw(events tmp)], 'absolute child listing strips path prefix';
    is_deeply [ $store->list_names("$game/events") ], [$move_b], 'absolute event listing returns event basename';
};

subtest 'long listing output is parsed without using long-listing FTP commands' => sub {
    my $ftp = MockFTP->new(list_style => 'long', include_total => 1);
    my $store = GobanFTP::Store::FTP->new(ftp => $ftp, root => 'mock-root');

    $ftp->create_file("mock-root/$game/events/$move_b");
    $ftp->mkdir("mock-root/$game/tmp", 1);
    is_deeply [ $store->list_names($game) ], [qw(events tmp)], 'long game-root listing returns basenames';
    is_deeply [ $store->list_names("$game/events") ], [$move_b], 'long event listing returns event basename';

    my @forbidden = grep { $_->[0] =~ /\A(?:dir|list)\z/ } $ftp->calls;
    is_deeply \@forbidden, [], 'long-form output came through the normal listing method only';
};

subtest 'long listing parser accepts common Unix and DOS variants' => sub {
    my $unix_ftp = MockFTP->new(list_style => 'long_acl');
    my $unix_store = GobanFTP::Store::FTP->new(ftp => $unix_ftp);

    $unix_ftp->create_file("$game/events/$move_b");
    is_deeply [ $unix_store->list_names("$game/events") ], [$move_b],
        'Unix permission suffix is stripped before basename extraction';

    my $dos_ftp = MockFTP->new(list_style => 'dos');
    my $dos_store = GobanFTP::Store::FTP->new(ftp => $dos_ftp);

    $dos_ftp->create_file("$game/events/$move_w");
    is_deeply [ $dos_store->list_names("$game/events") ], [$move_w],
        'DOS listing with spaced AM/PM is parsed to the basename';
};

subtest 'exact confirmation does not trust long-listing compatibility parsing' => sub {
    my $ftp = MockFTP->new(list_style => 'long');
    my $store = GobanFTP::Store::FTP->new(ftp => $ftp);

    $ftp->create_file("$game/events/$move_b");
    is_deeply [ $store->list_names("$game/events") ], [$move_b],
        'compatibility listing still parses long listing rows';
    ok !$store->exists_name("$game/events", $move_b),
        'exact confirmation does not treat a long listing row as proof';
};

subtest 'temporary names include event id to avoid same player nonce collisions' => sub {
    my $ftp = MockFTP->new;
    my $store = GobanFTP::Store::FTP->new(ftp => $ftp);
    my $same_nonce_other_event = build_move_name(
        game_descriptor => $game,
        ply             => 1,
        color           => 'b',
        action          => 'play-ee',
        parent_id       => 'genesis',
        player          => 'alice',
        nonce           => 'k31v',
    );

    ok $store->publish_event_name($game, $move_b), 'published first same nonce event';
    ok $store->publish_event_name($game, $same_nonce_other_event), 'published second same nonce event';

    my @tmp_paths = map { $_->[2] } grep { $_->[0] eq 'put' } $ftp->calls;
    is scalar(@tmp_paths), 2, 'both publishes uploaded a temporary resource';
    isnt $tmp_paths[0], $tmp_paths[1], 'temporary resources differ by event id';
};

subtest 'listing entry and line size limits fail closed' => sub {
    my $entry_ftp = MockFTP->new;
    my $entry_store = GobanFTP::Store::FTP->new(ftp => $entry_ftp, max_listing_entries => 1);
    $entry_ftp->create_file("$game/events/$move_b");
    $entry_ftp->create_file("$game/events/$move_w");

    like exception(sub { $entry_store->list_names("$game/events") }),
        qr/list \Q$game\E\/events failed: listing entry limit exceeded/,
        'FTP listing entry count is bounded';

    my $line_ftp = MockFTP->new;
    my $line_store = GobanFTP::Store::FTP->new(ftp => $line_ftp, max_listing_line_bytes => 20);
    $line_ftp->create_file("$game/events/$move_b");

    like exception(sub { $line_store->list_names("$game/events") }),
        qr/list \Q$game\E\/events failed: listing line too long/,
        'FTP listing line length is bounded';
};

subtest 'mock timeout surfaces as stable listing failure' => sub {
    my $ftp = MockFTP->new(list_die => 'timeout waiting for directory data');
    my $store = GobanFTP::Store::FTP->new(ftp => $ftp);

    like exception(sub { $store->list_names('') }),
        qr/list  failed: timeout waiting for directory data/,
        'FTP timeout-like listing failure is surfaced without a real network call';
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
    my ($ftp, $description) = @_;

    my @forbidden = grep { $_->[0] =~ /\A(?:get|retr|size|mdtm|dir|list)\z/ } $ftp->calls;
    is_deeply \@forbidden, [], $description;
}

sub exception {
    my ($code) = @_;

    my $error;
    eval { $code->(); 1 } or $error = $@;

    return $error;
}

package MockFTP;

use v5.34;
use strict;
use warnings;

sub new {
    my ($class, %args) = @_;

    return bless {
        entries     => { '' => 'dir' },
        calls       => [],
        put_sizes   => [],
        rename_hook => $args{rename_hook},
        list_fail   => $args{list_fail},
        list_error_with_rows => $args{list_error_with_rows},
        list_error_message   => $args{list_error_message},
        list_die     => $args{list_die},
        list_style   => $args{list_style} // 'names',
        list_prefix  => $args{list_prefix} // 'relative',
        include_total => $args{include_total} // 0,
        empty_list_message => $args{empty_list_message},
        missing_message    => $args{missing_message} // '550 no such directory',
        scheduled_creates  => [],
        message     => '',
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

    $path = _canon($path);
    push @{ $self->{scheduled_creates} }, {
        path      => $path,
        parent    => _parent($path),
        remaining => $args{after_listings} // 1,
    };

    return 1;
}

sub set_message {
    my ($self, $message) = @_;
    $self->{message} = $message // '';
    return 1;
}

sub ls {
    my ($self, @args) = @_;

    $self->_record('ls', @args);

    if (defined $self->{list_error_with_rows}) {
        $self->{message} = $self->{list_error_message} // '426 Transfer aborted';
        return @{ $self->{list_error_with_rows} };
    }
    die $self->{list_die} if defined $self->{list_die};

    if ($self->{list_fail}) {
        $self->{message} = $self->{missing_message};
        return;
    }

    my $path = _canon($args[0] // '');
    $self->_apply_scheduled_creates($path);

    if (($self->{entries}{$path} // '') ne 'dir') {
        $self->{message} = $self->{missing_message};
        return;
    }

    my @children = sort
        map { _basename($_) }
        grep { $_ ne '' && _parent($_) eq $path }
        keys %{ $self->{entries} };

    $self->{message} = @children ? '' : ($self->{empty_list_message} // '');

    my @entries = map { $self->_listing_entry($path, $_) } @children;
    unshift @entries, 'total ' . scalar(@children)
        if @entries && $self->{include_total} && $self->{list_style} eq 'long';

    return @entries;
}

sub nlst { die 'low-level nlst should not be used by Store::FTP' }

sub mkdir {
    my ($self, $path, $recursive) = @_;

    $self->_record('mkdir', defined($recursive) ? ($path, $recursive) : ($path));

    $path = _canon($path);
    return '.' if $path eq '';

    my $parent = _parent($path);
    return if !$recursive && ($self->{entries}{$parent} // '') ne 'dir';

    $self->_mkdir_internal($path);
    return $path;
}

sub binary {
    my ($self) = @_;

    $self->_record('binary');
    return 1;
}

sub put {
    my ($self, $local, $remote) = @_;

    $self->_record('put', $local, $remote);

    $remote = _canon($remote);
    my $parent = _parent($remote);
    return if ($self->{entries}{$parent} // '') ne 'dir';

    push @{ $self->{put_sizes} }, -s $local;
    $self->{entries}{$remote} = 'file';

    return $remote;
}

sub rename {
    my ($self, $old, $new) = @_;

    $self->_record('rename', $old, $new);

    $old = _canon($old);
    $new = _canon($new);

    if (my $hook = $self->{rename_hook}) {
        return $hook->($self, $old, $new);
    }

    if (!exists $self->{entries}{$old}) {
        $self->{message} = '550 rename source missing';
        return;
    }
    if (exists $self->{entries}{$new}) {
        $self->{message} = '550 rename target exists';
        return;
    }
    if (($self->{entries}{ _parent($new) } // '') ne 'dir') {
        $self->{message} = '550 rename target parent missing';
        return;
    }

    $self->{entries}{$new} = delete $self->{entries}{$old};
    $self->{message} = '';
    return 1;
}

sub message {
    my ($self) = @_;
    return $self->{message};
}

sub get  { die 'forbidden get' }
sub retr { die 'forbidden retr' }
sub size { die 'forbidden size' }
sub mdtm { die 'forbidden mdtm' }
sub dir  { die 'forbidden dir' }
sub list { die 'forbidden list' }

sub _record {
    my ($self, @call) = @_;
    push @{ $self->{calls} }, \@call;
    return;
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

sub _listing_entry {
    my ($self, $parent, $name) = @_;

    my $path = $parent eq '' ? $name : "$parent/$name";
    my $listed_path = $self->{list_prefix} eq 'absolute' ? "/$path" : $path;

    return $listed_path if $self->{list_style} eq 'names';

    my $type = ($self->{entries}{$path} // '') eq 'dir' ? 'd' : '-';
    return sprintf '%srwxr-xr-x 1 owner group 0 Jan  1 00:00 %s', $type, $listed_path
        if $self->{list_style} eq 'long';
    return sprintf '%srwxr-xr-x+ 1 owner group 0 Jan  1 00:00 %s', $type, $listed_path
        if $self->{list_style} eq 'long_acl';
    return sprintf '01-01-2026  12:00 PM %s %s',
        (($self->{entries}{$path} // '') eq 'dir' ? '<DIR>' : '0'),
        $listed_path
        if $self->{list_style} eq 'dos';

    die "unknown mock list_style: $self->{list_style}";
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

sub _canon {
    my ($path) = @_;

    $path //= '';
    $path =~ s{\A\./+}{};
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

sub _basename {
    my ($path) = @_;

    $path = _canon($path);
    $path =~ s{\A.*/}{};
    return $path;
}
