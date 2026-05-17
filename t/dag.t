use v5.34;
use strict;
use warnings;

use FindBin;
use JSON::PP;
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::DAG qw(build);
use GobanFTP::Filename::Grammar qw(parse_event);

my $fixture_dir = "$FindBin::Bin/fixtures/dag";
my %event = _read_events("$fixture_dir/events.jsonl");

subtest 'unordered chain is sorted and topological' => sub {
    my $dag = build(events => [
        $event{child_c},
        $event{root_a},
        $event{child_b},
    ]);

    is_deeply [$dag->move_ids],
        [qw(aaaaaaaaaaaaaaaa bbbbbbbbbbbbbbbb cccccccccccccccc)],
        'move_ids are lexical by event_id';

    is_deeply [$dag->topological_move_ids],
        [qw(aaaaaaaaaaaaaaaa bbbbbbbbbbbbbbbb cccccccccccccccc)],
        'topological order puts parents before children';

    is_deeply [$dag->children_of('genesis')], ['aaaaaaaaaaaaaaaa'], 'genesis child';
    is_deeply [$dag->children_of('aaaaaaaaaaaaaaaa')], ['bbbbbbbbbbbbbbbb'], 'move child';
    is_deeply [$dag->diagnostics], [], 'valid chain has no diagnostics';
};

subtest 'fork at genesis is reported but not a diagnostic' => sub {
    my $dag = build(events => [
        $event{root_e},
        $event{root_d},
    ]);

    is_deeply $dag->forks,
        { genesis => [qw(dddddddddddddddd eeeeeeeeeeeeeeee)] },
        'genesis has multiple lexical children';

    is_deeply [$dag->diagnostics], [], 'fork is not an error';
};

subtest 'fork after move is reported' => sub {
    my $dag = build(events => [
        $event{after_a_g},
        $event{root_a},
        $event{after_a_f},
    ]);

    is_deeply [$dag->children_of('aaaaaaaaaaaaaaaa')],
        [qw(ffffffffffffffff gggggggggggggggg)],
        'children are lexical';

    is_deeply $dag->forks,
        { aaaaaaaaaaaaaaaa => [qw(ffffffffffffffff gggggggggggggggg)] },
        'move parent fork';
};

subtest 'missing parent diagnostic' => sub {
    my $dag = build(events => [$event{missing_parent}]);

    is_deeply [$dag->move_ids], [], 'missing-parent move is not replayable';
    is_deeply [$dag->topological_move_ids], [], 'missing-parent move is not topological';

    is_deeply [$dag->diagnostics],
        [{
            code      => 'missing_parent',
            event_id  => 'hhhhhhhhhhhhhhhh',
            parent_id => '9999999999999999',
        }],
        'missing parent is diagnosed';
};

subtest 'parent_not_move diagnostic' => sub {
    my $dag = build(events => [
        $event{parent_is_ack},
        $event{ack_a},
        $event{root_a},
    ]);

    is_deeply [$dag->move_ids], ['aaaaaaaaaaaaaaaa'], 'parent-not-move child is not replayable';
    is_deeply [$dag->children_of('iiiiiiiiiiiiiiii')], [], 'ack parent has no replayable children';
    is_deeply [$dag->ack_ids], ['iiiiiiiiiiiiiiii'], 'ack_ids are exposed';
    is_deeply [$dag->diagnostics],
        [{
            code        => 'parent_not_move',
            event_id    => 'jjjjjjjjjjjjjjjj',
            parent_id   => 'iiiiiiiiiiiiiiii',
            parent_kind => 'ack',
        }],
        'ack cannot be a move parent';
};

subtest 'dangling ack target diagnostic' => sub {
    my $dag = build(events => [$event{dangling_ack}]);

    is $dag->node('kkkkkkkkkkkkkkkk')->{target_id}, '8888888888888888', 'ack node exposes target';
    is_deeply [$dag->diagnostics],
        [{
            code      => 'dangling_ack_target',
            event_id  => 'kkkkkkkkkkkkkkkk',
            target_id => '8888888888888888',
        }],
        'missing ack target is diagnosed';
};

subtest 'ack target must be a move' => sub {
    my $dag = build(events => [
        $event{ack_a},
        $event{ack_ack},
        $event{root_a},
    ]);

    is_deeply [$dag->diagnostics],
        [{
            code        => 'ack_target_not_move',
            event_id    => 'mmmmmmmmmmmmmmmm',
            target_id   => 'iiiiiiiiiiiiiiii',
            target_kind => 'ack',
        }],
        'ack cannot target another ack';
};

subtest 'duplicate exact name is idempotent' => sub {
    my $dag = build(events => [
        $event{root_a},
        $event{root_a},
    ]);

    is_deeply [$dag->move_ids], ['aaaaaaaaaaaaaaaa'], 'duplicate exact name is kept once';
    is_deeply [$dag->children_of('genesis')], ['aaaaaaaaaaaaaaaa'], 'duplicate does not duplicate edges';
    is_deeply [$dag->diagnostics], [], 'duplicate exact name is not a collision';
};

subtest 'event_id collision diagnostic' => sub {
    my $dag = build(events => [
        $event{collision_second},
        $event{collision_first},
    ]);

    is $dag->node('llllllllllllllll'), undef, 'colliding id does not become a node';
    is_deeply [$dag->move_ids], [], 'colliding moves are not replayable';
    is_deeply [$dag->children_of('genesis')], [], 'colliding moves are not children';

    is_deeply [$dag->diagnostics],
        [{
            code     => 'event_id_collision',
            event_id => 'llllllllllllllll',
            names    => [
                $event{collision_first}{name},
                $event{collision_second}{name},
            ],
        }],
        'same id with different names is diagnosed deterministically';
};

done_testing;

sub _read_events {
    my ($path) = @_;

    open my $fh, '<:encoding(UTF-8)', $path or die "open $path: $!";
    my %events;
    my $json = JSON::PP->new;
    while (my $line = <$fh>) {
        chomp $line;
        next if $line =~ /\A\s*\z/;

        my $row = $json->decode($line);
        my ($parsed, $error) = parse_event($row->{name});
        die "$row->{id}: $error" if defined $error;

        $events{ $row->{id} } = {
            name  => $row->{name},
            event => $parsed,
        };
    }
    close $fh or die "close $path: $!";

    return %events;
}
