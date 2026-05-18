package GobanFTP::Witness;

use v5.34;
use strict;
use warnings;

use Carp qw(croak);
use Digest::SHA qw(sha256_hex);
use Exporter qw(import);

use GobanFTP::Diagnostics qw(
    default_diagnostics_schema
    diagnostic_classes
    diagnostic_codes
    replay_status
    schema_from_file
);
use GobanFTP::EventSetRoot qw(event_set_root_result);
use GobanFTP::GameSpec qw(parse_basename);
use GobanFTP::Listing qw(normalize_listing);
use GobanFTP::Profile qw(profile);
use GobanFTP::Profile::Adapter qw(profile_listing_names);
use GobanFTP::Profile::SignedHMAC qw(is_signed_hmac_profile signed_hmac_event_set_result);
use GobanFTP::Projection qw(render_projection);
use GobanFTP::Replay qw(replay);
use GobanFTP::RulesetSeal qw(ruleset_seal_record);

our @EXPORT_OK = qw(witness_for_listing);

sub witness_for_listing {
    my %args = _args(@_);

    my $profile_id = _required($args{profile_id}, 'profile_id');
    my $game       = _required($args{game_descriptor}, 'game_descriptor');
    my $raw_names  = _array_ref($args{raw_names}, 'raw_names');
    my $schema     = _diagnostics_schema(%args);
    my $profile    = profile($profile_id);
    my $ruleset    = _ruleset_record_for_game($game);

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

    if (is_signed_hmac_profile($profile_id)) {
        $event_set = signed_hmac_event_set_result(
            profile_id        => $profile_id,
            game_descriptor   => $game,
            unsigned_result   => $event_set,
            hmac_attestations => _array_ref(
                $args{hmac_attestations} // [],
                'hmac_attestations',
            ),
            trusted_hmac_keys => _hash_ref(
                $args{trusted_hmac_keys} // {},
                'trusted_hmac_keys',
            ),
            trusted_hmac_key_statuses => _hash_ref(
                $args{trusted_hmac_key_statuses} // {},
                'trusted_hmac_key_statuses',
            ),
        );
        @replay_events = @{ $event_set->{accepted_events} };
    }

    my $result = replay(
        game_descriptor => $game,
        events          => \@replay_events,
    );
    my @diagnostics = $result->diagnostics;
    my @rejected_diagnostics = map { _clone_diagnostic($_) } @{ $event_set->{diagnostics} };

    my $rendered = _render_projection(
        game_descriptor => $game,
        events          => \@replay_events,
        replay_result   => $result,
    );

    my @canonical_ids = $result->canonical_ids;
    my @legal_ids     = $result->legal_ids;
    my %projection_hashes = _projection_hashes($rendered);

    my $witness = {
        profile_id                => $profile_id,
        profile_consensus_version => $profile->{consensus_version},
        adapter_id                => $profile->{adapter_id},
        game_descriptor           => $game,
        %$ruleset,
        raw_count                 => scalar(@$raw_names),
        normalized_count          => scalar(@events),
        normalized_events         => [@events],
        accepted_count            => $event_set->{event_count},
        accepted_events           => [@{ $event_set->{accepted_events} }],
        rejected_count            => scalar(@{ $event_set->{diagnostics} }),
        rejected_diagnostics      => \@rejected_diagnostics,
        rejected_codes            => [diagnostic_codes($event_set->{diagnostics})],
        rejected_classes          => [diagnostic_classes($event_set->{diagnostics}, $schema)],
        event_set_root            => $event_set->{event_set_root},
        replay_status             => replay_status(\@diagnostics),
        canonical_tip             => @canonical_ids ? $canonical_ids[-1] : 'genesis',
        canonical_ids             => \@canonical_ids,
        legal_ids                 => \@legal_ids,
        %projection_hashes,
        diagnostic_codes          => [diagnostic_codes(\@diagnostics)],
        diagnostic_classes        => [diagnostic_classes(\@diagnostics, $schema)],
        diagnostic_count          => scalar(@diagnostics),
        replay_diagnostics        => [map { _clone_diagnostic($_) } @diagnostics],
    };
    $witness->{projection_text} = _projection_text($rendered)
        if $args{include_projection_text};

    return $witness;
}

sub _diagnostics_schema {
    my (%args) = @_;

    return _array_ref($args{diagnostics_schema}, 'diagnostics_schema')
        if exists $args{diagnostics_schema};

    return schema_from_file($args{diagnostics_schema_path})
        if exists $args{diagnostics_schema_path};

    return default_diagnostics_schema();
}

sub _ruleset_record_for_game {
    my ($game_descriptor) = @_;

    my ($game_spec, $game_error) = parse_basename($game_descriptor);
    return {} if defined $game_error;

    my $ruleset = eval { ruleset_seal_record($game_spec->{rules}) };
    if (!$ruleset) {
        my $error = $@ || 'unknown ruleset seal error';
        die $error if $error !~ /\Aunsupported ruleset:/;
        return {};
    }

    return $ruleset;
}

sub _render_projection {
    my (%args) = @_;

    my $result = $args{replay_result};
    my @diagnostics = $result->diagnostics;

    my $rendered = eval { render_projection(%args) };
    return $rendered if $rendered;

    my $error = $@ || 'unknown projection error';
    die $error if !_has_diagnostic_code(\@diagnostics, qw(parse_game_descriptor rules));
    return {};
}

sub _projection_hashes {
    my ($rendered) = @_;
    return () if ref($rendered) ne 'HASH' || !%$rendered;

    return (
        board_hash => sha256_hex($rendered->{board} // ''),
        sgf_hash   => sha256_hex($rendered->{sgf_main} // $rendered->{sgf} // ''),
        variations_sgf_hash => sha256_hex(
            $rendered->{sgf_variations} // $rendered->{variations_sgf} // ''
        ),
    );
}

sub _projection_text {
    my ($rendered) = @_;
    return {} if ref($rendered) ne 'HASH' || !%$rendered;

    my %text;
    for my $field (qw(
        board
        verdict
        listing
        sgf_main
        sgf_variations
    )) {
        next if !exists $rendered->{$field};
        next if ref($rendered->{$field});
        $text{$field} = $rendered->{$field};
    }

    return \%text;
}

sub _has_diagnostic_code {
    my ($diagnostics, @codes) = @_;

    my %wanted = map { $_ => 1 } @codes;
    return grep { $wanted{ $_->{code} // '' } } @$diagnostics;
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

sub _hash_ref {
    my ($value, $name) = @_;
    croak "$name must be a hash reference" if ref($value) ne 'HASH';
    return $value;
}

sub _clone_diagnostic {
    my ($diagnostic) = @_;
    return { %$diagnostic };
}

1;

__END__

=head1 NAME

GobanFTP::Witness - read-only v1 profile witness assembly

=cut
