package GobanFTP::Auth::PublishToken;

use v5.34;
use strict;
use warnings;

use Carp qw(croak);
use Exporter qw(import);

use GobanFTP::Auth::HMAC qw(hmac_sha256_hex key_id_for_secret);
use GobanFTP::Auth::TrustReport qw(trust_lifecycle_decision);
use GobanFTP::Filename::Grammar qw(parse_event);

our @EXPORT_OK = qw(
    publish_authorization_result
    publish_token_preimage
    sign_publish_token
    verify_publish_token
);

my $VERSION = 'GOFTP-HMAC-PUBLISH/1';
my $PROFILE = 'signed-hmac-goftp1';
my $ALGORITHM = 'hmac-sha256';
my $PURPOSE = 'publish';
my $SIGNATURE_RE = qr/\A[0-9a-f]{64}\z/;

sub publish_token_preimage {
    my %args = _args(@_);
    my $fields = _publish_fields_or_croak(\%args);

    return _publish_preimage($fields);
}

sub sign_publish_token {
    my %args = _args(@_);
    my $key = _key_or_croak(\%args);
    my $key_id = exists $args{key_id}
        ? _clean_field_or_croak('key_id', $args{key_id})
        : key_id_for_secret($key);

    my %fields = %args;
    $fields{key_id} = $key_id;

    my $publish = _publish_fields_or_croak(\%fields);
    my $signature = hmac_sha256_hex($key, _publish_preimage($publish));

    return {
        version         => $publish->{version},
        purpose         => $publish->{purpose},
        algorithm       => $publish->{algorithm},
        profile         => $publish->{profile},
        game_descriptor => $publish->{game_descriptor},
        event_basename  => $publish->{event_basename},
        event_id        => $publish->{event_id},
        key_id          => $publish->{key_id},
        mac             => $signature,
        signature       => $signature,
        signature_hex   => $signature,
    };
}

sub verify_publish_token {
    my %args = _args(@_);
    my ($record, $record_error) = _token_record(\%args);
    return _verification_result(0, $record_error) if defined $record_error;

    my $key = _key_or_croak(\%args);

    for my $field (qw(version profile purpose algorithm game_descriptor event_basename event_id key_id)) {
        next if !exists $args{$field};
        next if !exists $record->{$field};
        next if !defined $args{$field} || !defined $record->{$field};

        if ($args{$field} ne $record->{$field}) {
            return _verification_result(0, "$field.mismatch");
        }
    }

    my %fields = %$record;
    for my $field (qw(version profile purpose algorithm game_descriptor event_basename event_id key_id signature signature_hex mac hmac_sha256)) {
        next if !exists $args{$field};
        next if $field eq 'signature' && ref $args{$field};
        $fields{$field} = $args{$field};
    }
    $fields{signature} = _signature_value(\%fields);

    return _verification_result(0, 'signature.missing')
        if !defined($fields{signature}) || $fields{signature} eq '';
    return _verification_result(0, 'signature.format')
        if $fields{signature} !~ $SIGNATURE_RE;

    my ($publish, $field_error) = _publish_fields_for_verify(\%fields);
    return _verification_result(0, $field_error) if defined $field_error;

    my $expected = hmac_sha256_hex($key, _publish_preimage($publish));
    my $ok = _constant_time_eq($expected, $fields{signature});

    return _verification_result(
        $ok,
        $ok ? undef : 'signature.mismatch',
        version         => $publish->{version},
        profile         => $publish->{profile},
        purpose         => $publish->{purpose},
        algorithm       => $publish->{algorithm},
        game_descriptor => $publish->{game_descriptor},
        event_basename  => $publish->{event_basename},
        event_id        => $publish->{event_id},
        key_id          => $publish->{key_id},
        signature       => $fields{signature},
    );
}

