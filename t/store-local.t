use v5.34;
use strict;
use warnings;

use FindBin;
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::Store::Local;

my $root  = tempdir(CLEANUP => 1);
my $store = GobanFTP::Store::Local->new(root => $root);

my $game = 'g1.id-local-test.s9.r-chinese-area-v1.k7500.pb-alice.pw-bob';
my $move_b = 'm1.p000001.b.play-dd.pa-genesis.by-alice.n-k31v.h-f98qai37nace5spg';
my $move_w = 'm1.p000002.w.play-ee.pa-f98qai37nace5spg.by-bob.n-q9az.h-5ivvsvtid3j6u1pg';
my $ack    = 'a1.t-f98qai37nace5spg.by-bob.n-s7p2.h-tim1sb5lpmd0d4q5';

isa_ok $store, 'GobanFTP::Store::Local';

$store->mkdir("$game/tmp");
$store->publish_event_name($game, $move_w);
$store->publish_event_name($game, $move_b);
$store->publish_event_name($game, $ack);

ok -d "$root/$game/tmp", 'mkdir creates a local directory path';
ok -d "$root/$game/events", 'publish_event_name creates the local events directory';

is_deeply
    [ $store->list_names('') ],
    [$game],
    'root listing returns direct game root basename';

is_deeply
    [ $store->list_names($game) ],
    [qw(events tmp)],
    'game root listing returns sorted direct child basenames';

is_deeply
    [ $store->list_names("$game/events") ],
    [$ack, $move_b, $move_w],
    'events listing returns stable sorted event basenames';

ok $store->exists_name($game, 'events'), 'exists_name finds direct child directory';
ok $store->exists_name("$game/events", $move_b), 'exists_name finds direct child event';
ok !$store->exists_name("$game/events", 'missing-event'), 'exists_name is false for a missing child';

ok -f "$root/$game/events/$move_b", 'publish_event_name creates an event file';
is -s "$root/$game/events/$move_b", 0, 'published event file is zero bytes';

my $preexisting = 'm1.p000003.b.pass.pa-5ivvsvtid3j6u1pg.by-alice.n-keep.h-0000000000000000';
open my $fh, '>', "$root/$game/events/$preexisting" or die "create preexisting event: $!";
print {$fh} "ignored bytes\n";
close $fh or die "close preexisting event: $!";

my $size_before = -s "$root/$game/events/$preexisting";
$store->publish_event_name($game, $preexisting);
is -s "$root/$game/events/$preexisting", $size_before,
    'publishing an existing event does not read or truncate its bytes';

$store->mkdir("$game/events/dir-event");
ok -d "$root/$game/events/dir-event", 'mkdir can create a local directory-shaped event entry';
is_deeply
    [ $store->list_names("$game/events/dir-event") ],
    [],
    'list_names returns direct children only';
ok $store->exists_name("$game/events", 'dir-event'), 'directory entries are names too';

like dies(sub { $store->list_names('../outside') }), qr/path must be relative|dot/,
    'relative path traversal is rejected';
like dies(sub { $store->exists_name($game, '../outside') }), qr/basename|dot/,
    'child name traversal is rejected';

subtest 'mkdir rejects symlinked game root' => sub {
    my $root = tempdir(CLEANUP => 1);
    my $outside = tempdir(CLEANUP => 1);
    my $game_root = File::Spec->catdir($root, $game);
    make_symlink_or_skip($outside, $game_root);

    my $store = GobanFTP::Store::Local->new(root => $root);
    like dies(sub { $store->mkdir("$game/events") }), qr/symlink/,
        'symlinked game root is rejected during mkdir';
    ok !-e File::Spec->catdir($outside, 'events'), 'outside events directory was not created';
};

subtest 'mkdir rejects symlinked child directories' => sub {
    my $root = tempdir(CLEANUP => 1);
    my $outside = tempdir(CLEANUP => 1);
    my $game_root = File::Spec->catdir($root, $game);
    make_path($game_root);

    my $events = File::Spec->catdir($game_root, 'events');
    make_symlink_or_skip($outside, $events);

    my $store = GobanFTP::Store::Local->new(root => $root);
    like dies(sub { $store->mkdir("$game/events/tmp") }), qr/symlink/,
        'symlinked intermediate directory is rejected during mkdir';
    ok !-e File::Spec->catdir($outside, 'tmp'), 'outside tmp directory was not created';

    my $root2 = tempdir(CLEANUP => 1);
    my $outside2 = tempdir(CLEANUP => 1);
    my $events2 = File::Spec->catdir($root2, $game, 'events');
    make_path($events2);
    my $tmp = File::Spec->catdir($events2, 'tmp');
    make_symlink_or_skip($outside2, $tmp);

    my $store2 = GobanFTP::Store::Local->new(root => $root2);
    like dies(sub { $store2->mkdir("$game/events/tmp/nested") }), qr/symlink/,
        'symlinked leaf directory is rejected during mkdir';
    ok !-e File::Spec->catdir($outside2, 'nested'), 'outside nested directory was not created';
};

