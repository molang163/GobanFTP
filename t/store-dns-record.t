use v5.34;
use strict;
use warnings;

use FindBin;
use File::Temp qw(tempfile);
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::EventSetRoot qw(event_set_root_result);
use GobanFTP::MovePublisher qw(build_move_name);

my $GAME = 'g1.id-dns-runtime.s9.r-chinese-area-v1.k7500.pb-alice.pw-bob';
my $OTHER_GAME = 'g1.id-dns-other.s9.r-chinese-area-v1.k7500.pb-alice.pw-bob';

my ($MOVE_B, $ID_B) = build_move_name(
    game_descriptor => $GAME,
    ply             => 1,
    color           => 'b',
    action          => 'play-dd',
    parent_id       => 'genesis',
    player          => 'alice',
    nonce           => 'dnsb',
);
my ($MOVE_W, $ID_W) = build_move_name(
    game_descriptor => $GAME,
    ply             => 2,
    color           => 'w',
    action          => 'play-ee',
    parent_id       => $ID_B,
    player          => 'bob',
    nonce           => 'dnsw',
);
my ($POISON_MOVE) = build_move_name(
    game_descriptor => $GAME,
    ply             => 3,
    color           => 'b',
    action          => 'pass',
    parent_id       => $ID_W,
    player          => 'alice',
    nonce           => 'dnsp',
);

my @EXPECTED_EVENTS = sort ($MOVE_B, $MOVE_W);
my $EXPECTED_ROOT = event_set_root_result(
    game_descriptor => $GAME,
    names           => \@EXPECTED_EVENTS,
)->{event_set_root};

subtest 'DNS record store admits only current-game TXT event rows' => sub {
    my @base_records = (
        "ttl=60 type=TXT owner=01.events.$GAME.example. event=$MOVE_B",
        "ttl=300 type=TXT owner=02.events.$GAME.example. event=\"$MOVE_W\"",
    );
    my $base = _new_store(records => \@base_records);
    return if !$base;

    _assert_runtime_admission($base, 'base TXT event rows');

    my $upper_game   = uc $GAME;
    my $upper_poison = uc $POISON_MOVE;
    my @noisy_records = (
        "ttl=3600 type=txt owner=02.events.$GAME.example. event=\"$MOVE_W\"",
        "ttl=1 type=TXT owner=01.events.$GAME.example. event=$MOVE_B",
        "ttl=10 type=TXT owner=01.duplicate.events.$GAME.example. event=$MOVE_B",
        "ttl=11 TyPe=Txt owner=01.EVENTS.$upper_game.EXAMPLE. event=\"$MOVE_B\"",
        "ttl=20 type=A owner=03.events.$GAME.example. event=$POISON_MOVE",
        "ttl=30 type=CNAME owner=03.events.$GAME.example. target=shadow.example.",
        "ttl=40 type=TXT owner=03.events.$OTHER_GAME.example. event=$POISON_MOVE",
        "ttl=50 type=TXT event=$POISON_MOVE",
        "ttl=60 type=TXT owner=sidecar.$GAME.example. event=$POISON_MOVE sidecar=$ID_B.sig",
        "ttl=70 type=TXT owner=projections.sgf.$GAME.example. event=$POISON_MOVE projection=sgf/main.sgf",
        "ttl=80 type=TXT owner=tmp.$GAME.example. event=$POISON_MOVE tmp=upload.part",
        "ttl=90 type=TXT owner=03.events.$GAME.example. sidecar=$ID_W.json",
        "ttl=100 type=TXT owner=04.events.$GAME.example. tmp=$POISON_MOVE",
        "ttl=110 type=TXT owner=05.events.$GAME.example. event=$upper_poison",
        "ttl=120 type=TXT owner=06.events.$GAME.example. event=events/$POISON_MOVE",
    );
    my $noisy = _new_store(records => \@noisy_records);
    return if !$noisy;

    _assert_runtime_admission($noisy, 'TTL/order/metadata noise');
};

subtest 'DNS record store is a read-only runtime source' => sub {
    my @records = (
        "ttl=60 type=TXT owner=01.events.$GAME.example. event=$MOVE_B",
        "ttl=60 type=TXT owner=02.events.$GAME.example. event=$MOVE_W",
    );
    my $store = _new_store(records => \@records);
    return if !$store;

    ok $store->exists_name("$GAME/events", $MOVE_B), 'exists_name sees an admitted event';
    ok !$store->exists_name("$GAME/events", $POISON_MOVE), 'exists_name rejects a missing event';

    like _dies(sub { $store->mkdir("$GAME/events") }), qr/read-only/,
        'mkdir is explicitly read-only';
    like _dies(sub { $store->publish_event_name($GAME, $POISON_MOVE) }), qr/read-only/,
        'publish_event_name is explicitly read-only';

    _assert_runtime_admission($store, 'read-only checks leave admission unchanged');
};

