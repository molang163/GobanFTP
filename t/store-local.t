use v5.34;
use strict;
use warnings;

use FindBin;
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

done_testing;

sub dies {
    my ($code) = @_;

    my $error;
    local $@;
    eval { $code->(); 1 } or $error = $@;

    return $error;
}
