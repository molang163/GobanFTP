use v5.34;
use strict;
use warnings;

use Digest::SHA qw(sha256_hex);
use FindBin;
use JSON::PP qw(decode_json);
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::Board;
use GobanFTP::Rules;

my $fixture_dir = "$FindBin::Bin/fixtures/rules";

subtest 'legal play copies parent board and hashes framed board bytes' => sub {
    my $rules  = GobanFTP::Rules->new(size => 3, rules => 'chinese-area-v1');
    my $state  = $rules->initial_state;
    my $result = $rules->apply_action($state, color => 'b', action => 'play-aa');

    ok $result->{ok}, 'play succeeds';
    is $result->{board}->stone_at('aa'), 1, 'black is stored as 1';
    is $state->{board}->stone_at('aa'), 0, 'parent board is not mutated';
    is_deeply $result->{captures}, [], 'ordinary play has no captures';
    is $result->{consecutive_passes}, 0, 'play clears pass count';
    is $result->{next_color}, 'w', 'turn advances to white';

    my $expected_hash = sha256_hex('GOFTP-BOARD/1' . "\0" . '3' . "\0" . $result->{board}->canonical_bytes);
    is $result->{position_hash}, $expected_hash, 'position hash uses RULES framing';
    ok $result->{ancestor_hashes}{ $result->{position_hash} }, 'new position enters ancestor set';
};

subtest 'occupied and bounds are rejected without committing' => sub {
    my $rules = GobanFTP::Rules->new(size => 3);
    my $after_black = $rules->apply_action($rules->initial_state, color => 'b', action => 'play-aa');

    my $occupied = $rules->apply_action($after_black, color => 'w', action => 'play-aa');
    ok !$occupied->{ok}, 'occupied move fails';
    is $occupied->{reason}, 'occupied', 'occupied reason';
    is $occupied->{board}->stone_at('aa'), 1, 'occupied rejection returns parent board';

    my $bounds = $rules->apply_action($after_black, color => 'w', action => 'play-dd');
    ok !$bounds->{ok}, 'out-of-bounds move fails';
    is $bounds->{reason}, 'coord.bounds', 'coord reason is surfaced';
};

subtest 'captures and suicide use full flood-fill' => sub {
    for my $case (_read_jsonl("$fixture_dir/play-cases.jsonl")) {
        my $rules = GobanFTP::Rules->new(size => $case->{size});
        my $board = _board_from_rows($case->{rows});
        my $hash  = $rules->position_hash($board);
        my $state = {
            board              => $board,
            position_hash      => $hash,
            ancestor_hashes    => { $hash => 1 },
            consecutive_passes => 0,
            terminal           => 0,
            next_color         => $case->{next_color},
        };

        my $result = $rules->apply_action($state, $case->{move});
        is !!$result->{ok}, !!$case->{ok}, "$case->{id}: ok";

        if ($case->{ok}) {
            is_deeply $result->{captures}, $case->{captures}, "$case->{id}: captures are row-major points";
        }
        else {
            is $result->{reason}, $case->{reason}, "$case->{id}: reason";
        }

        is_deeply _rows_from_board($result->{board}), $case->{expected_rows}, "$case->{id}: board";
    }
};

done_testing;

sub _read_jsonl {
    my ($path) = @_;

    open my $fh, '<:encoding(UTF-8)', $path or die "open $path: $!";
    my @cases;
    while (defined(my $line = <$fh>)) {
        chomp $line;
        next if $line =~ /\A\s*\z/;
        push @cases, decode_json($line);
    }
    close $fh or die "close $path: $!";

    return @cases;
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
