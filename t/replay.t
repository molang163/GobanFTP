use v5.34;
use strict;
use warnings;

use FindBin;
use JSON::PP qw(decode_json);
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::Event qw(from_name);
use GobanFTP::EventID qw(event_id);
use GobanFTP::Replay qw(replay);

my $game = 'g1.id-replay.s3.r-chinese-area-v1.k0.pb-alice.pw-bob';
my %event = _read_events("$FindBin::Bin/fixtures/replay/events.jsonl");

subtest 'legal chain replays to final state' => sub {
    my $result = replay(
        game_descriptor => $game,
        events          => _names(qw(chain_3 chain_1 chain_2)),
    );

    is_deeply $result->{diagnostics}, [], 'legal chain has no diagnostics';
    is_deeply $result->{canonical_ids}, _ids(qw(chain_1 chain_2 chain_3)), 'canonical line follows parent chain';
    is_deeply $result->{legal_ids}, _ids(qw(chain_1 chain_2 chain_3)), 'all moves are legal';

    is $result->{final_state}{board}->stone_at('aa'), 1, 'black stone is present';
    is $result->{final_state}{board}->stone_at('bb'), 2, 'white stone is present';
    is $result->{final_state}{next_color}, 'w', 'turn advanced after black pass';
};

subtest 'item names are accepted with parsed event payloads' => sub {
    my @items = map {
        my ($parsed, $error) = from_name($event{$_}{name}, game_descriptor => $game);
        die "$_: $error" if defined $error;
        +{
            name  => $event{$_}{name},
            event => $parsed,
        };
    } qw(chain_1 chain_2);

    my $result = replay(
        game_descriptor => $game,
        items           => \@items,
    );

    is_deeply $result->{diagnostics}, [], 'item names reparse cleanly';
    is_deeply $result->{canonical_ids}, _ids(qw(chain_1 chain_2)), 'canonical line comes from item names';
};

subtest 'unknown event versions are parse diagnostics' => sub {
    my $unknown = 'm2.p000001.b.play-aa.pa-genesis.by-alice.n-future.h-0000000000000000';
    my $result = replay(
        game_descriptor => $game,
        events          => [$unknown],
    );

    is_deeply $result->{diagnostics},
        [{
            code  => 'parse_event',
            name  => $unknown,
            error => 'event.version',
        }],
        'unknown event version is reported by the parser';
    is_deeply $result->{canonical_ids}, [], 'unknown event version does not enter canonical replay';
    is_deeply $result->{legal_ids}, [], 'unknown event version is not legal';
};

subtest 'rules diagnostics use stable error classes' => sub {
    my $bad_game = 'g1.id-replay.s3.r-made-up.k0.pb-alice.pw-bob';
    my $result = replay(
        game_descriptor => $bad_game,
        events          => [],
    );

    is_deeply $result->{diagnostics},
        [{
            code  => 'rules',
            error => 'rules.id',
        }],
        'rules constructor failures do not expose file or line details';
};

subtest 'ack publisher must be one of the game players' => sub {
    my $target = _id('chain_1');
    my $ack_without_hash = "a1.t-$target.by-charlie.n-outsider";
    my $ack = "$ack_without_hash.h-" . event_id($game, $ack_without_hash);

    my $result = replay(
        game_descriptor => $game,
        events          => [@{ _names(qw(chain_1)) }, $ack],
    );

    my @ack_diagnostics = grep { $_->{code} eq 'ack_wrong_player' } @{ $result->{diagnostics} };
    is scalar(@ack_diagnostics), 1, 'outsider ack is diagnosed';
    is $ack_diagnostics[0]{event_id}, _event_id_from_name($ack), 'ack event id is reported';
    is $ack_diagnostics[0]{player}, 'charlie', 'submitted ack player is reported';
    is $ack_diagnostics[0]{expected_player}, 'alice,bob', 'game players are reported';
    is_deeply $result->{canonical_ids}, _ids(qw(chain_1)), 'ack validation does not change canonical moves';
};

