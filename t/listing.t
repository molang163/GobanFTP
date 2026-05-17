use v5.34;
use strict;
use warnings;

use FindBin;
use JSON::PP qw(decode_json);
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::Listing qw(event_basenames normalize_listing sort_event_basenames);

my $fixture_dir = "$FindBin::Bin/fixtures/listing-normalization";

for my $case (_read_jsonl("$fixture_dir/cases.jsonl")) {
    my @normalized = normalize_listing($case->{names});
    my $expected   = $case->{expected_sorted} // $case->{expected_events};

    is_deeply \@normalized, $expected, "$case->{id}: normalized listing";

    if (exists $case->{expected_sorted}) {
        my @sorted = sort_event_basenames($case->{names});
        is_deeply \@sorted, $case->{expected_sorted}, "$case->{id}: stable sort";
    }

    if (exists $case->{expected_events}) {
        my @events = event_basenames($case->{names});
        is_deeply \@events, $case->{expected_events}, "$case->{id}: event basename filter";
    }
}

my $move1 = 'm1.p000001.b.play-dd.pa-genesis.by-alice.n-k31v.h-f98qai37nace5spg';
my $move2 = 'm1.p000002.w.play-ee.pa-f98qai37nace5spg.by-bob.n-q9az.h-5ivvsvtid3j6u1pg';
my $ack1  = 'a1.t-f98qai37nace5spg.by-bob.n-s7p2.h-tim1sb5lpmd0d4q5';

is_deeply
    [event_basenames("events/$move1", "events/$ack1")],
    [$move1, $ack1],
    'events/ direct children normalize to basenames';

is_deeply
    [
    event_basenames(
        "events/$move1/child",
        "$move2/child",
        'tmp/alice.part',
        'sidecar/f98qai37nace5spg.json',
        'projections/board/current',
        'projection/board/current',
    )
    ],
    [],
    'recursive and non-authoritative paths are ignored';

is_deeply
    [event_basenames('events/m2.future-version', 'a2.future-version')],
    ['m2.future-version', 'a2.future-version'],
    'direct unknown move and ack versions are preserved for parser diagnostics';

is_deeply
    [normalize_listing("./events/$move1", $ack1, $move2)],
    [$ack1, $move1, $move2],
    'normalized listing has deterministic lexical order';

done_testing;

sub _read_jsonl {
    my ($file) = @_;

    open my $fh, '<:encoding(UTF-8)', $file or die "cannot open $file: $!";

    my @cases;
    while (defined(my $line = <$fh>)) {
        chomp $line;
        next if $line =~ /\A\s*\z/;
        push @cases, decode_json($line);
    }

    close $fh or die "cannot close $file: $!";

    return @cases;
}
