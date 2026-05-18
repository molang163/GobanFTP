use v5.34;
use strict;
use warnings;

use FindBin;
use File::Spec;
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::Witness qw(witness_for_listing);

my $fixture_dir = "$FindBin::Bin/fixtures/v1/attacks";
my $schema_path = "$FindBin::Bin/../docs/DIAGNOSTICS.md";

ok -d $fixture_dir, 'v1 profile attack fixture directory exists';

my @attacks = grep { -d File::Spec->catdir($fixture_dir, $_) } _dir_names($fixture_dir);
ok @attacks, 'v1 profile attack gallery has specimens';

for my $attack (@attacks) {
    subtest $attack => sub {
        my $dir = File::Spec->catdir($fixture_dir, $attack);
        my $expected = _read_verdict(File::Spec->catfile($dir, 'expected.verdict'));
        my $game = _read_single(File::Spec->catfile($dir, 'game.name'));

        is $expected->{attack}, $attack, 'verdict attack matches directory';
        is $expected->{game}, $game, 'verdict game matches game.name';
        ok $expected->{ignored_inputs} ne '', 'ignored inputs are declared';
        ok $expected->{note} ne '', 'fixture has a judgment note';

        my $profile = $expected->{profile};
        my $baseline_profile = $expected->{baseline_profile};
        ok defined($profile) && $profile ne '', 'profile is declared';
        ok defined($baseline_profile) && $baseline_profile ne '', 'baseline profile is declared';

        my $baseline = _witness_for_fixture_profile($dir, $baseline_profile, $game);
        my $witness  = _witness_for_fixture_profile($dir, $profile, $game);

        is $witness->{accepted_count}, 0 + $expected->{accepted_count}, 'accepted count';
        is $witness->{event_set_root}, $expected->{event_set_root}, 'event-set root';
        is $witness->{replay_status}, $expected->{replay_status}, 'replay status';
        is join(',', @{ $witness->{canonical_ids} }), $expected->{canonical_ids},
            'canonical ids';
        is join(',', @{ $witness->{legal_ids} }), $expected->{legal_ids},
            'legal ids';
        is join(',', @{ $witness->{diagnostic_classes} }), $expected->{diagnostic_classes},
            'diagnostic classes';
        is join(',', @{ $witness->{rejected_classes} }), $expected->{rejected_classes},
            'rejected-name classes';

        _assert_same_witness($attack, $witness, $baseline, qw(
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

        ok $witness->{raw_count} > $baseline->{raw_count},
            'attack profile has extra hostile raw rows';
        ok $witness->{normalized_count} >= $witness->{accepted_count},
            'normalization keeps at least the accepted event candidates';
        ok !grep({ m{/} } @{ $witness->{accepted_events} }),
            'accepted events are basenames';
    };
}

done_testing;

sub _witness_for_fixture_profile {
    my ($dir, $profile, $game) = @_;

    my @raw = _read_names(File::Spec->catfile($dir, $profile, 'listing.names'));
    return witness_for_listing(
        profile_id              => $profile,
        game_descriptor         => $game,
        raw_names               => \@raw,
        diagnostics_schema_path => $schema_path,
    );
}

sub _assert_same_witness {
    my ($attack, $got, $want, @fields) = @_;

    for my $field (@fields) {
        my $got_value  = $got->{$field};
        my $want_value = $want->{$field};
        if (ref($want_value)) {
            is_deeply $got_value, $want_value, "$attack matches baseline $field";
        }
        else {
            is $got_value, $want_value, "$attack matches baseline $field";
        }
    }
}

sub _read_verdict {
    my ($path) = @_;

    my %verdict;
    open my $fh, '<:encoding(UTF-8)', $path or die "open $path: $!";
    while (my $line = <$fh>) {
        chomp $line;
        next if $line =~ /\A\s*\z/;
        my ($key, $value) = split /=/, $line, 2;
        die "bad verdict line in $path: $line" if !defined($key) || !defined($value);
        $verdict{$key} = $value;
    }
    close $fh or die "close $path: $!";

    return \%verdict;
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

sub _dir_names {
    my ($dir) = @_;

    opendir my $dh, $dir or die "opendir $dir: $!";
    my @names = sort grep { $_ ne '.' && $_ ne '..' } readdir $dh;
    closedir $dh or die "closedir $dir: $!";

    return @names;
}
