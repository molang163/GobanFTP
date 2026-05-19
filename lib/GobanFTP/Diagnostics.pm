package GobanFTP::Diagnostics;

use v5.34;
use strict;
use warnings;

use Carp qw(croak);
use Exporter qw(import);
use JSON::PP ();

our @EXPORT_OK = qw(
    default_diagnostics_schema
    diagnostic_registry
    diagnostic_class
    diagnostic_classes
    diagnostic_codes
    diagnostic_schema_json
    diagnostics_schema_from_file
    explain_diagnostic
    replay_status
    schema_from_file
);

my %SCHEMA_CACHE;
my @DEFAULT_REGISTRY = map {
    my ($code, $selector, $class, $required, $optional, $explanation, $hint) = @$_;
    +{
        code        => $code,
        selector    => $selector,
        class       => $class,
        required    => [_schema_fields($required)],
        optional    => [_schema_fields($optional)],
        explanation => $explanation,
        hint        => $hint,
    };
} (
    [
        'parse_event', 'error=event_id.*', 'event-id',
        'code,name,error', '-',
        'The event basename failed event-id validation.',
        'Recreate the basename from canonical event fields and publish the regenerated name.',
    ],
    [
        'parse_event', 'error=*', 'parse',
        'code,name,error', '-',
        'The event basename is not valid for a supported GOFTP/1 event version.',
        'Check the event name grammar, version prefix, fields, and short hash.',
    ],
    [
        'parse_game_descriptor', '*', 'parse',
        'code,error', '-',
        'The game descriptor basename is invalid or unsupported.',
        'Use a valid g1.* descriptor with supported size, rules, komi, and players.',
    ],
    [
        'parse_public_key', '*', 'parse',
        'code,error', '-',
        'The public key record cannot be parsed.',
        'Regenerate the key record or remove malformed trust input.',
    ],
    [
        'parse_hmac_key', '*', 'parse',
        'code,error', '-',
        'The HMAC key record cannot be parsed.',
        'Regenerate the HMAC key file and avoid editing secret material by hand.',
    ],
    [
        'parse_publish_token', '*', 'parse',
        'code,error', '-',
        'The publish token cannot be parsed.',
        'Regenerate the publish token from valid trust input.',
    ],
    [
        'parse_trust', '*', 'parse',
        'code,error', '-',
        'The trust record cannot be parsed.',
        'Fix the trust file format or regenerate trust records.',
    ],
    [
        'invalid_event_item', '*', 'parse',
        'code,index,stage', '-',
        'Replay received an in-memory item that is not a valid event container.',
        'Pass event basenames or parsed move/ack items with the expected fields.',
    ],
    [
        'event_id_collision', '*', 'event-id',
        'code,event_id,names', '-',
        'Two accepted parsed event items resolve to the same event id.',
        'Remove the duplicate or colliding event and keep only one basename for that id.',
    ],
    [
        'missing_parent', '*', 'dag',
        'code,event_id,parent_id', '-',
        'An event references a parent that is not present in the replay DAG.',
        'Publish or restore the parent event before the child.',
    ],
    [
        'parent_not_move', '*', 'dag',
        'code,event_id,parent_id,parent_kind', '-',
        'An event parent exists but is not a move event.',
        'Point moves and acknowledgements at move parents only.',
    ],
    [
        'cycle', '*', 'dag',
        'code,event_id', '-',
        'The event graph contains a parent cycle.',
        'Remove or correct parent links so replay remains acyclic.',
    ],
    [
        'dangling_ack_target', '*', 'dag',
        'code,event_id,target_id', '-',
        'An acknowledgement targets an event id that is not present.',
        'Publish the target move or remove the acknowledgement.',
    ],
    [
        'ack_target_not_move', '*', 'dag',
        'code,event_id,target_id,target_kind', '-',
        'An acknowledgement target exists but is not a move event.',
        'Target acknowledgements at move events only.',
    ],
    [
        'ack_target_invalid', '*', 'dag',
        'code,target_id,reason,error', '-',
        'An acknowledgement target is not eligible for canonical replay.',
        'Inspect the target diagnostic reason before trusting the acknowledgement.',
    ],
    [
        'wrong_color', '*', 'rules',
        'code,event_id,parent_id,expected_color,color', '-',
        'A move used a color different from the expected turn color.',
        'Submit the next move using the expected color.',
    ],
    [
        'wrong_player', '*', 'rules',
        'code,event_id,parent_id,color,expected_player,player', '-',
        'A move was submitted by a player who is not allowed for that color.',
        'Use the configured player id for the move color.',
    ],
    [
        'wrong_ply', '*', 'rules',
        'code,event_id,parent_id,expected_ply,ply', '-',
        'A move used a ply number different from the expected sequence.',
        'Publish the move with the next expected ply.',
    ],
    [
        'illegal_move', '*', 'rules',
        'code,event_id,parent_id,reason', '-',
        'The rules engine rejected the move.',
        'Choose a legal point, pass, or resign under the current ruleset.',
    ],
    [
        'parent_not_legal', '*', 'rules',
        'code,event_id,parent_id', '-',
        'A child move depends on a parent that was already illegal.',
        'Branch from a legal parent or resolve the earlier invalid move.',
    ],
    [
        'ack_wrong_player', '*', 'rules',
        'code,event_id,expected_player,player', '-',
        'An acknowledgement was submitted by a player who is not allowed to ack.',
        'Use an allowed opposing player for the acknowledgement.',
    ],
    [
        'rules', '*', 'rules',
        'code,error', '-',
        'Replay could not evaluate the ruleset or rule state.',
        'Use a supported ruleset descriptor and inspect the error field.',
    ],
    [
        'fork', '*', 'fork',
        'code,parent_id,child_ids', '-',
        'Multiple legal child moves compete for the same parent.',
        'Publish an acknowledgement or otherwise choose a canonical branch.',
    ],
    [
        'missing_signature', '*', 'signature',
        'code,profile_id,name,event_id', '-',
        'A signed profile required an event signature, but no usable signature was found.',
        'Publish a valid attestation for the event under the signed profile.',
    ],
    [
        'wrong_signature', '*', 'signature',
        'code,profile_id,name,event_id,key_id,reason', '-',
        'A trusted signature record does not verify the canonical event binding.',
        'Regenerate the attestation for this profile, game descriptor, event, and key.',
    ],
    [
        'untrusted_signature', '*', 'signature',
        'code,profile_id,name,event_id,key_id,reason', 'trust_set_id',
        'A signature uses a key outside the active trust scope.',
        'Add an appropriate trust record or sign with a trusted HMAC key.',
    ],
    [
        'malformed_signature', '*', 'signature',
        'code,profile_id,signature_id,reason', '-',
        'A signature record cannot be parsed as the signed profile format.',
        'Regenerate the signature sidecar record.',
    ],
    [
        'storage', '*', 'storage',
        'code,error', 'stage',
        'A storage operation failed before replay truth could be produced.',
        'Inspect the error field and retry after fixing the store path or backend.',
    ],
    [
        'transport_stale', '*', 'storage',
        'code,error', 'stage',
        'The remote transport did not show the expected published state within the read-back window.',
        'Refresh the store and retry once the transport view catches up.',
    ],
    [
        'publish_pending', '*', 'storage',
        'code,error', 'stage,name,event_id',
        'A publish operation was accepted locally but final visibility is not confirmed.',
        'Avoid conflicting follow-ups until the event becomes visible or the operation is retried.',
    ],
    [
        'shadow_poisoned', '*', 'storage',
        'code,error', 'stage,name',
        'Storage contains ignored shadow or metadata content that attempts to influence replay.',
        'Keep only direct public event basenames as consensus input and quarantine the shadow content.',
    ],
);
my %DEFAULT_REGISTRY_BY_KEY;
for my $row (@DEFAULT_REGISTRY) {
    my $key = _registry_key($row);
    croak "duplicate diagnostic registry row: $key" if exists $DEFAULT_REGISTRY_BY_KEY{$key};
    $DEFAULT_REGISTRY_BY_KEY{$key} = $row;
}

