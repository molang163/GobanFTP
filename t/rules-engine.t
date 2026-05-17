use v5.34;
use strict;
use warnings;

use FindBin;
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::Board;
use GobanFTP::Rules;

sub exception (&);

subtest 'Perl is the default authoritative engine' => sub {
    local $ENV{GOBANFTP_RULES_ENGINE};
    local $ENV{GOBANFTP_RULES_DISABLE_C};
    delete $ENV{GOBANFTP_RULES_ENGINE};
    delete $ENV{GOBANFTP_RULES_DISABLE_C};

    my $rules = GobanFTP::Rules->new(size => 3);
    is $rules->engine, 'perl', 'default engine is perl';

    my $status = $rules->engine_status;
    is $status->{requested}, 'perl', 'status records requested engine';
    is $status->{effective}, 'perl', 'status records effective engine';
    is_deeply $status->{diagnostics}, [], 'default Perl has no C diagnostics';
};

subtest 'engine environment is validated and can be overridden' => sub {
    local $ENV{GOBANFTP_RULES_ENGINE} = 'nonsense';
    like exception { GobanFTP::Rules->new(size => 3) }, qr/rules\.engine/, 'unknown engine fails';

    local $ENV{GOBANFTP_RULES_DISABLE_C} = 1;
    local $ENV{GOBANFTP_RULES_ENGINE} = 'c';
    my $rules = GobanFTP::Rules->new(size => 3, engine => 'perl');
    is $rules->engine, 'perl', 'constructor engine overrides environment';
};

subtest 'auto falls back to Perl when C is disabled' => sub {
    local $ENV{GOBANFTP_RULES_ENGINE} = 'auto';
    local $ENV{GOBANFTP_RULES_DISABLE_C} = 1;

    my $rules = GobanFTP::Rules->new(size => 3);
    my $status = $rules->engine_status;
    is $status->{requested}, 'auto', 'auto requested';
    is $status->{effective}, 'perl', 'auto falls back to Perl';
    is $status->{c_available}, 0, 'C is reported unavailable';
    like $status->{c_error}, qr/GOBANFTP_RULES_DISABLE_C/, 'status explains disabled C';

    my $result = $rules->apply_action($rules->initial_state, color => 'b', action => 'play-aa');
    ok $result->{ok}, 'auto fallback still applies legal moves';
    is $result->{board}->stone_at('aa'), 1, 'auto fallback uses Perl mechanics';
};

subtest 'c mode fails explicitly when C is disabled' => sub {
    local $ENV{GOBANFTP_RULES_ENGINE} = 'c';
    local $ENV{GOBANFTP_RULES_DISABLE_C} = 1;

    like exception { GobanFTP::Rules->new(size => 3) },
        qr/rules\.c\.unavailable.*GOBANFTP_RULES_DISABLE_C/,
        'forced C mode reports unavailable C';
};

subtest 'shadow falls back to authoritative Perl with diagnostics when C is disabled' => sub {
    local $ENV{GOBANFTP_RULES_ENGINE} = 'shadow';
    local $ENV{GOBANFTP_RULES_DISABLE_C} = 1;

    my $rules = GobanFTP::Rules->new(size => 3);
    my $status = $rules->engine_status;
    is $status->{requested}, 'shadow', 'shadow requested';
    is $status->{effective}, 'perl', 'shadow falls back to Perl';
    is $status->{diagnostics}[0]{code}, 'rules_c_unavailable', 'status has C diagnostic';

    my $result = $rules->apply_action($rules->initial_state, color => 'b', action => 'play-bb');
    ok $result->{ok}, 'shadow fallback applies move';
    is $result->{board}->stone_at('bb'), 1, 'shadow fallback board is updated';
    is $result->{engine_diagnostics}[0]{code}, 'rules_c_unavailable', 'move result carries shadow diagnostic';
};

subtest 'shadow mode detects C mechanics mismatches without requiring Inline::C' => sub {
    local $ENV{GOBANFTP_RULES_ENGINE} = 'shadow';
    local $ENV{GOBANFTP_RULES_DISABLE_C};
    delete $ENV{GOBANFTP_RULES_DISABLE_C};

    no warnings 'redefine';
    local *GobanFTP::Rules::_c_available = sub { return (1, undef) };

    {
        local *GobanFTP::Rules::_c_play_mechanics = sub {
            return {
                ok       => 0,
                reason   => 'occupied',
                captures => [],
            };
        };
        my $rules = GobanFTP::Rules->new(size => 3);
        like exception {
            $rules->apply_action($rules->initial_state, color => 'b', action => 'play-aa');
        }, qr/rules\.c\.shadow_mismatch\.ok/, 'shadow mode fails loudly on C/Perl ok mismatch';
    }

    {
        local *GobanFTP::Rules::_c_play_mechanics = sub {
            my ($self) = @_;
            return {
                ok          => 1,
                board_bytes => "\0" x ($self->size * $self->size),
                captures    => [],
            };
        };
        my $rules = GobanFTP::Rules->new(size => 3);
        like exception {
            $rules->apply_action($rules->initial_state, color => 'b', action => 'play-aa');
        }, qr/rules\.c\.shadow_mismatch\.board_bytes/, 'shadow mode fails loudly on C/Perl board mismatch';
    }

    {
        local *GobanFTP::Rules::_c_play_mechanics = sub {
            return {
                ok       => 0,
                reason   => 'suicide',
                captures => [],
            };
        };
        my $rules = GobanFTP::Rules->new(size => 3);
        my $state = _state_with_board($rules, GobanFTP::Board->new(size => 3)->place('aa', 1));
        like exception {
            $rules->apply_action($state, color => 'b', action => 'play-aa');
        }, qr/rules\.c\.shadow_mismatch\.reason/, 'shadow mode fails loudly on C/Perl rejection reason mismatch';
    }

    {
        local *GobanFTP::Rules::_c_play_mechanics = sub {
            my ($self, %args) = @_;
            my $perl = GobanFTP::Rules::_perl_play_mechanics($self->size, %args);
            return {
                %$perl,
                captures => [],
            };
        };
        my $rules = GobanFTP::Rules->new(size => 3);
        my $board = GobanFTP::Board->new(size => 3)
            ->place('ab', 1)
            ->place('bb', 2)
            ->place('cb', 1)
            ->place('bc', 1);
        my $state = _state_with_board($rules, $board);
        like exception {
            $rules->apply_action($state, color => 'b', action => 'play-ba');
        }, qr/rules\.c\.shadow_mismatch\.captures/, 'shadow mode fails loudly on C/Perl capture mismatch';
    }
};

done_testing;

sub exception (&) {
    my ($code) = @_;

    my $error;
    eval { $code->(); 1 } or $error = $@;

    return $error;
}

sub _state_with_board {
    my ($rules, $board) = @_;

    my $hash = $rules->position_hash($board);
    return {
        %{ $rules->initial_state },
        board           => $board,
        position_hash   => $hash,
        ancestor_hashes => { $hash => 1 },
    };
}
