use v5.34;
use strict;
use warnings;

use FindBin;
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::EventID qw(event_id);
use GobanFTP::MovePublisher qw(build_move_name);
use GobanFTP::Replay qw(replay);

my $GAME = 'g1.id-ack-assisted.s3.r-chinese-area-v1.k0.pb-alice.pw-bob';

subtest 'default replay remains conservative with a valid opponent ack' => sub {
    my ($left, $left_id) = _move(
        ply       => 1,
        color     => 'b',
        action    => 'play-aa',
        parent_id => 'genesis',
        nonce     => 'left',
    );
    my ($right, $right_id) = _move(
        ply       => 1,
        color     => 'b',
        action    => 'play-bb',
        parent_id => 'genesis',
        nonce     => 'right',
    );
    my ($ack_left, $ack_left_id) = _ack($left_id, 'bob', 'ackleft');

    my $result = replay(
        game_descriptor => $GAME,
        events          => [$left, $right, $ack_left],
    );

    is $result->{policy}, 'conservative', 'default policy is conservative';
    is_deeply $result->{canonical_ids}, [], 'default replay does not choose an acked fork child';
    is $result->{fork}{parent_id}, 'genesis', 'default replay still reports the fork';
    is_deeply $result->{fork}{child_ids}, [sort ($left_id, $right_id)], 'fork children are deterministic';
    is_deeply $result->{ack_ids_by_target}, { $left_id => [$ack_left_id] }, 'ack map is still exposed';
    is_deeply $result->{ack_assisted_choices}, [], 'conservative replay records no ack-assisted choices';
};

subtest 'ack-assisted chooses the only fork child with an opponent ack' => sub {
    my ($left, $left_id) = _move(
        ply       => 1,
        color     => 'b',
        action    => 'play-aa',
        parent_id => 'genesis',
        nonce     => 'left',
    );
    my ($right, $right_id) = _move(
        ply       => 1,
        color     => 'b',
        action    => 'play-bb',
        parent_id => 'genesis',
        nonce     => 'right',
    );
    my ($ack_left, $ack_left_id) = _ack($left_id, 'bob', 'ackleft');

    my $result = replay(
        game_descriptor => $GAME,
        events          => [$right, $ack_left, $left],
        policy          => 'ack-assisted',
    );

    is $result->{policy}, 'ack-assisted', 'policy is recorded';
    is_deeply $result->{diagnostics}, [], 'resolved fork has no diagnostics';
    is_deeply $result->{canonical_ids}, [$left_id], 'acked child is canonical';
    is_deeply [sort @{ $result->{legal_ids} }], [sort ($left_id, $right_id)], 'both fork children remain legal';
    is $result->{fork}, undef, 'resolved fork is not reported as unresolved';
    is $result->{final_state}{board}->stone_at('aa'), 1, 'chosen child state is replayed';
    is $result->{final_state}{board}->stone_at('bb'), 0, 'unchosen child is not committed';
    is_deeply $result->{ack_assisted_choices},
        [{
            parent_id => 'genesis',
            child_id  => $left_id,
            ack_ids   => [$ack_left_id],
        }],
        'policy choice records the ack that resolved the fork';
};

subtest 'ack-assisted leaves an unacked fork unresolved' => sub {
    my ($left, $left_id) = _move(
        ply       => 1,
        color     => 'b',
        action    => 'play-aa',
        parent_id => 'genesis',
        nonce     => 'left',
    );
    my ($right, $right_id) = _move(
        ply       => 1,
        color     => 'b',
        action    => 'play-bb',
        parent_id => 'genesis',
        nonce     => 'right',
    );

    my $result = replay(
        game_descriptor => $GAME,
        events          => [$left, $right],
        policy          => 'ack-assisted',
    );

    is_deeply $result->{canonical_ids}, [], 'no child is chosen';
    is $result->{fork}{parent_id}, 'genesis', 'fork remains visible';
    is_deeply $result->{fork}{child_ids}, [sort ($left_id, $right_id)], 'fork children are unchanged';
    is_deeply [map { $_->{code} } @{ $result->{diagnostics} }], ['fork'], 'unresolved fork is the only diagnostic';
};

