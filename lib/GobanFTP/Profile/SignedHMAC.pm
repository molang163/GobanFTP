package GobanFTP::Profile::SignedHMAC;

use v5.34;
use strict;
use warnings;

use Carp qw(croak);
use Exporter qw(import);

use GobanFTP::Auth::HMAC qw(verify_event_signature);
use GobanFTP::EventSetRoot qw(event_set_root_result);

our @EXPORT_OK = qw(is_signed_hmac_profile signed_hmac_event_set_result);

sub is_signed_hmac_profile {
    my ($profile_id) = @_;
    return defined($profile_id) && $profile_id eq 'signed-hmac-goftp1';
}

sub signed_hmac_event_set_result {
    my %args = _args(@_);

    my $profile_id      = _required($args{profile_id}, 'profile_id');
    my $game_descriptor = _required($args{game_descriptor}, 'game_descriptor');
    my $unsigned_result = _hash_ref($args{unsigned_result}, 'unsigned_result');
    my $attestations    = _hmac_attestation_index(_array_ref(
        $args{hmac_attestations} // [],
        'hmac_attestations',
    ));
    my $trusted_keys    = _hash_ref($args{trusted_hmac_keys} // {}, 'trusted_hmac_keys');

    croak "unsupported signed HMAC profile: $profile_id"
        if !is_signed_hmac_profile($profile_id);

    my (@signed_events, @signature_diagnostics);
    for my $event (@{ $unsigned_result->{accepted_events} // [] }) {
        my ($ok, $diagnostic) = _verify_event(
            profile_id        => $profile_id,
            game_descriptor   => $game_descriptor,
            event             => $event,
            attestation       => $attestations->{$event},
            trusted_hmac_keys => $trusted_keys,
        );

        if ($ok) {
            push @signed_events, $event;
            next;
        }

        push @signature_diagnostics, $diagnostic;
    }

    my $signed_result = event_set_root_result(
        game_descriptor => $game_descriptor,
        names           => \@signed_events,
    );

    return {
        %$signed_result,
        diagnostics => [
            @{ $unsigned_result->{diagnostics} // [] },
            @signature_diagnostics,
        ],
    };
}

sub _verify_event {
    my (%args) = @_;

    my $profile_id = _required($args{profile_id}, 'profile_id');
    my $event      = _required($args{event}, 'event');
    my @attestations = _attestation_records($args{attestation});
    if (!@attestations) {
        return (0, {
            code       => 'missing_signature',
            profile_id => $profile_id,
            name       => $event,
            event_id   => _event_id_from_basename($event),
        });
    }

    my @diagnostics;
    for my $attestation (@attestations) {
        my $diagnostic = _attestation_diagnostic(
            %args,
            profile_id  => $profile_id,
            event       => $event,
            attestation => $attestation,
        );

        return (1, undef) if !defined $diagnostic;
        push @diagnostics, $diagnostic;
    }

    return (0, _preferred_signature_diagnostic(@diagnostics));
}

sub _attestation_diagnostic {
    my (%args) = @_;

    my $profile_id  = _required($args{profile_id}, 'profile_id');
    my $event       = _required($args{event}, 'event');
    my $attestation = _hash_ref($args{attestation}, 'attestation');
    my $keys        = _hash_ref($args{trusted_hmac_keys}, 'trusted_hmac_keys');

    my $event_id = _event_id_from_basename($event);
    my $key_id   = $attestation->{key_id} // '';

    if (_is_public_key_namespace($key_id)) {
        return {
            code       => 'untrusted_signature',
            profile_id => $profile_id,
            name       => $event,
            event_id   => $event_id,
            key_id     => $key_id,
            reason     => 'key_id.public_key_namespace',
        };
    }

    if ($key_id eq '' || !exists $keys->{$key_id}) {
        return {
            code       => 'untrusted_signature',
            profile_id => $profile_id,
            name       => $event,
            event_id   => $event_id,
            key_id     => $key_id,
            reason     => $key_id eq '' ? 'key_id.missing' : 'key.untrusted',
        };
    }

    my $verification = _verify_hmac_attestation(
        profile_id       => $profile_id,
        game_descriptor  => _required($args{game_descriptor}, 'game_descriptor'),
        event            => $event,
        event_id         => $event_id,
        key_id           => $key_id,
        key              => $keys->{$key_id},
        attestation      => $attestation,
    );

    return undef if $verification->{ok};

    my $code = _signature_diagnostic_code($verification->{error});
    my %diagnostic = (
        code       => $code,
        profile_id => $profile_id,
        reason     => $verification->{error} // 'signature.invalid',
    );

    if ($code eq 'malformed_signature') {
        $diagnostic{signature_id} = $attestation->{signature_id} // $event_id;
    }
    else {
        $diagnostic{name}     = $event;
        $diagnostic{event_id} = $event_id;
        $diagnostic{key_id}   = $key_id;
    }

    return \%diagnostic;
}

sub _verify_hmac_attestation {
    my (%args) = @_;

    return verify_event_signature(
        version          => 'GOFTP-HMAC-EVENT/1',
        profile          => $args{profile_id},
        game_descriptor  => $args{game_descriptor},
        event_basename   => $args{event},
        event_id         => $args{event_id},
        key_id           => $args{key_id},
        key              => $args{key},
        signature_record => _normalized_attestation_record($args{attestation}),
    );
}

sub _normalized_attestation_record {
    my ($attestation) = @_;

    my %record = %$attestation;
    $record{signature} //= $record{signature_hex} // $record{hmac_sha256};
    $record{event_basename} //= $record{event};

    return \%record;
}

sub _signature_diagnostic_code {
    my ($error) = @_;
    return 'missing_signature'
        if !defined($error) || $error eq 'signature.missing';
    return 'malformed_signature'
        if $error eq 'signature.format' || $error eq 'signature.record';
    return 'wrong_signature';
}

sub _attestation_records {
    my ($attestation) = @_;
    return () if !defined $attestation;
    return @$attestation if ref($attestation) eq 'ARRAY';
    return ($attestation);
}

sub _preferred_signature_diagnostic {
    my (@diagnostics) = @_;

    my %priority = (
        wrong_signature     => 0,
        malformed_signature => 1,
        untrusted_signature => 2,
        missing_signature   => 3,
    );

    return (sort {
        ($priority{ $a->{code} // '' } // 99) <=> ($priority{ $b->{code} // '' } // 99)
            || (($a->{key_id} // '') cmp ($b->{key_id} // ''))
            || (($a->{signature_id} // '') cmp ($b->{signature_id} // ''))
            || (($a->{reason} // '') cmp ($b->{reason} // ''))
    } @diagnostics)[0];
}

sub _hmac_attestation_index {
    my ($records) = @_;

    my %by_event;
    for my $index (0 .. $#$records) {
        my $record = _hash_ref($records->[$index], "hmac_attestations[$index]");
        my $event = _required(
            $record->{event_basename} // $record->{event},
            "hmac_attestations[$index].event_basename",
        );
        push @{ $by_event{$event} }, $record;
    }

    return \%by_event;
}

sub _event_id_from_basename {
    my ($event) = @_;
    return undef if !defined $event;
    return $1 if $event =~ /[.]h-([a-z0-9]+)\z/;
    return undef;
}

sub _is_public_key_namespace {
    my ($key_id) = @_;
    return defined($key_id) && $key_id =~ /\Ak1[.]/;
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

1;

__END__

=head1 NAME

GobanFTP::Profile::SignedHMAC - signed-HMAC event acceptance gate

=cut
