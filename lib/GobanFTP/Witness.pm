package GobanFTP::Witness;

use v5.34;
use strict;
use warnings;

use Carp qw(croak);
use Digest::SHA qw(sha256_hex);
use Exporter qw(import);

use GobanFTP::Diagnostics qw(
    diagnostic_classes
    diagnostic_codes
    replay_status
    schema_from_file
);
use GobanFTP::EventSetRoot qw(event_set_root_result);
use GobanFTP::Listing qw(normalize_listing);
use GobanFTP::Profile qw(profile);
use GobanFTP::Profile::Adapter qw(profile_listing_names);
use GobanFTP::Projection qw(render_projection);
use GobanFTP::Replay qw(replay);

our @EXPORT_OK = qw(witness_for_listing);

sub witness_for_listing {
    my %args = _args(@_);

    my $profile_id = _required($args{profile_id}, 'profile_id');
    my $game       = _required($args{game_descriptor}, 'game_descriptor');
    my $raw_names  = _array_ref($args{raw_names}, 'raw_names');
    my $schema     = _diagnostics_schema(%args);
    my $profile    = profile($profile_id);

    my @profile_names = profile_listing_names(
        profile_id      => $profile_id,
        game_descriptor => $game,
        raw_names       => $raw_names,
    );
    my @events        = normalize_listing(@profile_names);
    my @replay_events = @events;

    my $event_set = event_set_root_result(
        game_descriptor => $game,
        names           => \@profile_names,
    );

    my $result = replay(
        game_descriptor => $game,
        events          => \@replay_events,
    );
    my @diagnostics = $result->diagnostics;

    my $rendered = render_projection(
        game_descriptor => $game,
        events          => \@replay_events,
        replay_result   => $result,
    );

    my @canonical_ids = $result->canonical_ids;
    my @legal_ids     = $result->legal_ids;

    return {
        profile_id                => $profile_id,
        profile_consensus_version => $profile->{consensus_version},
        adapter_id                => $profile->{adapter_id},
        game_descriptor           => $game,
        raw_count                 => scalar(@$raw_names),
        normalized_count          => scalar(@events),
        normalized_events         => [@events],
        accepted_count            => $event_set->{event_count},
        accepted_events           => [@{ $event_set->{accepted_events} }],
        rejected_count            => scalar(@{ $event_set->{diagnostics} }),
        rejected_codes            => [diagnostic_codes($event_set->{diagnostics})],
        rejected_classes          => [diagnostic_classes($event_set->{diagnostics}, $schema)],
        event_set_root            => $event_set->{event_set_root},
        replay_status             => replay_status(\@diagnostics),
        canonical_tip             => @canonical_ids ? $canonical_ids[-1] : 'genesis',
        canonical_ids             => \@canonical_ids,
        legal_ids                 => \@legal_ids,
        board_hash                => sha256_hex($rendered->{board} // ''),
        sgf_hash                  => sha256_hex($rendered->{sgf_main} // $rendered->{sgf} // ''),
        variations_sgf_hash       => sha256_hex(
            $rendered->{sgf_variations} // $rendered->{variations_sgf} // ''
        ),
        diagnostic_codes          => [diagnostic_codes(\@diagnostics)],
        diagnostic_classes        => [diagnostic_classes(\@diagnostics, $schema)],
        diagnostic_count          => scalar(@diagnostics),
    };
}

sub _diagnostics_schema {
    my (%args) = @_;

    return _array_ref($args{diagnostics_schema}, 'diagnostics_schema')
        if exists $args{diagnostics_schema};

    return schema_from_file($args{diagnostics_schema_path});
}

sub _args {
    return %{ $_[0] } if @_ == 1 && ref($_[0]) eq 'HASH';
    croak 'named arguments must be key/value pairs' if @_ % 2;
    return @_;
}

sub _required {
    my ($value, $name) = @_;
    croak "$name is required" if !defined($value) || $value eq '';
    return $value;
}

sub _array_ref {
    my ($value, $name) = @_;
    croak "$name must be an array reference" if ref($value) ne 'ARRAY';
    return $value;
}

1;

__END__

=head1 NAME

GobanFTP::Witness - read-only v1 profile witness assembly

=cut
