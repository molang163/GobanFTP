use strict;
use warnings;

use FindBin;
use JSON::PP qw(decode_json);
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::EventSetRoot qw(accepted_event_basenames event_set_root event_set_root_preimage event_set_root_result);

my $fixture_dir = "$FindBin::Bin/fixtures/vectors";

for my $case (_read_jsonl("$fixture_dir/event-set-root.jsonl")) {
    my @accepted = accepted_event_basenames(
        game_descriptor => $case->{game_descriptor},
        names           => $case->{names},
    );

    is_deeply \@accepted, $case->{accepted}, "$case->{id}: accepted basenames are deduped and sorted";

    for my $rejected (@{ $case->{rejected} }) {
        ok !grep({ $_ eq $rejected->{name} } @accepted), "$case->{id}: excludes $rejected->{id}";
    }

    my $preimage = event_set_root_preimage(
        game_descriptor => $case->{game_descriptor},
        names           => $case->{names},
    );

    is unpack('H*', $preimage), $case->{preimage_hex}, "$case->{id}: preimage framing";
    is event_set_root(game_descriptor => $case->{game_descriptor}, names => $case->{names}),
        $case->{event_set_root},
        "$case->{id}: event_set_root digest";

    my $result = event_set_root_result(game_descriptor => $case->{game_descriptor}, names => $case->{names});
    is $result->{version}, 'GOFTP-EVENT-SET/1', "$case->{id}: result names root version";
    is $result->{event_set_root}, $case->{event_set_root}, "$case->{id}: result carries root";
    is $result->{event_count}, scalar(@{ $case->{accepted} }), "$case->{id}: result counts accepted events";
    is_deeply $result->{accepted_events}, $case->{accepted}, "$case->{id}: result carries accepted events";
    is_deeply $result->{diagnostics}, $case->{diagnostics}, "$case->{id}: result carries rejected diagnostics";

    is event_set_root($case->{game_descriptor}, reverse @{ $case->{names} }),
        $case->{event_set_root},
        "$case->{id}: listing order does not affect root";
}

done_testing;

sub _read_jsonl {
    my ($path) = @_;

    open my $fh, '<:encoding(UTF-8)', $path or die "open $path: $!";

    my @cases;
    while (my $line = <$fh>) {
        chomp $line;
        next if $line =~ /\A\s*\z/;
        push @cases, decode_json($line);
    }

    close $fh or die "close $path: $!";

    return @cases;
}
