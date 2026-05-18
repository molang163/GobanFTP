use v5.34;
use strict;
use warnings;

use FindBin;
use File::Spec;
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::Witness qw(witness_for_listing);

my $fixture_dir = "$FindBin::Bin/fixtures/v1/cross-substrate";
my $schema_path = "$FindBin::Bin/../docs/DIAGNOSTICS.md";

subtest 'minimal local witness exposes production fields' => sub {
    my $case_dir = File::Spec->catdir($fixture_dir, 'minimal');
    my $game     = _read_single(File::Spec->catfile($case_dir, 'game.name'));
    my @raw      = _read_names(File::Spec->catfile($case_dir, 'local-goftp1', 'listing.names'));

    my $witness = witness_for_listing(
        profile_id              => 'local-goftp1',
        game_descriptor         => $game,
        raw_names               => \@raw,
        diagnostics_schema_path => $schema_path,
    );

    is $witness->{profile_id}, 'local-goftp1', 'records profile id';
    is $witness->{profile_consensus_version}, 'GOFTP-PROFILE/local-goftp1/1',
        'records profile consensus version';
    is $witness->{adapter_id}, 'local-listing-goftp1', 'records adapter id';
    is $witness->{game_descriptor}, $game, 'records game descriptor';
    is $witness->{raw_count}, 4, 'counts raw listing rows';
    is $witness->{normalized_count}, 3, 'counts normalized event candidates';
    is $witness->{accepted_count}, 3, 'counts accepted events';
    is $witness->{rejected_count}, 0, 'no rejected filename diagnostics';
    is $witness->{event_set_root},
        '599c00f0614e400274a92ab1c96d09087a53d0d88bd8b0ecba481ac60a1f1461',
        'minimal root is stable';
    is $witness->{replay_status}, 'ok', 'replay status is ok';
    is $witness->{canonical_tip}, 'kcvtlonfje163p9q', 'canonical tip is stable';
    is_deeply $witness->{diagnostic_classes}, [], 'no replay diagnostic classes';
    is_deeply $witness->{rejected_classes}, [], 'no root rejection classes';
    is $witness->{board_hash},
        '15d477c5602f55fd5e90624226a791e92b2c1feb1be6e2a5c4bdcb6457ea262c',
        'minimal board hash is stable';
    is $witness->{sgf_hash},
        'c18781ad0ed14358917d489286f257f0ff906ed3df6c35f937d52763b0a94553',
        'minimal SGF hash is stable';
    is $witness->{variations_sgf_hash},
        'c18781ad0ed14358917d489286f257f0ff906ed3df6c35f937d52763b0a94553',
        'minimal variations SGF hash is stable';
    ok !grep({ m{/} } @{ $witness->{accepted_events} }),
        'accepted events are basenames';
};

subtest 'bad event id still reaches replay diagnostics' => sub {
    my $case_dir = File::Spec->catdir($fixture_dir, 'bad-event-id');
    my $game     = _read_single(File::Spec->catfile($case_dir, 'game.name'));
    my @raw      = _read_names(File::Spec->catfile($case_dir, 'local-goftp1', 'listing.names'));

    my $witness = witness_for_listing(
        profile_id              => 'local-goftp1',
        game_descriptor         => $game,
        raw_names               => \@raw,
        diagnostics_schema_path => $schema_path,
    );

    is $witness->{accepted_count}, 0, 'bad event id is excluded from event-set root';
    is $witness->{rejected_count}, 1, 'bad event id is reported by root gate';
    is $witness->{replay_status}, 'validation', 'bad event id is still a replay validation';
    is_deeply $witness->{rejected_classes}, ['event-id'], 'root rejection class is event-id';
    is_deeply $witness->{diagnostic_classes}, ['event-id'], 'replay diagnostic class is event-id';
    is $witness->{board_hash},
        'e02590a52e17585d3bc4bf16f9754b15d74a07eac57352998777474e56970709',
        'bad event id board hash is stable';
    is $witness->{sgf_hash},
        'bc7a5a055f2cbff252f6d7ada04bbfbdadd9e0e3a6ea364102ce31ace7215838',
        'bad event id SGF hash is stable';
    is $witness->{variations_sgf_hash},
        'bc7a5a055f2cbff252f6d7ada04bbfbdadd9e0e3a6ea364102ce31ace7215838',
        'bad event id variations SGF hash is stable';
};

done_testing;

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
