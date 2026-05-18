use v5.34;
use strict;
use warnings;

use FindBin;
use File::Spec;
use Test::More;

use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/lib";

use GobanFTP::Test::WitnessHarness qw(witness_for_listing);

my $fixture_dir = "$FindBin::Bin/fixtures/v1/cross-substrate";
my $schema_path = "$FindBin::Bin/../docs/DIAGNOSTICS.md";
my @profiles = qw(local-goftp1 ftp-goftp1 git-tree-goftp1 dns-record-goftp1 webdav-goftp1);

my %expected = (
    minimal => {
        status        => 'ok',
        root          => '599c00f0614e400274a92ab1c96d09087a53d0d88bd8b0ecba481ac60a1f1461',
        accepted      => 3,
        rejected      => 0,
        canonical_tip => 'kcvtlonfje163p9q',
        diagnostics   => [],
        rejected_classes => [],
    },
    fork => {
        status        => 'fork',
        root          => '02dac396696a1a3806d89819aadf672d02399426106b25bbbd4f36d9dd178b76',
        accepted      => 2,
        rejected      => 0,
        canonical_tip => 'genesis',
        diagnostics   => ['fork'],
        rejected_classes => [],
    },
    'fork-with-ack' => {
        status        => 'fork',
        root          => '3e8226ada6d09e4da60d6fe423fb918d464d0e2a7b7b6f5d377784ff90eeb215',
        accepted      => 3,
        rejected      => 0,
        canonical_tip => 'genesis',
        diagnostics   => ['fork'],
        rejected_classes => [],
    },
    'bad-event-id' => {
        status        => 'validation',
        root          => 'c8bdfd7e8dc55bdef0a4571923d9ae370c876aa106ad666d125f8151dc05185d',
        accepted      => 0,
        rejected      => 1,
        canonical_tip => 'genesis',
        diagnostics   => ['event-id'],
        rejected_classes => ['event-id'],
    },
);

for my $case (qw(minimal fork fork-with-ack bad-event-id)) {
    subtest $case => sub {
        my $case_dir = File::Spec->catdir($fixture_dir, $case);
        my $game = _read_single(File::Spec->catfile($case_dir, 'game.name'));
        my %witness;

        for my $profile (@profiles) {
            my @raw = _read_names(File::Spec->catfile($case_dir, $profile, 'listing.names'));
            my $witness = witness_for_listing(
                profile_id              => $profile,
                game_descriptor         => $game,
                raw_names               => \@raw,
                diagnostics_schema_path => $schema_path,
            );
            $witness{$profile} = $witness;

            is $witness->{profile_id}, $profile, "$profile records profile id";
            is $witness->{game_descriptor}, $game, "$profile records game descriptor";
            is $witness->{event_set_root}, $expected{$case}{root}, "$profile event_set_root";
            is $witness->{accepted_count}, $expected{$case}{accepted}, "$profile accepted count";
            is $witness->{rejected_count}, $expected{$case}{rejected}, "$profile rejected-name count";
            is $witness->{replay_status}, $expected{$case}{status}, "$profile replay status";
            is $witness->{canonical_tip}, $expected{$case}{canonical_tip}, "$profile canonical tip";
            is_deeply $witness->{diagnostic_classes}, $expected{$case}{diagnostics},
                "$profile diagnostic classes";
            is_deeply $witness->{rejected_classes}, $expected{$case}{rejected_classes},
                "$profile rejected-name diagnostic classes";
            like $witness->{board_hash}, qr/\A[0-9a-f]{64}\z/, "$profile board hash shape";
            like $witness->{sgf_hash}, qr/\A[0-9a-f]{64}\z/, "$profile SGF hash shape";
            like $witness->{variations_sgf_hash}, qr/\A[0-9a-f]{64}\z/,
                "$profile variations SGF hash shape";
            ok !grep({ m{/} } @{ $witness->{accepted_events} }),
                "$profile accepted events are basenames";
        }

        _assert_same_witness($case, \%witness, qw(
            accepted_count
            accepted_events
            rejected_count
            rejected_codes
            rejected_classes
            event_set_root
            replay_status
            canonical_tip
            canonical_ids
            legal_ids
            board_hash
            sgf_hash
            variations_sgf_hash
            diagnostic_codes
            diagnostic_classes
        ));

        ok $witness{'ftp-goftp1'}{raw_count} > $witness{'local-goftp1'}{raw_count},
            "$case FTP fixture has ignored shadow names";
        ok $witness{'ftp-goftp1'}{normalized_count} >= $witness{'ftp-goftp1'}{accepted_count},
            "$case FTP normalization can see duplicates before acceptance dedupe";
        ok $witness{'git-tree-goftp1'}{raw_count} > $witness{'local-goftp1'}{raw_count},
            "$case Git tree fixture has ignored metadata entries";
        ok $witness{'git-tree-goftp1'}{normalized_count} >= $witness{'git-tree-goftp1'}{accepted_count},
            "$case Git tree normalization preserves accepted events";
        ok $witness{'dns-record-goftp1'}{raw_count} > $witness{'local-goftp1'}{raw_count},
            "$case DNS record fixture has ignored metadata rows";
        ok $witness{'dns-record-goftp1'}{normalized_count} >= $witness{'dns-record-goftp1'}{accepted_count},
            "$case DNS record normalization preserves accepted events";
        ok $witness{'webdav-goftp1'}{raw_count} > $witness{'local-goftp1'}{raw_count},
            "$case WebDAV fixture has ignored metadata rows";
        ok $witness{'webdav-goftp1'}{normalized_count} >= $witness{'webdav-goftp1'}{accepted_count},
            "$case WebDAV normalization can see duplicates before acceptance dedupe";
    };
}

done_testing;

sub _assert_same_witness {
    my ($case, $witnesses, @fields) = @_;

    my $baseline = $witnesses->{'local-goftp1'};
    for my $profile (grep { $_ ne 'local-goftp1' } sort keys %$witnesses) {
        for my $field (@fields) {
            my $got  = $witnesses->{$profile}{$field};
            my $want = $baseline->{$field};
            if (ref($want)) {
                is_deeply $got, $want, "$case $profile matches local $field";
            }
            else {
                is $got, $want, "$case $profile matches local $field";
            }
        }
    }
}

sub _read_single {
    my ($path) = @_;

    my @names = _read_names($path);
    die "$path must contain exactly one nonblank line" if @names != 1;
    return $names[0];
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
