use v5.34;
use strict;
use warnings;

use FindBin;
use Test::More;

use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/lib";

use GobanFTP::Rules;
use GobanFTP::Test::RulesMechanics qw(
    assert_c_matches_perl_case
    assert_c_matches_perl_mechanics
    assert_case_expected
    read_jsonl
    skip_unless_c_available
);

skip_unless_c_available('rules C equivalence');

my $fixture_dir = "$FindBin::Bin/fixtures/rules";

subtest 'forced C engine is active when Inline::C is available' => sub {
    my $rules = GobanFTP::Rules->new(size => 3, engine => 'c');
    my $status = $rules->engine_status;
    is $status->{requested}, 'c', 'C engine requested';
    is $status->{effective}, 'c', 'C engine is the effective mechanics engine';
    is $status->{c_available}, 1, 'C availability is reported';
};

subtest 'C engine matches Perl engine for legacy play fixtures' => sub {
    for my $case (_read_jsonl("$fixture_dir/play-cases.jsonl")) {
        my (undef, $c) = assert_c_matches_perl_case($case);
        assert_case_expected($case, $c);
    }
};

subtest 'C mechanics matches Perl for boundary fixtures' => sub {
    for my $case (_read_jsonl("$fixture_dir/mechanics-boundary.jsonl")) {
        assert_c_matches_perl_mechanics($case);
        my (undef, $c) = assert_c_matches_perl_case($case);
        assert_case_expected($case, $c);
    }
};

done_testing;

sub _read_jsonl { return read_jsonl(@_) }
