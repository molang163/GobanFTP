use v5.34;
use strict;
use warnings;

use FindBin;
use JSON::PP qw(decode_json);
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::Board;
use GobanFTP::Rules;

my $fixture_dir = "$FindBin::Bin/fixtures/rules";

subtest 'simple ko is rejected by positional superko' => sub {
    my $case  = _read_json("$fixture_dir/ko.json");
    my $rules = GobanFTP::Rules->new(size => $case->{size});
    my $board = _board_from_rows($case->{rows});
    my $hash  = $rules->position_hash($board);
    my $state = {
        board              => $board,
        position_hash      => $hash,
        ancestor_hashes    => { $hash => 1 },
        consecutive_passes => 0,
        terminal           => 0,
        next_color         => 'b',
    };

    my $capture = $rules->apply_action($state,
        color  => $case->{first_move}{color},
        action => $case->{first_move}{action},
    );
    ok $capture->{ok}, 'ko capture is legal';
    is_deeply $capture->{captures}, $case->{first_move}{captures}, 'captured stone is reported';
    is_deeply _rows_from_board($capture->{board}), $case->{first_move}{expected_rows}, 'capture board';
    ok $capture->{ancestor_hashes}{$hash}, 'parent hash remains in ancestor set';

    my $recapture = $rules->apply_action($capture,
        color  => $case->{recapture}{color},
        action => $case->{recapture}{action},
    );
    ok !$recapture->{ok}, 'immediate recapture is illegal';
    is $recapture->{reason}, $case->{recapture}{reason}, 'recapture fails by superko';
    is_deeply $recapture->{captures}, [], 'superko rejection does not commit captures';
    is_deeply _rows_from_board($recapture->{board}), $case->{first_move}{expected_rows}, 'board stays at parent position';
};

subtest 'pass does not run positional superko check' => sub {
    my $rules = GobanFTP::Rules->new(size => 3);
    my $state = $rules->initial_state;
    ok $state->{ancestor_hashes}{ $state->{position_hash} }, 'initial position is already an ancestor';

    my $pass = $rules->apply_action($state, color => 'b', action => 'pass');
    ok $pass->{ok}, 'pass succeeds even though position repeats an ancestor';
    is $pass->{position_hash}, $state->{position_hash}, 'pass keeps repeated position';
};

done_testing;

sub _read_json {
    my ($path) = @_;

    open my $fh, '<:encoding(UTF-8)', $path or die "open $path: $!";
    local $/;
    my $json = <$fh>;
    close $fh or die "close $path: $!";

    return decode_json($json);
}

sub _board_from_rows {
    my ($rows) = @_;

    my $size  = @$rows;
    my $board = GobanFTP::Board->new(size => $size);
    for my $y (0 .. $size - 1) {
        my @stones = split //, $rows->[$y];
        for my $x (0 .. $#stones) {
            next if $stones[$x] == 0;
            $board->set($x, $y, $stones[$x]);
        }
    }

    return $board;
}

sub _rows_from_board {
    my ($board) = @_;

    my @cells = unpack 'C*', $board->canonical_bytes;
    my @rows;
    for my $y (0 .. $board->size - 1) {
        push @rows, join '', @cells[$y * $board->size .. ($y + 1) * $board->size - 1];
    }

    return \@rows;
}
