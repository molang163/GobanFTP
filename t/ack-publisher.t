use v5.34;
use strict;
use warnings;

use FindBin;
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::AckPublisher qw(build_ack_for_target build_ack_name);
use GobanFTP::EventID qw(event_id);
use GobanFTP::MovePublisher qw(build_move_name);
use GobanFTP::Replay qw(replay);

my $GAME = 'g1.id-ackpub.s3.r-chinese-area-v1.k0.pb-alice.pw-bob';

subtest 'build_ack_name uses the EventID hash' => sub {
    my ($move, $move_id) = _move(
        ply       => 1,
        color     => 'b',
        action    => 'play-aa',
        parent_id => 'genesis',
        nonce     => 'target',
    );
    my ($ack, $ack_id) = build_ack_name(
        game_descriptor => $GAME,
        target_id       => $move_id,
        player          => 'bob',
        nonce           => 'ack1',
    );

    my ($without_hash) = $ack =~ /\A(.+)\.h-[0-9a-v]{16}\z/;
    is $ack_id, event_id($GAME, $without_hash), 'ack event id comes from GobanFTP::EventID';
    is $ack, "$without_hash.h-$ack_id", 'ack name appends the EventID value';
    like $ack, qr/\Aa1\.t-\Q$move_id\E\.by-bob\.n-ack1\.h-[0-9a-v]{16}\z/, 'ack fields are encoded';
};

subtest 'build_ack_for_target derives the opponent player' => sub {
    my ($black_move, $black_id) = _move(
        ply       => 1,
        color     => 'b',
        action    => 'play-aa',
        parent_id => 'genesis',
        nonce     => 'black',
    );
    my ($white_move, $white_id) = _move(
        ply       => 2,
        color     => 'w',
        action    => 'play-bb',
        parent_id => $black_id,
        nonce     => 'white',
    );
    my $result = replay(
        game_descriptor => $GAME,
        events          => [$black_move, $white_move],
    );

    my ($black_ack) = build_ack_for_target(
        game_descriptor => $GAME,
        replay_result   => $result,
        target_id       => $black_id,
        nonce           => 'ackblack',
    );
    my ($white_ack) = build_ack_for_target(
        game_descriptor => $GAME,
        replay_result   => $result,
        target_id       => $white_id,
        nonce           => 'ackwhite',
    );

    like $black_ack, qr/\Aa1\.t-\Q$black_id\E\.by-bob\.n-ackblack\.h-[0-9a-v]{16}\z/,
        'black move is acked by white player';
    like $white_ack, qr/\Aa1\.t-\Q$white_id\E\.by-alice\.n-ackwhite\.h-[0-9a-v]{16}\z/,
        'white move is acked by black player';
};

subtest 'build_ack_for_target rejects unknown illegal or non-move targets' => sub {
    my ($root, $root_id) = _move(
        ply       => 1,
        color     => 'b',
        action    => 'play-aa',
        parent_id => 'genesis',
        nonce     => 'root',
    );
    my ($illegal, $illegal_id) = _move(
        ply       => 2,
        color     => 'w',
        action    => 'play-aa',
        parent_id => $root_id,
        nonce     => 'illegal',
    );
    my ($ack, $ack_id) = build_ack_name(
        game_descriptor => $GAME,
        target_id       => $root_id,
        player          => 'bob',
        nonce           => 'knownack',
    );
    my $result = replay(
        game_descriptor => $GAME,
        events          => [$root, $illegal, $ack],
    );

    like exception(sub {
        build_ack_for_target(
            game_descriptor => $GAME,
            replay_result   => $result,
            target_id       => '0000000000000000',
            nonce           => 'unknown',
        );
    }), qr/\Aack\.target\b/, 'unknown target is rejected';

    like exception(sub {
        build_ack_for_target(
            game_descriptor => $GAME,
            replay_result   => $result,
            target_id       => $illegal_id,
            nonce           => 'illegal',
        );
    }), qr/\Aack\.target_legal\b/, 'illegal move target is rejected';

    like exception(sub {
        build_ack_for_target(
            game_descriptor => $GAME,
            replay_result   => $result,
            target_id       => $ack_id,
            nonce           => 'acktarget',
        );
    }), qr/\Aack\.target_move\b/, 'ack target that is itself an ack is rejected';
};

subtest 'builder validates ack fields' => sub {
    my (undef, $target_id) = _move(
        ply       => 1,
        color     => 'b',
        action    => 'play-aa',
        parent_id => 'genesis',
        nonce     => 'target',
    );

    like exception(sub {
        build_ack_name(
            game_descriptor => $GAME,
            target_id       => $target_id,
            player          => 'Bob',
            nonce           => 'ack',
        );
    }), qr/\Aevent\.player\b/, 'player grammar is enforced';

    like exception(sub {
        build_ack_name(
            game_descriptor => $GAME,
            target_id       => $target_id,
            player          => 'bob',
            nonce           => 'too.long.for.ack',
        );
    }), qr/\Aevent\.nonce\b/, 'nonce grammar is enforced';
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

sub exception {
    my ($code) = @_;

    my $error;
    eval { $code->(); 1 } or $error = $@;

    return $error;
}