sub default_diagnostics_schema {
    return diagnostic_registry();
}

sub diagnostic_registry {
    return _clone(\@DEFAULT_REGISTRY);
}

sub diagnostic_schema_json {
    my ($schema) = @_;
    $schema = diagnostic_registry() if !defined $schema;
    $schema = _array_ref($schema, 'schema');

    return JSON::PP->new->canonical(1)->encode(_clone($schema));
}

sub explain_diagnostic {
    my ($diagnostic, $schema) = @_;

    my $query;
    if (ref($diagnostic) eq 'HASH') {
        $query = $diagnostic;
    } elsif (defined($diagnostic) && !ref($diagnostic) && $diagnostic ne '') {
        $query = { code => $diagnostic };
    } else {
        croak 'diagnostic must be a hash reference or diagnostic code';
    }

    $schema = diagnostic_registry() if !defined $schema;
    $schema = _array_ref($schema, 'schema');

    my $row = _schema_row($query, $schema);
    my $code = $query->{code} // (defined($row) ? ($row->{code} // '') : '');
    return undef if $code eq '' && !defined $row;
    return $code if !defined $row;

    my $explanation = $row->{explanation} // '';
    return $code if $explanation eq '';
    return "$code: $explanation";
}

sub replay_status {
    my ($diagnostics) = @_;
    $diagnostics = _array_ref($diagnostics, 'diagnostics');

    return 'ok' if !@$diagnostics;
    return 'validation' if grep { ($_->{code} // '') ne 'fork' } @$diagnostics;
    return 'fork';
}

sub diagnostic_codes {
    my ($diagnostics) = @_;
    $diagnostics = _array_ref($diagnostics, 'diagnostics');

    return _unique_sorted(map { $_->{code} // '' } @$diagnostics);
}

sub diagnostic_classes {
    my ($diagnostics, $schema) = @_;
    $diagnostics = _array_ref($diagnostics, 'diagnostics');
    $schema = _array_ref(defined($schema) ? $schema : diagnostic_registry(), 'schema');

    return _unique_sorted(map { diagnostic_class($_, $schema) // 'unknown' } @$diagnostics);
}

sub diagnostic_class {
    my ($diagnostic, $schema) = @_;
    croak 'diagnostic must be a hash reference' if ref($diagnostic) ne 'HASH';
    $schema = _array_ref(defined($schema) ? $schema : diagnostic_registry(), 'schema');

    my $code = $diagnostic->{code} // '';
    return 'signature'
        if $code =~ /\Asignature(?:_|\z)/
            || $code =~ /\A(?:missing|wrong|untrusted|malformed)_signature\z/;

    my $row = _schema_row($diagnostic, $schema);
    return $row->{class} if defined $row;

    return undef;
}

sub diagnostics_schema_from_file {
    return schema_from_file(@_);
}

sub schema_from_file {
    my ($path) = @_;

    croak 'diagnostics_schema_path is required' if !defined($path) || $path eq '';
    return $SCHEMA_CACHE{$path} if exists $SCHEMA_CACHE{$path};

    open my $fh, '<:encoding(UTF-8)', $path or croak "open $path: $!";
    my $docs = do { local $/; <$fh> };
    close $fh or croak "close $path: $!";

    my ($block) = $docs =~ /^```diagnostic-schema\n(.*?)^```/ms;
    croak 'diagnostic-schema block not found' if !defined $block;

    my @lines = grep { /\S/ } split /\n/, $block;
    my $header = shift @lines // '';
    my $has_human_text = $header eq 'code|selector|class|required|optional|explanation|hint';
    croak "bad diagnostic schema header: $header"
        if $header ne 'code|selector|class|required|optional' && !$has_human_text;

    my @schema;
    for my $line (@lines) {
        my ($code, $selector, $class, $required, $optional, $explanation, $hint)
            = split /\|/, $line, $has_human_text ? 7 : 5;
        croak "bad diagnostic schema line: $line"
            if !defined($code) || !defined($selector) || !defined($class)
                || !defined($required) || !defined($optional);

        my $defaults = _default_registry_row($code, $selector);
        push @schema, {
            code        => $code,
            selector    => $selector,
            class       => $class,
            required    => [_schema_fields($required)],
            optional    => [_schema_fields($optional)],
            explanation => $explanation // $defaults->{explanation} // '',
            hint        => $hint // $defaults->{hint} // '',
        };
    }

    return $SCHEMA_CACHE{$path} = \@schema;
}

sub _schema_row {
    my ($diagnostic, $schema) = @_;

    my $code = $diagnostic->{code} // '';
    my @candidates = grep { ($_->{code} // '') eq $code } @$schema;
    for my $row (@candidates) {
        return $row if _selector_matches($diagnostic, $row->{selector});
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

sub _unique_sorted {
    my (%seen, @values);
    for my $value (@_) {
        next if !defined($value) || $value eq '';
        next if $seen{$value}++;
        push @values, $value;
    }

    return sort @values;
}

sub _array_ref {
    my ($value, $name) = @_;
    croak "$name must be an array reference" if ref($value) ne 'ARRAY';
    return $value;
}

sub _schema_fields {
    my ($text) = @_;
    return () if !defined($text) || $text eq '' || $text eq '-';
    return split /,/, $text;
}

sub _default_registry_row {
    my ($code, $selector) = @_;
    return $DEFAULT_REGISTRY_BY_KEY{_registry_key_fields($code, $selector)} // {};
}

sub _registry_key {
    my ($row) = @_;
    return _registry_key_fields($row->{code}, $row->{selector});
}

sub _registry_key_fields {
    my ($code, $selector) = @_;
    return join "\0", $code // '', $selector // '*';
}

sub _clone {
    my ($value) = @_;

    if (ref($value) eq 'ARRAY') {
        return [map { _clone($_) } @$value];
    }

    if (ref($value) eq 'HASH') {
        return { map { $_ => _clone($value->{$_}) } keys %$value };
    }

    return $value;
}

1;

__END__

=head1 NAME

GobanFTP::Diagnostics - stable diagnostic code and class helpers

=cut