subtest 'illegal sibling does not block legal sibling' => sub {
    my $result = replay(
        game_descriptor => $game,
        events          => _names(qw(sibling_root sibling_occupied sibling_legal)),
    );

    is_deeply $result->{canonical_ids}, _ids(qw(sibling_root sibling_legal)), 'canonical chooses sole legal child';
    is_deeply $result->{legal_ids}, _ids(qw(sibling_root sibling_legal)), 'illegal sibling is not legal';

    my $illegal_id = _id('sibling_occupied');
    is $result->{illegal_by_id}{$illegal_id}[0]{code}, 'illegal_move', 'illegal sibling is recorded';
    is $result->{illegal_by_id}{$illegal_id}[0]{reason}, 'occupied', 'rule reason is preserved';
};

subtest 'wrong player color and ply are illegal' => sub {
    my $result = replay(
        game_descriptor => $game,
        events          => _names(qw(wrong_player wrong_color wrong_ply)),
    );

    is_deeply $result->{canonical_ids}, [], 'no invalid root enters canonical line';
    is_deeply $result->{legal_ids}, [], 'no invalid root is legal';

    is $result->{illegal_by_id}{ _id('wrong_player') }[0]{code}, 'wrong_player', 'black move must be by pb player';
    is $result->{illegal_by_id}{ _id('wrong_color') }[0]{code}, 'wrong_color', 'black moves first';
    is $result->{illegal_by_id}{ _id('wrong_ply') }[0]{code}, 'wrong_ply', 'ply follows parent depth';

    my @codes = sort { $a cmp $b } _codes($result);
    is_deeply \@codes, [qw(wrong_color wrong_player wrong_ply)], 'diagnostics expose each replay failure';
};

subtest 'two legal children report fork and stop canonical replay' => sub {
    my $result = replay(
        game_descriptor => $game,
        events          => _names(qw(fork_left fork_right)),
    );

    is_deeply $result->{canonical_ids}, [], 'fork roots are not chosen';
    is_deeply [sort @{ $result->{legal_ids} }], [sort @{ _ids(qw(fork_left fork_right)) }], 'both fork children are legal';

    is $result->{fork}{code}, 'fork', 'fork is exposed';
    is $result->{fork}{parent_id}, 'genesis', 'fork parent is genesis';
    is_deeply $result->{fork}{child_ids}, [sort @{ _ids(qw(fork_left fork_right)) }], 'fork children are deterministic';
    is_deeply [_codes($result)], ['fork'], 'fork is also diagnostic';

    is $result->{final_state}{board}->stone_at('aa'), 0, 'final state remains at fork parent';
    is $result->{final_state}{board}->stone_at('bb'), 0, 'neither fork child is committed';
};

subtest 'missing parent comes from DAG diagnostics' => sub {
    my $result = replay(
        game_descriptor => $game,
        events          => _names(qw(missing_parent)),
    );

    is_deeply $result->{canonical_ids}, [], 'missing parent cannot be canonical';
    is_deeply $result->{legal_ids}, [], 'missing parent is not replayed';

    is_deeply $result->{diagnostics},
        [{
            code      => 'missing_parent',
            event_id  => _id('missing_parent'),
            parent_id => '9999999999999999',
        }],
        'DAG missing_parent diagnostic is surfaced unchanged';
    ok !exists $result->{illegal_by_id}{ _id('missing_parent') }, 'DAG-invalid move is not replay-classified';
};

done_testing;

sub _read_events {
    my ($path) = @_;

    open my $fh, '<:encoding(UTF-8)', $path or die "open $path: $!";
    my %events;
    while (my $line = <$fh>) {
        chomp $line;
        next if $line =~ /\A\s*\z/;

        my $row = decode_json($line);
        $row->{event_id} = _event_id_from_name($row->{name});
        $events{ $row->{id} } = $row;
    }
    close $fh or die "close $path: $!";

    return %events;
}

sub _names {
    return [map { $event{$_}{name} } @_];
}

sub _ids {
    return [map { _id($_) } @_];
}

sub _id {
    my ($label) = @_;
    return $event{$label}{event_id};
}

sub _codes {
    my ($result) = @_;
    return map { $_->{code} } @{ $result->{diagnostics} };
}

sub _event_id_from_name {
    my ($name) = @_;
    die "bad fixture name: $name" if $name !~ /\.h-([0-9a-v]{16})\z/;
    return $1;
}
