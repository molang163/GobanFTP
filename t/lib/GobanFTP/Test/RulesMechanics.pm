package GobanFTP::Test::RulesMechanics;

use v5.34;
use strict;
use warnings;

use Carp qw(croak);
use Exporter qw(import);
use JSON::PP qw(decode_json);
use Test::More ();

use GobanFTP::Board;
use GobanFTP::Coord qw(point_to_index);
use GobanFTP::Rules;
use GobanFTP::Rules::C;

our @EXPORT_OK = qw(
    apply_case
    apply_mechanics_case
    assert_c_matches_perl_case
    assert_c_matches_perl_mechanics
    assert_case_expected
    board_from_rows
    bytes_from_rows
    read_jsonl
    rows_from_board
    rows_from_bytes
    skip_unless_c_available
    state_for_case
);

sub skip_unless_c_available {
    my ($purpose) = @_;

    my $status = GobanFTP::Rules::C->status;
    return if $status->{available};

    my $error = $status->{error} // 'unknown error';
    Test::More::plan(skip_all => "$purpose requires Rules::C: $error");
}

sub read_jsonl {
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

sub bytes_from_rows {
    my ($rows) = @_;

    croak 'rules.test.rows' if ref($rows) ne 'ARRAY' || !@$rows;

    my $size = @$rows;
    my @cells;
    for my $row (@$rows) {
        croak 'rules.test.rows'
            if !defined($row) || ref($row) || length($row) != $size || $row !~ /\A[012]+\z/;
        push @cells, split //, $row;
    }

    return pack 'C*', @cells;
}

sub board_from_rows {
    my ($rows) = @_;

    return GobanFTP::Board->from_canonical_bytes(
        size            => scalar @$rows,
        canonical_bytes => bytes_from_rows($rows),
    );
}

sub rows_from_board {
    my ($board) = @_;

    return rows_from_bytes($board->size, $board->canonical_bytes);
}

sub rows_from_bytes {
    my ($size, $bytes) = @_;

    croak 'rules.test.size'
        if !defined($size) || ref($size) || $size !~ /\A(?:0|[1-9][0-9]*)\z/ || $size < 1 || $size > 26;
    croak 'rules.test.bytes'
        if !defined($bytes) || ref($bytes) || length($bytes) != $size * $size;

    my @cells = unpack 'C*', $bytes;
    my @rows;
    for my $y (0 .. $size - 1) {
        push @rows, join '', @cells[$y * $size .. ($y + 1) * $size - 1];
    }

    return \@rows;
}

sub state_for_case {
    my ($rules, $case) = @_;

    my $board = board_from_rows($case->{rows});
    my $hash  = $rules->position_hash($board);
    return {
        board              => $board,
        position_hash      => $hash,
        ancestor_hashes    => { $hash => 1 },
        consecutive_passes => 0,
        terminal           => 0,
        next_color         => $case->{next_color} // $case->{move}{color},
    };
}

sub apply_case {
    my ($engine, $case) = @_;

    my $rules = GobanFTP::Rules->new(size => $case->{size}, engine => $engine);
    return $rules->apply_action(state_for_case($rules, $case), $case->{move});
}

sub apply_mechanics_case {
    my ($engine, $case) = @_;

    my ($point) = $case->{move}{action} =~ /\Aplay-([a-z][a-z])\z/;
    croak 'rules.test.play_action' if !defined $point;

    my ($index, $error) = point_to_index($point, $case->{size});
    croak $error if defined $error;

    my $rules = GobanFTP::Rules->new(size => $case->{size}, engine => $engine);
    return $rules->_apply_play_mechanics(
        board_bytes => bytes_from_rows($case->{rows}),
        index       => $index,
        stone       => _stone_for_color($case->{move}{color}),
    );
}

sub assert_c_matches_perl_case {
    my ($case, $label) = @_;

    $label //= $case->{id};
    my $perl = apply_case('perl', $case);
    my $c    = apply_case('c', $case);

    Test::More::is(!!$c->{ok}, !!$perl->{ok}, "$label: public ok matches Perl");
    Test::More::is_deeply(rows_from_board($c->{board}), rows_from_board($perl->{board}), "$label: public board matches Perl");
    Test::More::is_deeply($c->{captures}, $perl->{captures}, "$label: public captures match Perl");
    Test::More::is($c->{reason}, $perl->{reason}, "$label: public rejection reason matches Perl")
        if !$perl->{ok};

    return ($perl, $c);
}

sub assert_c_matches_perl_mechanics {
    my ($case, $label) = @_;

    $label //= $case->{id};
    my $perl = apply_mechanics_case('perl', $case);
    my $c    = apply_mechanics_case('c', $case);

    Test::More::is(!!$c->{ok}, !!$perl->{ok}, "$label: mechanics ok matches Perl");
    if ($perl->{ok}) {
        Test::More::is($c->{board_bytes}, $perl->{board_bytes}, "$label: mechanics board bytes match Perl");
        Test::More::is_deeply($c->{captures}, $perl->{captures}, "$label: mechanics captures match Perl");
    }
    else {
        Test::More::is($c->{reason}, $perl->{reason}, "$label: mechanics rejection reason matches Perl");
    }

    return ($perl, $c);
}

sub assert_case_expected {
    my ($case, $result, $label) = @_;

    $label //= $case->{id};
    Test::More::is(!!$result->{ok}, !!$case->{ok}, "$label: expected ok")
        if exists $case->{ok};

    if ($case->{ok}) {
        Test::More::is_deeply($result->{captures}, $case->{captures}, "$label: expected captures")
            if exists $case->{captures};
    }
    else {
        Test::More::is($result->{reason}, $case->{reason}, "$label: expected rejection reason")
            if exists $case->{reason};
    }

    Test::More::is_deeply(rows_from_board($result->{board}), $case->{expected_rows}, "$label: expected board")
        if exists $case->{expected_rows};
}

sub _stone_for_color {
    my ($color) = @_;

    return 1 if defined($color) && $color eq 'b';
    return 2 if defined($color) && $color eq 'w';
    croak 'rules.test.color';
}

1;
