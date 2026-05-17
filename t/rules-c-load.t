use v5.34;
use strict;
use warnings;

use FindBin;
use Test::More;

use lib "$FindBin::Bin/../lib";

sub exception (&);

require_ok('GobanFTP::Rules::C');

subtest 'module reports optional C availability without requiring Inline::C' => sub {
    my $status = GobanFTP::Rules::C->status;

    ok exists($status->{available}), 'status has availability flag';
    is !!$status->{available}, !!GobanFTP::Rules::C->available, 'status matches available()';

    if (GobanFTP::Rules::C->available) {
        is $status->{error}, undef, 'available C has no load error';
    }
    else {
        ok defined(GobanFTP::Rules::C->load_error), 'unavailable C has a diagnostic';
    }
};

subtest 'direct C mechanics either works or fails explicitly' => sub {
    my $empty = "\0" x 9;

    if (GobanFTP::Rules::C->available) {
        my $result = GobanFTP::Rules::C->apply_play(
            board_bytes => $empty,
            size        => 3,
            index       => 4,
            stone       => 1,
        );

        ok $result->{ok}, 'C play succeeds';
        is_deeply $result->{captures}, [], 'ordinary C play has no captures';
        is substr($result->{board_bytes}, 4, 1), "\1", 'C writes the placed stone byte';
    }
    else {
        like exception {
            GobanFTP::Rules::C->apply_play(
                board_bytes => $empty,
                size        => 3,
                index       => 4,
                stone       => 1,
            );
        }, qr/rules\.c\.unavailable/, 'unavailable C apply is explicit';
    }
};

done_testing;

sub exception (&) {
    my ($code) = @_;

    my $error;
    eval { $code->(); 1 } or $error = $@;

    return $error;
}
