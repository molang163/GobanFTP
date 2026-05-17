use strict;
use warnings;

use FindBin;
use JSON::PP;
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::Filename::Grammar qw(event_id_for parse_event);

my $fixture_dir = "$FindBin::Bin/fixtures/filename-grammar";
my $json        = JSON::PP->new->canonical;
my $game        = _read_single_line("$fixture_dir/game.name");

my @valid_cases   = _read_jsonl("$fixture_dir/valid-events.jsonl");
my @invalid_cases = _read_jsonl("$fixture_dir/invalid-events.jsonl");

for my $case (@valid_cases) {
    my ($event, $error) = parse_event($case->{name}, game_descriptor => $game);

    is $error, undef, "$case->{id}: accepted";
    is_deeply $event,
        {
        kind   => $case->{kind},
        fields => $case->{fields},
        },
        "$case->{id}: parsed kind and fields match fixture";
}

for my $case (@invalid_cases) {
    my ($event, $error) = parse_event($case->{name}, game_descriptor => $game);

    is $event, undef, "$case->{id}: rejected";
    is $error, $case->{error}, "$case->{id}: error code";
}

my @valid_names = _read_names("$fixture_dir/valid.names");
is_deeply \@valid_names, [map { $_->{name} } @valid_cases], 'valid.names mirrors valid-events.jsonl';

my @invalid_names = _read_invalid_names("$fixture_dir/invalid.names");
is_deeply \@invalid_names, [map { $_->{name} } @invalid_cases], 'invalid.names mirrors invalid-events.jsonl';

for my $row (_read_expected_ids("$fixture_dir/expected_ids.tsv")) {
    is event_id_for($game, $row->{event_without_hash}),
        $row->{expected_id},
        "$row->{event_without_hash}: event id";

    is "$row->{event_without_hash}.h-$row->{expected_id}",
        $row->{full_event_name},
        "$row->{event_without_hash}: full event name";
}

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

sub _read_jsonl {
    my ($path) = @_;

    open my $fh, '<:encoding(UTF-8)', $path or die "open $path: $!";
    my @cases;
    while (my $line = <$fh>) {
        chomp $line;
        next if $line =~ /\A\s*\z/;
        push @cases, $json->decode($line);
    }
    close $fh or die "close $path: $!";

    return @cases;
}

sub _read_names {
    my ($path) = @_;

    open my $fh, '<:encoding(UTF-8)', $path or die "open $path: $!";
    my @names;
    while (my $line = <$fh>) {
        chomp $line;
        next if $line =~ /\A\s*\z/;
        push @names, $line;
    }
    close $fh or die "close $path: $!";

    return @names;
}

sub _read_invalid_names {
    my ($path) = @_;

    open my $fh, '<:encoding(UTF-8)', $path or die "open $path: $!";
    my $header = <$fh>;
    die "$path is empty" if !defined $header;

    my @names;
    while (my $line = <$fh>) {
        chomp $line;
        next if $line =~ /\A\s*\z/;
        my ($name) = split /\t/, $line, 2;
        push @names, $name;
    }
    close $fh or die "close $path: $!";

    return @names;
}

sub _read_expected_ids {
    my ($path) = @_;

    open my $fh, '<:encoding(UTF-8)', $path or die "open $path: $!";
    my $header = <$fh>;
    die "$path is empty" if !defined $header;
    chomp $header;

    my @columns = split /\t/, $header;
    my @rows;
    while (my $line = <$fh>) {
        chomp $line;
        next if $line =~ /\A\s*\z/;

        my @values = split /\t/, $line;
        my %row;
        @row{@columns} = @values;
        push @rows, \%row;
    }
    close $fh or die "close $path: $!";

    return @rows;
}
