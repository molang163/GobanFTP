use v5.34;
use strict;
use warnings;

use FindBin;
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::Filename::Grammar qw(parse_event);
use GobanFTP::Rules;

sub exception (&);

subtest 'constructor validates v1 rules identity' => sub {
    my $rules = GobanFTP::Rules->new(size => 9, rules => 'chinese-area-v1');
    is $rules->size, 9, 'size is stored';
    is $rules->rules, 'chinese-area-v1', 'rules id is stored';
    like exception { GobanFTP::Rules->new(size => 1) }, qr/rules\.size/, 'size follows game descriptor bounds';
    like exception { GobanFTP::Rules->new(size => 9, rules => 'made-up') }, qr/rules\.id/, 'unknown rules rejected';
};

subtest 'black moves first and turns alternate' => sub {
    my $rules = GobanFTP::Rules->new(size => 3);
    my $state = $rules->initial_state;

    my $white_first = $rules->apply_action($state, color => 'w', action => 'play-aa');
    ok !$white_first->{ok}, 'white cannot play first';
    is $white_first->{reason}, 'color', 'wrong color reason';

    my $black = $rules->apply_action($state, color => 'b', action => 'play-aa');
    ok $black->{ok}, 'black can play first';
    is $black->{next_color}, 'w', 'white is next';

    my $black_again = $rules->apply_action($black, color => 'b', action => 'pass');
    ok !$black_again->{ok}, 'same color cannot move twice';
    is $black_again->{reason}, 'color', 'turn error is color';
};

subtest 'pass skips superko and two passes end play' => sub {
    my $rules = GobanFTP::Rules->new(size => 3);
    my $state = $rules->initial_state;

    my $black_pass = $rules->apply_action($state, color => 'b', action => 'pass');
    ok $black_pass->{ok}, 'first pass is legal despite unchanged position hash';
    is $black_pass->{position_hash}, $state->{position_hash}, 'pass keeps position hash';
    is $black_pass->{consecutive_passes}, 1, 'pass count increments';
    ok !$black_pass->{terminal}, 'one pass is not terminal';

    my $white_pass = $rules->apply_action($black_pass, color => 'w', action => 'pass');
    ok $white_pass->{ok}, 'second pass is legal';
    is $white_pass->{consecutive_passes}, 2, 'pass count reaches two';
    ok $white_pass->{terminal}, 'two consecutive passes are terminal';
    is $white_pass->{terminal_reason}, 'two_passes', 'terminal reason identifies two passes';

    my $after_terminal = $rules->apply_action($white_pass, color => 'b', action => 'play-aa');
    ok !$after_terminal->{ok}, 'moves after terminal state fail';
    is $after_terminal->{reason}, 'terminal', 'terminal reason';
};

subtest 'resign ends immediately' => sub {
    my $rules  = GobanFTP::Rules->new(size => 3);
    my $resign = $rules->apply_action($rules->initial_state, color => 'b', action => 'resign');

    ok $resign->{ok}, 'resign is legal';
    ok $resign->{terminal}, 'resign is terminal';
    is $resign->{terminal_reason}, 'resign', 'terminal reason identifies resign';
    is_deeply $resign->{captures}, [], 'resign has no captures';
};

subtest 'apply_move accepts parsed event hashes for replay integration' => sub {
    my ($event, $error) = parse_event('m1.p000001.b.play-aa.pa-genesis.by-alice.n-a.h-0000000000000000');
    is $error, undef, 'fixture event parses';

    my $rules  = GobanFTP::Rules->new(size => 3);
    my $result = $rules->apply_move($rules->initial_state, $event);

    ok $result->{ok}, 'parsed move applies';
    is $result->{board}->stone_at('aa'), 1, 'parsed move writes stone';
};

done_testing;

sub exception (&) {
    my ($code) = @_;

    my $error;
    eval { $code->(); 1 } or $error = $@;

    return $error;
}
