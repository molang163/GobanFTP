use v5.34;
use strict;
use warnings;

use FindBin;
use Test::More;

use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/lib";

use GobanFTP::Coord qw(index_to_point);
use GobanFTP::Test::RulesMechanics qw(
    assert_c_matches_perl_mechanics
    rows_from_bytes
    skip_unless_c_available
);

skip_unless_c_available('rules C random equivalence');

my $seed_input = $ENV{GOBANFTP_RULES_RANDOM_SEED} // 'gobanftp-rules-c-v1';
my $stress     = $ENV{GOBANFTP_RULES_RANDOM_STRESS} ? 1 : 0;
my $trials     = _env_uint(
    'GOBANFTP_RULES_RANDOM_TRIALS',
    $ENV{GOBANFTP_RULES_RANDOM_TRIALS} // ($stress ? 2000 : 200),
);
my $state = _seed_value($seed_input);

diag "rules random seed=$seed_input state=$state trials=$trials stress=$stress";

subtest 'C mechanics matches Perl mechanics for seeded random boards' => sub {
    my %seen_size;
    my %seen_result;
    for my $trial (1 .. $trials) {
        my $case = _random_case(\$state, $trial, $stress);
        my ($perl) = assert_c_matches_perl_mechanics($case, $case->{id});
        $seen_size{ $case->{size} } = 1;
        if ($perl->{ok}) {
            $seen_result{legal} = 1;
            $seen_result{capture} = 1 if @{ $perl->{captures} };
        }
        else {
            $seen_result{ $perl->{reason} } = 1;
        }
    }

    my @expected_sizes = $stress ? (2 .. 26) : (2, 3, 4, 5, 9, 13, 19, 26);
    if ($trials >= @expected_sizes) {
        is_deeply [ sort { $a <=> $b } keys %seen_size ], \@expected_sizes,
            'random equivalence covered every configured board size';
    }

    for my $category (qw(legal capture suicide)) {
        ok $seen_result{$category}, "random equivalence covered $category mechanics";
    }
};

done_testing;

sub _random_case {
    my ($state_ref, $trial, $stress) = @_;

    my @sizes = $stress ? (2 .. 26) : (2, 3, 4, 5, 9, 13, 19, 26);
    return _coverage_case($trial) if $trial <= 3;

    my $size  = $sizes[ ($trial - 1) % @sizes ];
    my $total = $size * $size;
    my $index = _rand_int($state_ref, $total);
    my $stone = _rand_int($state_ref, 2) + 1;
    my @cells;

    for (1 .. $total) {
        my $roll = _rand_int($state_ref, 100);
        push @cells, $roll < 44 ? 0 : $roll < 72 ? 1 : 2;
    }

    if ($trial % 3 == 0) {
        $cells[$index] = 0;
    }
    elsif ($trial % 7 == 0) {
        $cells[$index] = $stone;
    }

    my $point = index_to_point($index, $size);
    my $color = $stone == 1 ? 'b' : 'w';

    return {
        id   => "random_${trial}_s${size}_${point}",
        size => $size,
        rows => rows_from_bytes($size, pack('C*', @cells)),
        move => {
            color  => $color,
            action => "play-$point",
        },
    };
}

sub _coverage_case {
    my ($trial) = @_;

    return {
        id   => 'coverage_legal_s2_aa',
        size => 2,
        rows => [ '00', '00' ],
        move => {
            color  => 'b',
            action => 'play-aa',
        },
    } if $trial == 1;

    return {
        id   => 'coverage_suicide_s3_bb',
        size => 3,
        rows => [ '020', '202', '020' ],
        move => {
            color  => 'b',
            action => 'play-bb',
        },
    } if $trial == 2;

    return {
        id   => 'coverage_capture_s4_ba',
        size => 4,
        rows => [ '0000', '1210', '0100', '0000' ],
        move => {
            color  => 'b',
            action => 'play-ba',
        },
    };
}

sub _env_uint {
    my ($name, $value) = @_;

    die "$name must be a positive integer\n"
        if !defined($value) || $value !~ /\A[1-9][0-9]*\z/;

    return 0 + $value;
}

sub _seed_value {
    my ($seed) = @_;

    return 0 + $seed if defined($seed) && $seed =~ /\A[0-9]+\z/;

    my $hash = 2166136261;
    for my $byte (unpack 'C*', $seed // '') {
        $hash ^= $byte;
        $hash = ($hash * 16777619) & 0xffffffff;
    }

    return $hash || 1;
}

sub _rand_u32 {
    my ($state_ref) = @_;

    $$state_ref = (1664525 * $$state_ref + 1013904223) & 0xffffffff;
    return $$state_ref;
}

sub _rand_int {
    my ($state_ref, $limit) = @_;

    return _rand_u32($state_ref) % $limit;
}
