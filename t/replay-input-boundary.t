use v5.34;
use strict;
use warnings;

use FindBin;
use JSON::PP qw(decode_json);
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::Event qw(from_name);
use GobanFTP::Replay qw(replay);

my $game = 'g1.id-replay.s3.r-chinese-area-v1.k0.pb-alice.pw-bob';
my %event = _read_events("$FindBin::Bin/fixtures/replay/events.jsonl");

subtest 'item name is authoritative over a forged event payload' => sub {
    my $valid_name   = $event{chain_1}{name};
    my $forged_event = _event('fork_right');

    my $result = replay(
        game_descriptor => $game,
        items           => [{
            name  => $valid_name,
            event => $forged_event,
        }],
    );

    is_deeply $result->{diagnostics}, [], 'valid name is reparsed without trusting the payload';
    is_deeply $result->{canonical_ids}, [_id('chain_1')], 'canonical id comes from name';
    is_deeply $result->{legal_ids}, [_id('chain_1')], 'legal id comes from name';
    is $result->{names_by_id}{ _id('chain_1') }, $valid_name, 'name map records the authoritative name';
    ok !exists $result->{events_by_id}{ _id('fork_right') }, 'forged event id is not admitted';
};

subtest 'event payload without name is rejected' => sub {
    my $result = replay(
        game_descriptor => $game,
        items           => [{
            event => _event('chain_1'),
        }],
    );

    is_deeply [_codes($result)], ['invalid_event_item'], 'missing name is diagnosed';
    is_deeply $result->{canonical_ids}, [], 'unnamed payload is not canonical';
    is_deeply $result->{legal_ids}, [], 'unnamed payload is not legal';
    is_deeply $result->{events_by_id}, {}, 'unnamed payload is not indexed';
};

subtest 'bare event payload is rejected' => sub {
    my $result = replay(
        game_descriptor => $game,
        items           => [_event('chain_1')],
    );

    is_deeply [_codes($result)], ['invalid_event_item'], 'bare event payload is diagnosed';
    is_deeply $result->{canonical_ids}, [], 'bare payload is not canonical';
    is_deeply $result->{legal_ids}, [], 'bare payload is not legal';
    is_deeply $result->{events_by_id}, {}, 'bare payload is not indexed';
};

subtest 'bad names cannot be bypassed by a valid event payload' => sub {
    my $valid_event = _event('chain_1');
    my $bad_id_name = $event{chain_1}{name};
    $bad_id_name =~ s/\.h-[0-9a-v]{16}\z/.h-0000000000000000/;

    my @cases = (
        {
            name  => $bad_id_name,
            error => 'event_id.mismatch',
            label => 'event id mismatch',
        },
        {
            name  => "$event{chain_1}{name}/child",
            error => 'filename.charset',
            label => 'filename grammar violation',
        },
    );

    for my $case (@cases) {
        my $result = replay(
            game_descriptor => $game,
            items           => [{
                name  => $case->{name},
                event => $valid_event,
            }],
        );

        is_deeply $result->{diagnostics},
            [{
                code  => 'parse_event',
                name  => $case->{name},
                error => $case->{error},
            }],
            "$case->{label}: name parse failure is diagnosed";
        is_deeply $result->{canonical_ids}, [], "$case->{label}: bad name is not canonical";
        is_deeply $result->{legal_ids}, [], "$case->{label}: bad name is not legal";
        is_deeply $result->{events_by_id}, {}, "$case->{label}: bad name is not indexed";
    }
};

done_testing;

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

sub _event {
    my ($label) = @_;

    my ($parsed, $error) = from_name($event{$label}{name}, game_descriptor => $game);
    die "$label: $error" if defined $error;

    return $parsed;
}

sub _id {
    my ($label) = @_;
    return $event{$label}{event_id};
}

sub _codes {
    my ($result) = @_;
    return map { $_->{code} } @{ $result->{diagnostics} };
}

sub _event_id_from_name {
    my ($name) = @_;

    die "bad fixture name: $name" if $name !~ /\.h-([0-9a-v]{16})\z/;
    return $1;
}
