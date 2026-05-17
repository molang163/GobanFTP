package GobanFTP::Test::WitnessHarness;

use v5.34;
use strict;
use warnings;

use Digest::SHA qw(sha256_hex);
use Exporter qw(import);

use GobanFTP::EventSetRoot qw(event_set_root_result);
use GobanFTP::Listing qw(normalize_listing);
use GobanFTP::Projection qw(render_projection);
use GobanFTP::Replay qw(replay);

our @EXPORT_OK = qw(witness_for_listing);

my %SCHEMA_CACHE;

sub witness_for_listing {
    my (%args) = @_;

    my $profile_id = _required($args{profile_id},      'profile_id');
    my $game       = _required($args{game_descriptor}, 'game_descriptor');
    my $raw_names  = _array_ref($args{raw_names},      'raw_names');
    my $schema     = _schema($args{diagnostics_schema_path});

    my @events = normalize_listing(@$raw_names);
    my $event_set = event_set_root_result(
        game_descriptor => $game,
        names           => $raw_names,
    );
    my $result = replay(
        game_descriptor => $game,
        events          => \@events,
    );
    my @diagnostics = $result->diagnostics;

    my $rendered = render_projection(
        game_descriptor => $game,
        events          => \@events,
        replay_result   => $result,
    );

    my @canonical_ids = $result->canonical_ids;
    my @legal_ids     = $result->legal_ids;

    return {
        profile_id             => $profile_id,
        game_descriptor        => $game,
        raw_count              => scalar(@$raw_names),
        normalized_count       => scalar(@events),
        normalized_events      => [@events],
        accepted_count         => $event_set->{event_count},
        accepted_events        => [@{ $event_set->{accepted_events} }],
        rejected_count         => scalar(@{ $event_set->{diagnostics} }),
        rejected_codes         => [_diagnostic_codes($event_set->{diagnostics})],
        rejected_classes       => [_diagnostic_classes($event_set->{diagnostics}, $schema)],
        event_set_root         => $event_set->{event_set_root},
        replay_status          => _replay_status(\@diagnostics),
        canonical_tip          => @canonical_ids ? $canonical_ids[-1] : 'genesis',
        canonical_ids          => \@canonical_ids,
        legal_ids              => \@legal_ids,
        board_hash             => sha256_hex($rendered->{board} // ''),
        sgf_hash               => sha256_hex($rendered->{sgf_main} // $rendered->{sgf} // ''),
        variations_sgf_hash    => sha256_hex($rendered->{sgf_variations} // $rendered->{variations_sgf} // ''),
        diagnostic_codes       => [_diagnostic_codes(\@diagnostics)],
        diagnostic_classes     => [_diagnostic_classes(\@diagnostics, $schema)],
        diagnostic_count       => scalar(@diagnostics),
    };
}

sub _replay_status {
    my ($diagnostics) = @_;

    return 'ok' if !@$diagnostics;
    return 'validation' if grep { ($_->{code} // '') ne 'fork' } @$diagnostics;
    return 'fork';
}

sub _diagnostic_codes {
    my ($diagnostics) = @_;
    return _unique_sorted(map { $_->{code} // '' } @$diagnostics);
}

sub _diagnostic_classes {
    my ($diagnostics, $schema) = @_;
    return _unique_sorted(map { _diagnostic_class($_, $schema) // 'unknown' } @$diagnostics);
}

sub _diagnostic_class {
    my ($diagnostic, $schema) = @_;

    my @candidates = grep { $_->{code} eq ($diagnostic->{code} // '') } @$schema;
    for my $row (@candidates) {
        return $row->{class} if _selector_matches($diagnostic, $row->{selector});
    }

    return undef;
}

sub _selector_matches {
    my ($diagnostic, $selector) = @_;

    return 1 if !defined($selector) || $selector eq '*';

    if ($selector =~ /\A([a-z_]+)=(.*)\z/) {
        my ($field, $want) = ($1, $2);
        my $got = $diagnostic->{$field} // '';
        return $got =~ /\A\Q$want\E\z/ if $want !~ /\*\z/;

        my $prefix = substr($want, 0, -1);
        return index($got, $prefix) == 0;
    }

    return 0;
}

sub _schema {
    my ($path) = @_;

    die 'diagnostics_schema_path is required' if !defined($path) || $path eq '';
    return $SCHEMA_CACHE{$path} if exists $SCHEMA_CACHE{$path};

    open my $fh, '<:encoding(UTF-8)', $path or die "open $path: $!";
    my $docs = do { local $/; <$fh> };
    close $fh or die "close $path: $!";

    my ($block) = $docs =~ /^```diagnostic-schema\n(.*?)^```/ms;
    die 'diagnostic-schema block not found' if !defined $block;

    my @lines = grep { /\S/ } split /\n/, $block;
    my $header = shift @lines // '';
    die "bad diagnostic schema header: $header"
        if $header ne 'code|selector|class|required|optional';

    my @schema;
    for my $line (@lines) {
        my ($code, $selector, $class, $required, $optional) = split /\|/, $line, 5;
        die "bad diagnostic schema line: $line"
            if !defined($code) || !defined($selector) || !defined($class)
                || !defined($required) || !defined($optional);

        push @schema, {
            code     => $code,
            selector => $selector,
            class    => $class,
        };
    }

    return $SCHEMA_CACHE{$path} = \@schema;
}

sub _unique_sorted {
    my (%seen, @values);
    for my $value (@_) {
        next if !defined($value) || $value eq '';
        next if $seen{$value}++;
        push @values, $value;
    }
    return sort @values;
}

sub _required {
    my ($value, $name) = @_;
    die "$name is required" if !defined($value) || $value eq '';
    return $value;
}

sub _array_ref {
    my ($value, $name) = @_;
    die "$name must be an array reference" if ref($value) ne 'ARRAY';
    return $value;
}

1;
