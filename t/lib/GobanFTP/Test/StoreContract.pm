package GobanFTP::Test::StoreContract;

use v5.34;
use strict;
use warnings;

use Exporter qw(import);
use Test::More;

our @EXPORT_OK = qw(run_store_contract);

my $DEFAULT_GAME = 'g1.id-store-contract.s9.r-chinese-area-v1.k7500.pb-alice.pw-bob';
my $MOVE_B = 'm1.p000001.b.play-dd.pa-genesis.by-alice.n-k31v.h-f98qai37nace5spg';
my $MOVE_W = 'm1.p000002.w.play-ee.pa-f98qai37nace5spg.by-bob.n-q9az.h-5ivvsvtid3j6u1pg';
my $ACK    = 'a1.t-f98qai37nace5spg.by-bob.n-s7p2.h-tim1sb5lpmd0d4q5';
my $PASS   = 'm1.p000003.b.pass.pa-5ivvsvtid3j6u1pg.by-alice.n-keep.h-0000000000000000';

sub run_store_contract {
    my (%args) = @_;

    my $store = $args{store} or die 'store is required';
    my $label = $args{name} // ref($store) // 'store';
    my $game  = $args{game} // $DEFAULT_GAME;
    my $strict_root_listing = exists $args{strict_root_listing} ? $args{strict_root_listing} : 1;

    subtest "$label store contract" => sub {
        isa_ok $store, 'GobanFTP::Store';

        ok $store->mkdir($game),          'mkdir creates the game root';
        ok $store->mkdir("$game/tmp"),    'mkdir creates nested directories';
        ok $store->mkdir("$game/sidecar"), 'mkdir is reusable for non-event children';

        if ($strict_root_listing) {
            names_are(
                [ $store->list_names('') ],
                [$game],
                'list_names returns direct child basenames at root',
            );
        }
        else {
            ok((grep { $_ eq $game } $store->list_names('')), 'list_names includes the game root child');
        }

        ok $store->exists_name('', $game), 'exists_name finds a direct root child';
        ok !$store->exists_name('', "$game-missing"), 'exists_name is false for a missing root child';

        ok $store->publish_event_name($game, $MOVE_W), 'publish_event_name publishes an event basename';
        ok $store->publish_event_name($game, $MOVE_B), 'publish_event_name publishes a second event basename';
        ok $store->publish_event_name($game, $ACK),    'publish_event_name publishes ack basenames too';

        names_are(
            [ $store->list_names($game) ],
            [qw(events sidecar tmp)],
            'game root listing contains direct child basenames only',
        );

        names_are(
            [ $store->list_names("$game/events") ],
            [$ACK, $MOVE_B, $MOVE_W],
            'events listing contains published event basenames',
        );

        ok $store->exists_name($game, 'events'), 'exists_name finds direct child directories';
        ok $store->exists_name("$game/events", $MOVE_B), 'exists_name finds direct child events';
        ok !$store->exists_name("$game/events", 'missing-event'), 'exists_name is false for a missing event';
        ok !$store->exists_name($game, $MOVE_B), 'exists_name does not match recursive descendants';

        ok $store->publish_event_name($game, $MOVE_B), 'publishing the same event name is idempotent';
        names_are(
            [ $store->list_names("$game/events") ],
            [$ACK, $MOVE_B, $MOVE_W],
            'idempotent publish does not add duplicate names',
        );

        ok $store->mkdir("$game/events/dir-event"), 'mkdir may publish a directory-shaped event name';
        names_are(
            [ $store->list_names("$game/events") ],
            [$ACK, 'dir-event', $MOVE_B, $MOVE_W],
            'directory entries are visible as names',
        );
        names_are(
            [ $store->list_names("$game/events/dir-event") ],
            [],
            'list_names returns direct children only for an empty child directory',
        );
        ok $store->exists_name("$game/events", 'dir-event'), 'exists_name sees directory entries as names';

        like dies(sub { $store->list_names('../outside') }), qr/path must be relative|dot/,
            'relative path traversal is rejected';
        like dies(sub { $store->mkdir('../outside') }), qr/path must be relative|dot/,
            'mkdir path traversal is rejected';
        like dies(sub { $store->exists_name($game, '../outside') }), qr/basename|dot/,
            'exists_name child traversal is rejected';
        like dies(sub { $store->publish_event_name($game, "../$PASS") }), qr/basename|dot/,
            'publish_event_name requires an event basename';
    };

    return 1;
}

sub names_are {
    my ($got, $expected, $description) = @_;

    is_deeply [ sort @$got ], [ sort @$expected ], $description;
    is scalar(@$got), scalar(keys %{ { map { $_ => 1 } @$got } }),
        "$description has no duplicate names";
}

sub dies {
    my ($code) = @_;

    my $error;
    local $@;
    eval { $code->(); 1 } or $error = $@;

    return $error;
}

1;