subtest 'ack-assisted does not choose when competing children are acked' => sub {
    my ($left, $left_id) = _move(
        ply       => 1,
        color     => 'b',
        action    => 'play-aa',
        parent_id => 'genesis',
        nonce     => 'left',
    );
    my ($right, $right_id) = _move(
        ply       => 1,
        color     => 'b',
        action    => 'play-bb',
        parent_id => 'genesis',
        nonce     => 'right',
    );
    my ($ack_left) = _ack($left_id, 'bob', 'ackleft');
    my ($ack_right) = _ack($right_id, 'bob', 'ackright');

    my $result = replay(
        game_descriptor => $GAME,
        events          => [$left, $right, $ack_left, $ack_right],
        policy          => 'ack-assisted',
    );

    is_deeply $result->{canonical_ids}, [], 'ambiguous acked fork chooses neither child';
    is $result->{fork}{parent_id}, 'genesis', 'fork remains unresolved';
    is_deeply [map { $_->{code} } @{ $result->{diagnostics} }], ['fork'], 'ambiguous acked fork reports fork';
};

subtest 'same-player ack does not resolve a fork' => sub {
    my ($left, $left_id) = _move(
        ply       => 1,
        color     => 'b',
        action    => 'play-aa',
        parent_id => 'genesis',
        nonce     => 'left',
    );
    my ($right, $right_id) = _move(
        ply       => 1,
        color     => 'b',
        action    => 'play-bb',
        parent_id => 'genesis',
        nonce     => 'right',
    );
    my ($ack_left) = _ack($left_id, 'alice', 'selfack');

    my $result = replay(
        game_descriptor => $GAME,
        events          => [$left, $right, $ack_left],
        policy          => 'ack-assisted',
    );

    is_deeply $result->{canonical_ids}, [], 'same-player ack chooses no child';
    is $result->{fork}{parent_id}, 'genesis', 'fork remains unresolved';
    is_deeply [map { $_->{code} } @{ $result->{diagnostics} }], ['fork'], 'same-player ack is not a validation error';
};

subtest 'ack targeting an illegal move does not make that move legal' => sub {
    my ($root, $root_id) = _move(
        ply       => 1,
        color     => 'b',
        action    => 'play-aa',
        parent_id => 'genesis',
        nonce     => 'root',
    );
    my ($legal_child, $legal_child_id) = _move(
        ply       => 2,
        color     => 'w',
        action    => 'play-bb',
        parent_id => $root_id,
        nonce     => 'legal',
    );
    my ($illegal_child, $illegal_child_id) = _move(
        ply       => 2,
        color     => 'w',
        action    => 'play-aa',
        parent_id => $root_id,
        nonce     => 'occupied',
    );
    my ($ack_illegal) = _ack($illegal_child_id, 'alice', 'ackbad');

    my $result = replay(
        game_descriptor => $GAME,
        events          => [$root, $legal_child, $illegal_child, $ack_illegal],
        policy          => 'ack-assisted',
    );

    is_deeply $result->{canonical_ids}, [$root_id, $legal_child_id], 'legal child remains canonical';
    is_deeply $result->{legal_ids}, [$root_id, $legal_child_id], 'illegal target is not made legal by ack';
    is $result->{illegal_by_id}{$illegal_child_id}[0]{code}, 'illegal_move', 'illegal target remains illegal';
};