subtest 'list_names rejects symlinked local paths' => sub {
    my $root = tempdir(CLEANUP => 1);
    my $outside = tempdir(CLEANUP => 1);
    open my $fh, '>', File::Spec->catfile($outside, 'leaked') or die "create leaked file: $!";
    close $fh or die "close leaked file: $!";

    make_symlink_or_skip($outside, File::Spec->catdir($root, $game));

    my $store = GobanFTP::Store::Local->new(root => $root);
    like dies(sub { $store->list_names($game) }), qr/symlink/,
        'symlinked game root is rejected during listing';

    my $root2 = tempdir(CLEANUP => 1);
    my $outside2 = tempdir(CLEANUP => 1);
    my $game_root2 = File::Spec->catdir($root2, $game);
    make_path($game_root2);
    make_symlink_or_skip($outside2, File::Spec->catdir($game_root2, 'events'));

    my $store2 = GobanFTP::Store::Local->new(root => $root2);
    like dies(sub { $store2->list_names("$game/events") }), qr/symlink/,
        'symlinked events directory is rejected during listing';
};

subtest 'exists_name rejects symlinked local paths' => sub {
    my $root = tempdir(CLEANUP => 1);
    my $outside = tempdir(CLEANUP => 1);
    make_symlink_or_skip($outside, File::Spec->catdir($root, $game));

    my $store = GobanFTP::Store::Local->new(root => $root);
    like dies(sub { $store->exists_name($game, 'events') }), qr/symlink/,
        'symlinked parent is rejected during exists_name';

    my $root2 = tempdir(CLEANUP => 1);
    my $outside_file = File::Spec->catfile(tempdir(CLEANUP => 1), 'outside-event');
    open my $fh, '>', $outside_file or die "create outside event: $!";
    close $fh or die "close outside event: $!";

    my $events = File::Spec->catdir($root2, $game, 'events');
    make_path($events);
    make_symlink_or_skip($outside_file, File::Spec->catfile($events, $move_b));

    my $store2 = GobanFTP::Store::Local->new(root => $root2);
    like dies(sub { $store2->exists_name("$game/events", $move_b) }), qr/symlink/,
        'symlinked child is rejected during exists_name';
};

subtest 'publish_event_name rejects symlinked game root' => sub {
    my $root = tempdir(CLEANUP => 1);
    my $outside = tempdir(CLEANUP => 1);
    make_symlink_or_skip($outside, File::Spec->catdir($root, $game));

    my $store = GobanFTP::Store::Local->new(root => $root);
    like dies(sub { $store->publish_event_name($game, $move_b) }), qr/symlink/,
        'symlinked game root is rejected during publish';
    ok !-e File::Spec->catdir($outside, 'events'), 'outside events directory was not created';
};

subtest 'publish_event_name rejects symlinked events directory' => sub {
    my $root = tempdir(CLEANUP => 1);
    my $outside = tempdir(CLEANUP => 1);
    my $game_root = File::Spec->catdir($root, $game);
    make_path($game_root);

    my $events = File::Spec->catdir($game_root, 'events');
    make_symlink_or_skip($outside, $events);

    my $store = GobanFTP::Store::Local->new(root => $root);
    like dies(sub { $store->publish_event_name($game, $move_b) }), qr/symlink/,
        'symlinked events directory is rejected';
    ok !-e File::Spec->catfile($outside, $move_b), 'outside target was not written';
};

subtest 'publish_event_name rejects symlinked event leaf' => sub {
    my $root = tempdir(CLEANUP => 1);
    my $outside = tempdir(CLEANUP => 1);
    my $game_root = File::Spec->catdir($root, $game);
    my $events = File::Spec->catdir($game_root, 'events');
    make_path($events);

    my $outside_event = File::Spec->catfile($outside, 'outside-event');
    open my $fh, '>', $outside_event or die "create outside event: $!";
    print {$fh} "sentinel\n";
    close $fh or die "close outside event: $!";

    make_symlink_or_skip($outside_event, File::Spec->catfile($events, $move_b));

    my $store = GobanFTP::Store::Local->new(root => $root);
    like dies(sub { $store->publish_event_name($game, $move_b) }), qr/symlink/,
        'symlinked event leaf is rejected';
    is -s $outside_event, length("sentinel\n"), 'outside event was not truncated';
};

done_testing;

sub dies {
    my ($code) = @_;

    my $error;
    local $@;
    eval { $code->(); 1 } or $error = $@;

    return $error;
}

sub make_symlink_or_skip {
    my ($target, $link) = @_;

    if (!eval { symlink $target, $link }) {
        my $message = "symlink unavailable on this platform: $!";
        BAIL_OUT($message) if $ENV{GOBANFTP_REQUIRE_SYMLINK_TESTS};
        plan skip_all => $message;
    }

    if (!-l $link) {
        my $message = "symlink did not create an lstat-visible link: $link";
        BAIL_OUT($message) if $ENV{GOBANFTP_REQUIRE_SYMLINK_TESTS};
        plan skip_all => $message;
    }

    return 1;
}
