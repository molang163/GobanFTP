use v5.34;
use strict;
use warnings;

use FindBin;
use JSON::PP;
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::Event qw(from_name event_id fields is_ack is_move kind parent_id);

my $json = JSON::PP->new->canonical;
my $fixture_dir = "$FindBin::Bin/fixtures/filename-grammar";
my $game = _read_single_line("$fixture_dir/game.name");

my @valid = _read_jsonl("$fixture_dir/valid-events.jsonl");

for my $case (@valid) {
    my ($event, $error) = from_name($case->{name}, game_descriptor => $game);

    is $error, undef, "$case->{id}: no error";
    is kind($event), $case->{kind}, "$case->{id}: kind";
    is_deeply fields($event), $case->{fields}, "$case->{id}: fields";
    is event_id($event), $case->{fields}{event_id}, "$case->{id}: event id";

    if ($case->{kind} eq 'move') {
        ok is_move($event), "$case->{id}: is move";
        ok !is_ack($event), "$case->{id}: not ack";
        is parent_id($event), $case->{fields}{parent}, "$case->{id}: parent";
    }
    else {
        ok is_ack($event), "$case->{id}: is ack";
        ok !is_move($event), "$case->{id}: not move";
        is parent_id($event), undef, "$case->{id}: no parent";
    }
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
