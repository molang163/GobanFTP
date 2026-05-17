use v5.34;
use strict;
use warnings;

use FindBin;
use JSON::PP qw(decode_json);
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::Replay qw(replay);

my $fixture_dir = "$FindBin::Bin/fixtures/projection-contract";
my $game = _read_single_line("$fixture_dir/game.name");
my %event = _read_events("$fixture_dir/events.jsonl");

my $result = replay(
    game_descriptor => $game,
    events          => _names(qw(left illegal ack_root root right)),
);

my $root    = _id('root');
my $left    = _id('left');
my $right   = _id('right');
my $illegal = _id('illegal');
my $ack     = _id('ack_root');

subtest 'projection fields expose parsed game and events' => sub {
    is_deeply $result->{game},
        {
        descriptor => $game,
        game_id    => 'contract',
        size       => 3,
        rules      => 'chinese-area-v1',
        komi_milli => 0,
        black      => 'alice',
        white      => 'bob',
        },
        'game view includes descriptor and parsed fields';

    is_deeply [sort keys %{ $result->{events_by_id} }],
        [sort ($root, $left, $right, $illegal, $ack)],
        'events_by_id includes parsed non-colliding events';

    is $result->{events_by_id}{$ack}{kind}, 'ack', 'ack event remains available for projections';
    is $result->{names_by_id}{$root}, $event{root}{name}, 'names_by_id maps id to authoritative name';
    is $result->{events_by_id}{$right}{fields}{point}, 'cc', 'event fields are available by id';
};

subtest 'canonical prefix stops before legal fork' => sub {
    is_deeply $result->{canonical_ids}, [$root], 'canonical line keeps only the conservative prefix';

    is $result->{fork}{code}, 'fork', 'fork is diagnosed';
    is $result->{fork}{parent_id}, $root, 'fork parent is the canonical root';
    is_deeply $result->{fork}{child_ids}, [sort ($left, $right)], 'fork children are event-id sorted';

    is_deeply $result->{legal_children_by_parent}{genesis}, [$root], 'genesis has the single legal root';
    is_deeply $result->{legal_children_by_parent}{$root}, [sort ($left, $right)],
        'only legal children are exposed under the fork parent';
    ok !grep({ $_ eq $illegal } @{ $result->{legal_children_by_parent}{$root} }),
        'illegal child is absent from legal_children_by_parent';
};

subtest 'canonical steps carry projection-ready move state' => sub {
    is scalar @{ $result->{canonical_steps} }, 1, 'one canonical step before fork';

    my $step = $result->{canonical_steps}[0];
    is $step->{id}, $root, 'step id is explicit';
    is $step->{event_id}, $root, 'step event_id mirrors id';
    is $step->{name}, $event{root}{name}, 'step carries authoritative event name';
    is $step->{parent_id}, 'genesis', 'step carries parent id';
    is $step->{fields}{action}, 'play-aa', 'step carries canonical event fields';
    is_deeply $step->{captures}, [], 'step carries capture list';
    is $step->{state}{board}->stone_at('aa'), 1, 'step state is the post-move state';
};

subtest 'projection accessors return copies' => sub {
    my $game_copy = $result->game;
    $game_copy->{size} = 99;
    is $result->game->{size}, 3, 'game accessor is isolated';

    my $events_copy = $result->events_by_id;
    $events_copy->{$root}{fields}{action} = 'pass';
    is $result->events_by_id->{$root}{fields}{action}, 'play-aa', 'events_by_id accessor is isolated';

    my @steps_copy = $result->canonical_steps;
    $steps_copy[0]{fields}{action} = 'pass';
    is(($result->canonical_steps)[0]{fields}{action}, 'play-aa', 'canonical_steps accessor is isolated');

    my $children_copy = $result->legal_children_by_parent;
    push @{ $children_copy->{$root} }, $illegal;
    is_deeply $result->legal_children_by_parent->{$root}, [sort ($left, $right)],
        'legal_children_by_parent accessor is isolated';

    my @diagnostics_copy = $result->diagnostics;
    ok @diagnostics_copy, 'fixture has diagnostics to copy';
    my $original_code = $diagnostics_copy[0]{code};
    $diagnostics_copy[0]{code} = 'mutated';
    is(($result->diagnostics)[0]{code}, $original_code, 'diagnostics accessor is isolated');
};

done_testing;

sub _read_single_line {
    my ($path) = @_;

    open my $fh, '<:encoding(UTF-8)', $path or die "open $path: $!";
    my $line = <$fh>;
    close $fh or die "close $path: $!";

    die "$path is empty" if !defined $line;
    chomp $line;
    return $line;
}

sub _read_events {
    my ($path) = @_;

    open my $fh, '<:encoding(UTF-8)', $path or die "open $path: $!";
    my %events;
    while (my $line = <$fh>) {
        chomp $line;
        next if $line =~ /\A\s*\z/;

        my $row = decode_json($line);
        $row->{event_id} = _event_id_from_name($row->{name});
        $events{ $row->{id} } = $row;
    }
    close $fh or die "close $path: $!";

    return %events;
}

sub _names {
    return [map { $event{$_}{name} } @_];
}

sub _id {
    my ($label) = @_;
    return $event{$label}{event_id};
}

sub _event_id_from_name {
    my ($name) = @_;
    die "bad fixture name: $name" if $name !~ /\.h-([0-9a-v]{16})\z/;
    return $1;
}
