use v5.34;
use strict;
use warnings;

use FindBin;
use JSON::PP qw(decode_json);
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::Replay qw(replay);
use GobanFTP::SGF qw(main_sgf variations_sgf);

my $fixture_dir = "$FindBin::Bin/fixtures/sgf";
my $game = _read_single_line("$fixture_dir/game.name");

subtest 'main SGF renders play pass resign and komi' => sub {
    my %event = _read_events("$fixture_dir/main-events.jsonl");
    my $result = replay(
        game_descriptor => $game,
        events          => _names(\%event, qw(main_3 main_1 main_2)),
    );

    is_deeply $result->{diagnostics}, [], 'main fixture replays cleanly';
    is main_sgf($result), _read_file("$fixture_dir/expected-main.sgf"),
        'main_sgf renders canonical replay result';

    my @canonical_events = map { $result->{events_by_id}{$_} } @{ $result->{canonical_ids} };
    is main_sgf(game_descriptor => $game, canonical_events => \@canonical_events),
        _read_file("$fixture_dir/expected-main.sgf"),
        'main_sgf can render from game descriptor and canonical events only';
};

subtest 'main SGF stops at fork instead of choosing low id' => sub {
    my %event = _read_events("$fixture_dir/variation-events.jsonl");
    my $result = replay(
        game_descriptor => $game,
        events          => _names(\%event, qw(right_child left right left_child)),
    );

    is $result->{fork}{parent_id}, 'genesis', 'fixture forks at genesis';
    is_deeply $result->{canonical_ids}, [], 'canonical prefix is empty at root fork';
    is main_sgf($result),
        "(;GM[1]FF[4]CA[UTF-8]AP[GobanFTP]SZ[9]KM[7.5]PB[alice]PW[bob]RU[chinese-area-v1])\n",
        'main SGF exports only the conservative prefix';
};

subtest 'variations SGF renders legal branches sorted by event id' => sub {
    my %event = _read_events("$fixture_dir/variation-events.jsonl");
    my $result = replay(
        game_descriptor => $game,
        events          => _names(\%event, qw(right_child left right left_child)),
    );

    is variations_sgf($result), _read_file("$fixture_dir/expected-variations.sgf"),
        'variations_sgf renders the legal branch tree';
};

subtest 'SGF property values are escaped' => sub {
    my $sgf = main_sgf(
        game => {
            size       => 9,
            komi_milli => 6250,
            black      => 'a]lice\\x',
            white      => 'bo]b',
            rules      => 'rule\\name',
        },
        events => [
            {
                color  => 'b',
                action => 'play-aa',
                point  => 'aa',
            },
        ],
    );

    is $sgf,
        "(;GM[1]FF[4]CA[UTF-8]AP[GobanFTP]SZ[9]KM[6.25]PB[a\\]lice\\\\x]PW[bo\\]b]RU[rule\\\\name];B[aa])\n",
        'escaping and arbitrary milli-komi formatting are deterministic';
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

sub _read_file {
    my ($path) = @_;

    open my $fh, '<:encoding(UTF-8)', $path or die "open $path: $!";
    local $/;
    my $content = <$fh>;
    close $fh or die "close $path: $!";

    return $content;
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
    my ($events, @labels) = @_;
    return [map { $events->{$_}{name} } @labels];
}

sub _event_id_from_name {
    my ($name) = @_;
    die "bad fixture name: $name" if $name !~ /\.h-([0-9a-v]{16})\z/;
    return $1;
}
