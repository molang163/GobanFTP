use strict;
use warnings;

use FindBin;
use JSON::PP qw(decode_json);
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::EventID qw(event_id event_id_error);

sub read_jsonl {
    my ($path) = @_;

    open my $fh, '<', $path or die "open $path: $!";

    my @rows;
    while (my $line = <$fh>) {
        chomp $line;
        next if $line =~ /\A\s*\z/;
        push @rows, decode_json($line);
    }

    return @rows;
}

my $fixture_dir = "$FindBin::Bin/fixtures/event-id";

for my $case (read_jsonl("$fixture_dir/cases.jsonl")) {
    is(
        event_id($case->{game}, $case->{event_without_hash}),
        $case->{expected_id},
        "$case->{id} computes expected event id",
    );

    is(
        event_id_error($case->{game}, $case->{full_event_name}),
        undef,
        "$case->{id} full event name validates",
    );
}

for my $case (read_jsonl("$fixture_dir/invalid.jsonl")) {
    is(
        event_id_error($case->{game}, $case->{name}),
        $case->{error},
        "$case->{id} reports $case->{error}",
    );
}

done_testing;