subtest 'DNS record parser rejects inline comment and duplicate-field poisoning' => sub {
    my @records = (
        "ttl=60 type=TXT owner=01.events.$GAME.example. event=$MOVE_B # type=TXT owner=03.events.$GAME.example. event=$POISON_MOVE",
        "ttl=61 type=TXT owner=02.events.$GAME.example. event=$MOVE_W",
        "ttl=62 type=A # type=TXT owner=04.events.$GAME.example. event=$POISON_MOVE",
        "ttl=63 type=A type=TXT owner=05.events.$GAME.example. event=$POISON_MOVE",
        "ttl=64 type=TXT owner=06.events.$GAME.example. event=$MOVE_B event=$POISON_MOVE",
        "ttl=65 type=TXT owner=07.events.$GAME.example. owner=08.events.$GAME.example. event=$POISON_MOVE",
    );
    my $store = _new_store(records => \@records);
    return if !$store;

    _assert_runtime_admission($store, 'comment and duplicate poison rows');
};

subtest 'DNS owner suffix scopes runtime admission' => sub {
    my @records = (
        "ttl=60 type=TXT owner=01.events.$GAME.example. event=$MOVE_B",
        "ttl=61 type=TXT owner=02.events.$GAME.example. event=$MOVE_W",
        "ttl=62 type=TXT owner=03.events.$GAME.example.evil. event=$POISON_MOVE",
    );
    my $store = _new_store(records => \@records, owner_suffix => 'example.');
    return if !$store;

    _assert_runtime_admission($store, 'owner_suffix scoped rows');
};

subtest 'DNS record input limits reject oversized inputs' => sub {
    like _dies(sub {
        my $store = _new_store(
            records => ["ttl=60 type=TXT owner=01.events.$GAME.example. event=$MOVE_B"],
            max_line_bytes => 24,
        );
        $store->list_names("$GAME/events");
    }), qr/dns record line too long/,
        'DNS record array rows have a line length limit';

    like _dies(sub {
        my $store = _new_store(
            records => [
                "ttl=60 type=TXT owner=01.events.$GAME.example. event=$MOVE_B",
                "ttl=61 type=TXT owner=02.events.$GAME.example. event=$MOVE_W",
            ],
            max_records => 1,
        );
        $store->list_names("$GAME/events");
    }), qr/dns record limit exceeded/,
        'DNS record arrays have a record count limit';

    like _dies(sub {
        my $store = _new_store(
            records => [
                '# comment',
                "ttl=60 type=TXT owner=01.events.$GAME.example. event=$MOVE_B",
            ],
            max_lines => 1,
        );
        $store->list_names("$GAME/events");
    }), qr/dns record line count exceeded/,
        'DNS record arrays have a physical line count limit';

    my ($fh, $path) = tempfile();
    print {$fh} 'x' x 32;
    close $fh or die "close $path: $!";

    like _dies(sub {
        my $store = _new_store(record_file => $path, max_file_bytes => 8);
        $store->list_names("$GAME/events");
    }), qr/dns record file too large/,
        'DNS record files have a byte-size limit before parsing';

    my ($line_fh, $line_path) = tempfile();
    print {$line_fh} "# comment\n";
    print {$line_fh} "ttl=60 type=TXT owner=01.events.$GAME.example. event=$MOVE_B\n";
    close $line_fh or die "close $line_path: $!";

    like _dies(sub {
        my $store = _new_store(record_file => $line_path, max_lines => 1);
        $store->list_names("$GAME/events");
    }), qr/dns record line count exceeded/,
        'DNS record files have a physical line count limit';
};

done_testing;

sub _assert_runtime_admission {
    my ($store, $label) = @_;

    my @events = $store->list_names("$GAME/events");
    is_deeply \@events, \@EXPECTED_EVENTS, "$label returns the accepted event basenames";

    my $root = event_set_root_result(
        game_descriptor => $GAME,
        names           => \@events,
    )->{event_set_root};
    is $root, $EXPECTED_ROOT, "$label preserves the accepted event-set root";
}

sub _new_store {
    state $loaded = require_ok('GobanFTP::Store::DNSRecord');
    return undef if !$loaded;

    return GobanFTP::Store::DNSRecord->new(@_);
}

sub _dies {
    my ($code) = @_;

    my $error = '';
    eval { $code->(); 1 } or $error = $@;
    return $error;
}
