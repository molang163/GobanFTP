use v5.34;
use strict;
use warnings;

use FindBin;
use File::Spec;
use Test::More;

my $fixture_dir = "$FindBin::Bin/fixtures/attacks";

my @required_attacks = qw(
    bad-mtime
    bad-payload
    bad-list-order
    bad-signature
    duplicate-event
    bad-event-id
    future-version
    missing-parent
    fake-player
    fork-race
    poisoned-sidecar
    projection-poison
    tmp-poison
    dangling-ack
);

my @required_files = qw(
    game.name
    listing.names
    expected.verdict
);

my @required_verdict_fields = qw(
    attack
    mode
    command
    status
    exit
    game
    events
    event_set_count
    event_set_root
    canonical_moves
    legal_moves
    diagnostic.class
    consensus_inputs
    ignored_inputs
    note
);

ok -d $fixture_dir, 'attack fixture gallery directory exists';

my @attacks = grep { -d File::Spec->catdir($fixture_dir, $_) } _dir_names($fixture_dir);
ok @attacks, 'attack fixture gallery has specimens';

my %attack_present = map { $_ => 1 } @attacks;
for my $attack (@required_attacks) {
    ok $attack_present{$attack}, "v1 required attack specimen exists: $attack";
}

for my $attack (@attacks) {
    subtest $attack => sub {
        my $dir = File::Spec->catdir($fixture_dir, $attack);

        my %path = map { $_ => File::Spec->catfile($dir, $_) } @required_files;
        my $has_required_files = 1;
        for my $file (@required_files) {
            my $ok = -f $path{$file};
            ok $ok, "$file exists";
            $has_required_files &&= $ok;
        }
        return if !$has_required_files;

        my ($game, $game_error) = _read_single($path{'game.name'});
        ok !$game_error, 'game.name has exactly one nonblank name';
        diag $game_error if $game_error;

        my ($listing, $listing_error) = _read_names($path{'listing.names'});
        ok !$listing_error, 'listing.names is readable';
        diag $listing_error if $listing_error;
        ok @$listing, 'listing.names has observed names' if !$listing_error;

        my ($verdict, $verdict_error) = _read_verdict($path{'expected.verdict'});
        ok !$verdict_error, 'expected.verdict is parseable key=value';
        diag $verdict_error if $verdict_error;
        return if $verdict_error;

        for my $field (@required_verdict_fields) {
            ok exists($verdict->{$field}), "verdict includes $field";
        }

        is $verdict->{attack}, $attack, 'verdict attack matches directory basename'
            if exists $verdict->{attack};
        is $verdict->{game}, $game, 'verdict game matches game.name'
            if !$game_error && exists $verdict->{game};

        is $verdict->{consensus_inputs}, 'descriptor,events',
            'GOFTP/1 consensus inputs stay descriptor and events'
            if exists $verdict->{consensus_inputs};

        like $verdict->{event_set_root}, qr/\A[0-9a-f]{64}\z/,
            'event_set_root is lowercase SHA-256 hex'
            if exists $verdict->{event_set_root};
        like $verdict->{mode}, qr/\A(?:local|listing)\z/, 'mode is a known harness mode'
            if exists $verdict->{mode};
        like $verdict->{exit}, qr/\A(?:0|[1-9][0-9]*)\z/, 'exit is numeric'
            if exists $verdict->{exit};

        for my $field (qw(events event_set_count canonical_moves legal_moves)) {
            like $verdict->{$field}, qr/\A(?:0|[1-9][0-9]*)\z/, "$field is numeric"
                if exists $verdict->{$field};
        }
    };
}

done_testing;

sub _read_verdict {
    my ($path) = @_;

    my %verdict;
    my $error = _with_error(sub {
        open my $fh, '<:encoding(UTF-8)', $path or die "open $path: $!";
        while (my $line = <$fh>) {
            chomp $line;
            next if $line =~ /\A\s*\z/;
            my ($key, $value) = split /=/, $line, 2;
            die "bad verdict line in $path: $line"
                if !defined($key) || !defined($value) || $key eq '';
            $verdict{$key} = $value;
        }
        close $fh or die "close $path: $!";
    });

    return (\%verdict, $error);
}

sub _read_single {
    my ($path) = @_;

    my ($names, $error) = _read_names($path);
    return (undef, $error) if $error;
    return (undef, "$path must contain exactly one nonblank line") if @$names != 1;
    return ($names->[0], undef);
}

sub _read_names {
    my ($path) = @_;

    my @names;
    my $error = _with_error(sub {
        open my $fh, '<:encoding(UTF-8)', $path or die "open $path: $!";
        while (my $line = <$fh>) {
            chomp $line;
            next if $line =~ /\A\s*\z/;
            push @names, $line;
        }
        close $fh or die "close $path: $!";
    });

    return (\@names, $error);
}

sub _dir_names {
    my ($dir) = @_;

    opendir my $dh, $dir or die "opendir $dir: $!";
    my @names = sort grep { $_ ne '.' && $_ ne '..' } readdir $dh;
    closedir $dh or die "closedir $dir: $!";

    return @names;
}

sub _with_error {
    my ($code) = @_;

    my $error;
    {
        local $@;
        eval { $code->(); 1 } or $error = $@ || 'unknown error';
    }
    chomp $error if defined $error;
    return $error;
}