sub publish_authorization_result {
    my %args = _args(@_);

    my $profile_id = _required_field(\%args, 'profile_id');
    my $game = _required_field(\%args, 'game_descriptor');
    my $event = _required_field(\%args, 'event_basename');
    my $token = _hash_ref($args{token}, 'token');
    my $trusted_keys = _hash_ref($args{trusted_hmac_keys} // {}, 'trusted_hmac_keys');
    my $statuses = _hash_ref(
        $args{trusted_hmac_key_statuses} // {},
        'trusted_hmac_key_statuses',
    );

    croak "unsupported publish token profile: $profile_id" if $profile_id ne $PROFILE;

    my (undef, $parse_error) = parse_event($event, game_descriptor => $game);
    if (defined $parse_error) {
        return _authorization_result(0, {
            code  => 'parse_event',
            name  => $event,
            error => $parse_error,
        });
    }

    my $event_id = _event_id_from_basename($event);
    my $key_id = $token->{key_id} // '';
    if ($key_id eq '') {
        return _authorization_result(0, {
            code         => 'malformed_signature',
            profile_id   => $profile_id,
            signature_id => $event_id,
            reason       => 'key_id.missing',
        });
    }

    if ($key_id =~ /\Ak1[.]/) {
        return _authorization_result(0, {
            code       => 'untrusted_signature',
            profile_id => $profile_id,
            name       => $event,
            event_id   => $event_id,
            key_id     => $key_id,
            reason     => 'key_id.public_key_namespace',
        });
    }

    if (!exists $trusted_keys->{$key_id}) {
        return _authorization_result(0, {
            code       => 'untrusted_signature',
            profile_id => $profile_id,
            name       => $event,
            event_id   => $event_id,
            key_id     => $key_id,
            reason     => 'key.untrusted',
        });
    }

    my $decision = trust_lifecycle_decision(
        status  => $statuses->{$key_id} // 'trusted',
        purpose => 'publish',
    );
    if (!$decision->{accepted}) {
        return _authorization_result(0, {
            code       => 'untrusted_signature',
            profile_id => $profile_id,
            name       => $event,
            event_id   => $event_id,
            key_id     => $key_id,
            reason     => $decision->{reason},
        });
    }

    my $verification = verify_publish_token(
        version         => $VERSION,
        purpose         => $PURPOSE,
        profile         => $profile_id,
        algorithm       => $ALGORITHM,
        game_descriptor => $game,
        event_basename  => $event,
        event_id        => $event_id,
        key_id          => $key_id,
        key             => $trusted_keys->{$key_id},
        signature       => $token,
    );
    return _authorization_result(1, undef, key_id => $key_id, event_id => $event_id)
        if $verification->{ok};

    return _authorization_result(
        0,
        _verification_diagnostic(
            verification => $verification,
            profile_id   => $profile_id,
            event        => $event,
            event_id     => $event_id,
            key_id       => $key_id,
        ),
        key_id => $key_id,
        event_id => $event_id,
    );
}

sub _verification_diagnostic {
    my (%args) = @_;

    my $error = $args{verification}{error} // 'signature.invalid';
    if ($error eq 'signature.missing') {
        return {
            code       => 'missing_signature',
            profile_id => $args{profile_id},
            name       => $args{event},
            event_id   => $args{event_id},
        };
    }

    if ($error eq 'signature.format' || $error =~ /(?:record|missing|invalid)\z/) {
        return {
            code         => 'malformed_signature',
            profile_id   => $args{profile_id},
            signature_id => $args{event_id},
            reason       => $error,
        };
    }

    return {
        code       => 'wrong_signature',
        profile_id => $args{profile_id},
        name       => $args{event},
        event_id   => $args{event_id},
        key_id     => $args{key_id},
        reason     => $error,
    };
}

sub _authorization_result {
    my ($authorized, $diagnostic, %fields) = @_;

    return {
        authorized  => $authorized ? 1 : 0,
        status      => $authorized ? 'authorized' : 'denied',
        diagnostics => defined($diagnostic) ? [$diagnostic] : [],
        %fields,
    };
}

sub _publish_fields_or_croak {
    my ($args) = @_;

    my $fields = {
        version         => _field_or_default($args, 'version', $VERSION),
        profile         => _field_or_default($args, 'profile', $PROFILE),
        purpose         => _field_or_default($args, 'purpose', $PURPOSE),
        algorithm       => _field_or_default($args, 'algorithm', $ALGORITHM),
        game_descriptor => _required_field($args, 'game_descriptor'),
        event_basename  => _required_field($args, 'event_basename'),
        event_id        => exists $args->{event_id}
            ? _clean_field_or_croak('event_id', $args->{event_id})
            : _event_id_from_basename($args->{event_basename}),
        key_id          => _required_field($args, 'key_id'),
    };

    _croak_if_path('game_descriptor', $fields->{game_descriptor});
    _croak_if_path('event_basename', $fields->{event_basename});
    _croak_if_event_id_mismatch($fields->{event_basename}, $fields->{event_id});
    _croak_if_bad_publish_constants($fields);

    my (undef, $error) = parse_event(
        $fields->{event_basename},
        game_descriptor => $fields->{game_descriptor},
    );
    croak "parse_event:$error" if defined $error;

    return $fields;
}

sub _publish_fields_for_verify {
    my ($args) = @_;

    my %fields = (
        version         => exists $args->{version} ? $args->{version} : $VERSION,
        profile         => exists $args->{profile} ? $args->{profile} : $PROFILE,
        purpose         => exists $args->{purpose} ? $args->{purpose} : $PURPOSE,
        algorithm       => exists $args->{algorithm} ? $args->{algorithm} : $ALGORITHM,
        game_descriptor => $args->{game_descriptor},
        event_basename  => $args->{event_basename},
        event_id        => exists $args->{event_id}
            ? $args->{event_id}
            : _event_id_from_basename_or_undef($args->{event_basename}),
        key_id          => $args->{key_id},
    );

    for my $field (qw(version profile purpose algorithm game_descriptor event_basename event_id key_id)) {
        return (undef, "$field.missing")
            if !defined($fields{$field}) || $fields{$field} eq '';
        return (undef, "$field.invalid")
            if index($fields{$field}, "\0") >= 0;
    }

    return (undef, 'game_descriptor.path') if $fields{game_descriptor} =~ m{/};
    return (undef, 'event_basename.path')  if $fields{event_basename} =~ m{/};
    return (undef, 'version.unsupported')  if $fields{version} ne $VERSION;
    return (undef, 'profile.unsupported')  if $fields{profile} ne $PROFILE;
    return (undef, 'purpose.unsupported')  if $fields{purpose} ne $PURPOSE;
    return (undef, 'algorithm.unsupported') if $fields{algorithm} ne $ALGORITHM;
    return (undef, 'event_id.mismatch')
        if !_event_id_matches_basename($fields{event_basename}, $fields{event_id});

    my (undef, $error) = parse_event(
        $fields{event_basename},
        game_descriptor => $fields{game_descriptor},
    );
    return (undef, "parse_event.$error") if defined $error;

    return (\%fields, undef);
}

sub _croak_if_bad_publish_constants {
    my ($fields) = @_;

    croak 'version is unsupported'   if $fields->{version} ne $VERSION;
    croak 'profile is unsupported'   if $fields->{profile} ne $PROFILE;
    croak 'purpose is unsupported'   if $fields->{purpose} ne $PURPOSE;
    croak 'algorithm is unsupported' if $fields->{algorithm} ne $ALGORITHM;
}

sub _publish_preimage {
    my ($fields) = @_;

    return join "\0",
        $fields->{version},
        'profile=' . $fields->{profile},
        'purpose=' . $fields->{purpose},
        'alg=' . $fields->{algorithm},
        'key_id=' . $fields->{key_id},
        'game=' . $fields->{game_descriptor},
        'event_id=' . $fields->{event_id},
        'event=' . $fields->{event_basename},
        '';
}

sub _token_record {
    my ($args) = @_;

    my $record = $args->{signature} // $args->{signature_record} // $args->{token};
    return (undef, 'signature.record') if !defined $record;

    if (!ref $record) {
        return ({
            signature => $record,
        }, undef);
    }

    return (undef, 'signature.record') if ref($record) ne 'HASH';

    my %record = %$record;
    $record{signature} //= _signature_value(\%record);
    $record{event_basename} //= $record{event};
    return (\%record, undef);
}

sub _signature_value {
    my ($fields) = @_;
    return $fields->{signature} // $fields->{signature_hex}
        // $fields->{mac} // $fields->{hmac_sha256};
}

sub _verification_result {
    my ($ok, $error, %fields) = @_;

    return {
        ok    => $ok ? 1 : 0,
        valid => $ok ? 1 : 0,
        defined($error) ? (error => $error) : (),
        %fields,
    };
}

sub _args {
    return %{ $_[0] } if @_ == 1 && ref($_[0]) eq 'HASH';
    croak 'named arguments must be key/value pairs' if @_ % 2;
    return @_;
}

sub _key_or_croak {
    my ($args) = @_;

    return $args->{key}    if exists $args->{key} && defined $args->{key};
    return $args->{secret} if exists $args->{secret} && defined $args->{secret};

    croak 'key is required';
}

sub _field_or_default {
    my ($args, $field, $default) = @_;
    my $value = exists $args->{$field} ? $args->{$field} : $default;
    return _clean_field_or_croak($field, $value);
}

sub _required_field {
    my ($args, $field) = @_;

    croak "$field is required" if !exists $args->{$field};
    return _clean_field_or_croak($field, $args->{$field});
}

sub _clean_field_or_croak {
    my ($field, $value) = @_;

    croak "$field is required" if !defined $value;
    croak "$field must not be empty" if $value eq '';
    croak "$field must not contain NUL" if index($value, "\0") >= 0;

    return $value;
}

sub _croak_if_path {
    my ($field, $value) = @_;

    croak "$field must be a basename" if $value =~ m{/};
}

sub _croak_if_event_id_mismatch {
    my ($event, $event_id) = @_;
    croak 'event_id mismatch' if !_event_id_matches_basename($event, $event_id);
}

sub _event_id_matches_basename {
    my ($event, $event_id) = @_;
    return defined($event) && defined($event_id)
        && $event =~ /[.]h-\Q$event_id\E\z/;
}

sub _event_id_from_basename {
    my ($event) = @_;
    my $event_id = _event_id_from_basename_or_undef($event);
    croak 'event_id missing' if !defined $event_id;
    return $event_id;
}

sub _event_id_from_basename_or_undef {
    my ($event) = @_;
    return undef if !defined $event;
    return $1 if $event =~ /[.]h-([a-z0-9]+)\z/;
    return undef;
}

sub _constant_time_eq {
    my ($left, $right) = @_;

    return 0 if !defined($left) || !defined($right);
    return 0 if length($left) != length($right);

    my $diff = 0;
    for my $i (0 .. length($left) - 1) {
        $diff |= ord(substr($left, $i, 1)) ^ ord(substr($right, $i, 1));
    }

    return $diff == 0 ? 1 : 0;
}

sub _hash_ref {
    my ($value, $name) = @_;
    croak "$name must be a hash reference" if ref($value) ne 'HASH';
    return $value;
}

1;

__END__

=head1 NAME

GobanFTP::Auth::PublishToken - HMAC publish authorization tokens

=cut