subtest 'ack-assisted continues after a resolved fork and stops at the next unresolved fork' => sub {
    my ($left, $left_id) = _move(
        ply       => 1,
        color     => 'b',
        action    => 'play-aa',
        parent_id => 'genesis',
        nonce     => 'left',
    );
    my ($right, $right_id) = _move(
        ply       => 1,
        color     => 'b',
        action    => 'play-bb',
        parent_id => 'genesis',
        nonce     => 'right',
    );
    my ($ack_left) = _ack($left_id, 'bob', 'ackleft');
    my ($next_left, $next_left_id) = _move(
        ply       => 2,
        color     => 'w',
        action    => 'play-ba',
        parent_id => $left_id,
        nonce     => 'nextleft',
    );
    my ($next_right, $next_right_id) = _move(
        ply       => 2,
        color     => 'w',
        action    => 'play-bb',
        parent_id => $left_id,
        nonce     => 'nextright',
    );

    my $result = replay(
        game_descriptor => $GAME,
        events          => [$left, $right, $ack_left, $next_left, $next_right],
        policy          => 'ack-assisted',
    );

    is_deeply $result->{canonical_ids}, [$left_id], 'replay continues through the resolved fork';
    is $result->{fork}{parent_id}, $left_id, 'next unresolved fork stops replay';
    is_deeply $result->{fork}{child_ids}, [sort ($next_left_id, $next_right_id)], 'second fork children are reported';
};

subtest 'ack-assisted preserves invalid ack diagnostics' => sub {
    my ($move, $move_id) = _move(
        ply       => 1,
        color     => 'b',
        action    => 'play-aa',
        parent_id => 'genesis',
        nonce     => 'root',
    );
    my ($ack_to_move, $ack_to_move_id) = _ack($move_id, 'bob', 'ackmove');
    my ($ack_to_ack) = _ack($ack_to_move_id, 'alice', 'ackack');
    my ($dangling_ack) = _ack('0000000000000000', 'alice', 'dangling');

    my $result = replay(
        game_descriptor => $GAME,
        events          => [$move, $ack_to_move, $ack_to_ack, $dangling_ack],
        policy          => 'ack-assisted',
    );

    my @codes = sort map { $_->{code} } @{ $result->{diagnostics} };
    is_deeply \@codes, [qw(ack_target_not_move dangling_ack_target)],
        'invalid ack targets remain validation diagnostics under ack-assisted policy';
    is_deeply $result->{canonical_ids}, [$move_id], 'invalid ack diagnostics do not alter move replay';
};

subtest 'ack-assisted accessors return copies' => sub {
    my ($left, $left_id) = _move(
        ply       => 1,
        color     => 'b',
        action    => 'play-aa',
        parent_id => 'genesis',
        nonce     => 'left',
    );
    my ($right) = _move(
        ply       => 1,
        color     => 'b',
        action    => 'play-bb',
        parent_id => 'genesis',
        nonce     => 'right',
    );
    my ($ack_left, $ack_left_id) = _ack($left_id, 'bob', 'ackleft');

    my $result = replay(
        game_descriptor => $GAME,
        events          => [$left, $right, $ack_left],
        policy          => 'ack-assisted',
    );

    my $acks = $result->ack_ids_by_target;
    my @choices = $result->ack_assisted_choices;
    $acks->{$left_id}[0] = 'mutated';
    $choices[0]{ack_ids}[0] = 'mutated';

    is $result->{ack_ids_by_target}{$left_id}[0], $ack_left_id,
        'ack_ids_by_target accessor does not expose internal storage';
    is $result->{ack_assisted_choices}[0]{ack_ids}[0], $ack_left_id,
        'ack_assisted_choices accessor does not expose internal storage';
};

done_testing;

sub _move {
    my (%args) = @_;

    my $color = $args{color};
    my $player = $args{player}
        // ($color eq 'b' ? 'alice' : $color eq 'w' ? 'bob' : undef);

    return build_move_name(
        game_descriptor => $GAME,
        %args,
        player => $player,
    );
}

sub _ack {
    my ($target_id, $player, $nonce) = @_;

    my $without_hash = "a1.t-$target_id.by-$player.n-$nonce";
    my $id = event_id($GAME, $without_hash);

    return ("$without_hash.h-$id", $id);
}
