package GobanFTP::Auth::HMAC;

use strict;
use warnings;

use bytes ();
use Carp qw(croak);
use Digest::SHA qw(sha256);
use Exporter qw(import);

our @EXPORT_OK = qw(
    hmac_sha256_hex
    key_id
    key_id_for_secret
    event_attestation_preimage
    sign_event
    verify_event_signature
);

my $BLOCK_SIZE = 64;
my $KEY_DOMAIN = "GOFTP-HMAC-KEY/1\0";
my $DEFAULT_VERSION = 'GOFTP-HMAC-EVENT/1';
my $DEFAULT_PROFILE = 'signed-hmac-goftp1';
my $DEFAULT_ALGORITHM = 'hmac-sha256';
my $BASE32HEX = '0123456789abcdefghijklmnopqrstuv';
my $SIGNATURE_RE = qr/\A[0-9a-f]{64}\z/;

sub hmac_sha256_hex {
    my ($key, $message) = @_;

    croak 'key is required'     if !defined $key;
    croak 'message is required' if !defined $message;

    $key = sha256($key) if bytes::length($key) > $BLOCK_SIZE;
    $key .= "\0" x ($BLOCK_SIZE - bytes::length($key));

    my @key_bytes = unpack 'C*', $key;
    my $ipad = pack 'C*', map { $_ ^ 0x36 } @key_bytes;
    my $opad = pack 'C*', map { $_ ^ 0x5c } @key_bytes;

    return unpack 'H*', sha256($opad . sha256($ipad . $message));
}

sub key_id {
    return key_id_for_secret(@_);
}

sub key_id_for_secret {
    my ($secret) = @_;

    croak 'secret is required' if !defined $secret;

    return substr _base32hex_no_padding(sha256($KEY_DOMAIN . $secret)), 0, 16;
}

sub event_attestation_preimage {
    my %args = _args(@_);
    my $fields = _attestation_fields_or_croak(\%args);

    return _event_preimage($fields);
}

sub sign_event {
    my %args = _args(@_);
    my $key = _key_or_croak(\%args);
    my $key_id = exists $args{key_id}
        ? _clean_field_or_croak('key_id', $args{key_id})
        : key_id_for_secret($key);

    my %fields = %args;
    $fields{key_id} = $key_id;

    my $attestation = _attestation_fields_or_croak(\%fields);
    my $signature = hmac_sha256_hex($key, _event_preimage($attestation));

    return {
        version         => $attestation->{version},
        algorithm       => $attestation->{algorithm},
        profile         => $attestation->{profile},
        game_descriptor => $attestation->{game_descriptor},
        event_basename  => $attestation->{event_basename},
        event_id        => $attestation->{event_id},
        key_id          => $attestation->{key_id},
        mac             => $signature,
        signature       => $signature,
        signature_hex   => $signature,
    };
}

sub verify_event_signature {
    my %args = _args(@_);
    my ($record, $record_error) = _signature_record(\%args);
    return _verification_result(0, $record_error) if defined $record_error;

    my $key = _key_or_croak(\%args);

    if (defined($record->{algorithm}) && $record->{algorithm} ne $DEFAULT_ALGORITHM) {
        return _verification_result(0, 'algorithm.unsupported');
    }

    for my $field (qw(version profile algorithm game_descriptor event_basename event_id key_id)) {
        next if !exists $args{$field};
        next if !exists $record->{$field};
        next if !defined $args{$field} || !defined $record->{$field};

        if ($args{$field} ne $record->{$field}) {
            return _verification_result(0, "$field.mismatch");
        }
    }

    my %fields = %{$record};
    for my $field (qw(version profile algorithm game_descriptor event_basename event_id key_id signature signature_hex mac hmac_sha256)) {
        next if !exists $args{$field};
        next if $field eq 'signature' && ref $args{$field};
        $fields{$field} = $args{$field};
    }

    $fields{signature} = _signature_value(\%fields);

    return _verification_result(0, 'signature.missing')
        if !defined($fields{signature}) || $fields{signature} eq '';

    return _verification_result(0, 'signature.format')
        if $fields{signature} !~ $SIGNATURE_RE;

    for my $field (qw(game_descriptor event_basename key_id)) {
        return _verification_result(0, "$field.missing")
            if !defined($fields{$field}) || $fields{$field} eq '';
    }

    my ($attestation, $field_error) = _attestation_fields_for_verify(\%fields);
    return _verification_result(0, $field_error) if defined $field_error;

    my $expected = hmac_sha256_hex($key, _event_preimage($attestation));
    my $ok = _constant_time_eq($expected, $fields{signature});

    return _verification_result(
        $ok,
        $ok ? undef : 'signature.mismatch',
        version         => $attestation->{version},
        profile         => $attestation->{profile},
        algorithm       => $attestation->{algorithm},
        game_descriptor => $attestation->{game_descriptor},
        event_basename  => $attestation->{event_basename},
        event_id        => $attestation->{event_id},
        key_id          => $attestation->{key_id},
        signature       => $fields{signature},
    );
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

sub _attestation_fields_or_croak {
    my ($args) = @_;

    my $fields = {
        version         => _field_or_default($args, 'version', $DEFAULT_VERSION),
        profile         => _field_or_default($args, 'profile', $DEFAULT_PROFILE),
        algorithm       => _field_or_default($args, 'algorithm', $DEFAULT_ALGORITHM),
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
    croak 'algorithm is unsupported' if $fields->{algorithm} ne $DEFAULT_ALGORITHM;

    return $fields;
}

sub _attestation_fields_for_verify {
    my ($args) = @_;

    my %fields = (
        version         => exists $args->{version} ? $args->{version} : $DEFAULT_VERSION,
        profile         => exists $args->{profile} ? $args->{profile} : $DEFAULT_PROFILE,
        algorithm       => exists $args->{algorithm} ? $args->{algorithm} : $DEFAULT_ALGORITHM,
        game_descriptor => $args->{game_descriptor},
        event_basename  => $args->{event_basename},
        event_id        => exists $args->{event_id}
            ? $args->{event_id}
            : _event_id_from_basename_or_undef($args->{event_basename}),
        key_id          => $args->{key_id},
    );

    for my $field (qw(version profile algorithm game_descriptor event_basename event_id key_id)) {
        return (undef, "$field.missing")
            if !defined($fields{$field}) || $fields{$field} eq '';

        return (undef, "$field.invalid")
            if index($fields{$field}, "\0") >= 0;
    }

    return (undef, 'game_descriptor.path') if $fields{game_descriptor} =~ m{/};
    return (undef, 'event_basename.path')  if $fields{event_basename} =~ m{/};
    return (undef, 'algorithm.unsupported') if $fields{algorithm} ne $DEFAULT_ALGORITHM;
    return (undef, 'event_id.mismatch')
        if !_event_id_matches_basename($fields{event_basename}, $fields{event_id});

    return (\%fields, undef);
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

    croak "$field is required"        if !defined $value;
    croak "$field must not be empty"  if $value eq '';
    croak "$field must not contain NUL" if index($value, "\0") >= 0;

    return $value;
}

sub _croak_if_path {
    my ($field, $value) = @_;

    croak "$field must be a basename" if $value =~ m{/};
}

sub _event_preimage {
    my ($fields) = @_;

    return join "\0",
        $fields->{version},
        'profile=' . $fields->{profile},
        'alg=' . $fields->{algorithm},
        'key_id=' . $fields->{key_id},
        'game=' . $fields->{game_descriptor},
        'event_id=' . $fields->{event_id},
        'event=' . $fields->{event_basename},
        '';
}

sub _signature_record {
    my ($args) = @_;
    my $record;

    if (exists $args->{attestation}) {
        return ({}, 'signature.record') if ref($args->{attestation}) ne 'HASH';
        $record = { %{ $args->{attestation} } };
    }
    elsif (exists $args->{signature_record}) {
        return ({}, 'signature.record') if ref($args->{signature_record}) ne 'HASH';
        $record = { %{ $args->{signature_record} } };
    }
    elsif (exists $args->{signature} && ref($args->{signature}) eq 'HASH') {
        $record = { %{ $args->{signature} } };
    }
    elsif (exists $args->{signature}) {
        $record = { signature => $args->{signature} };
    }
    elsif (exists $args->{signature_hex}) {
        $record = { signature_hex => $args->{signature_hex} };
    }
    elsif (exists $args->{mac}) {
        $record = { mac => $args->{mac} };
    }
    elsif (exists $args->{hmac_sha256}) {
        $record = { hmac_sha256 => $args->{hmac_sha256} };
    }
    else {
        return ({}, 'signature.missing');
    }

    $record->{signature} = _signature_value($record);

    return ($record, undef);
}

sub _signature_value {
    my ($record) = @_;

    for my $field (qw(signature signature_hex mac hmac_sha256)) {
        return $record->{$field}
            if defined($record->{$field}) && $record->{$field} ne '';
    }

    return undef;
}

sub _verification_result {
    my ($ok, $error, %extra) = @_;

    return {
        ok    => $ok ? 1 : 0,
        valid => $ok ? 1 : 0,
        error => $error,
        %extra,
    };
}

sub _constant_time_eq {
    my ($left, $right) = @_;
    return 0 if !defined $left || !defined $right;

    my $max = length($left) > length($right) ? length($left) : length($right);
    my $diff = length($left) ^ length($right);

    for (my $i = 0; $i < $max; $i++) {
        my $l = $i < length($left)  ? ord substr($left, $i, 1)  : 0;
        my $r = $i < length($right) ? ord substr($right, $i, 1) : 0;
        $diff |= $l ^ $r;
    }

    return $diff == 0;
}

sub _event_id_from_basename {
    my ($event_basename) = @_;
    croak 'event_basename is required' if !defined $event_basename;
    return $1 if $event_basename =~ /[.]h-([0-9a-v]{16})\z/;
    croak 'event_basename must end with a visible event id';
}

sub _event_id_from_basename_or_undef {
    my ($event_basename) = @_;
    return undef if !defined $event_basename;
    return $1 if $event_basename =~ /[.]h-([0-9a-v]{16})\z/;
    return undef;
}

sub _croak_if_event_id_mismatch {
    my ($event_basename, $event_id) = @_;
    croak 'event_id must match event_basename'
        if !_event_id_matches_basename($event_basename, $event_id);
}

sub _event_id_matches_basename {
    my ($event_basename, $event_id) = @_;
    return 0 if !defined($event_basename) || !defined($event_id);
    return $event_basename =~ /[.]h-\Q$event_id\E\z/ ? 1 : 0;
}

sub _base32hex_no_padding {
    my ($bytes) = @_;

    my $bits = 0;
    my $bit_count = 0;
    my $out = '';

    for my $byte (unpack 'C*', $bytes) {
        $bits = ($bits << 8) | $byte;
        $bit_count += 8;

        while ($bit_count >= 5) {
            $bit_count -= 5;
            $out .= substr $BASE32HEX, ($bits >> $bit_count) & 0x1f, 1;
        }

        $bits &= (1 << $bit_count) - 1;
    }

    if ($bit_count) {
        $out .= substr $BASE32HEX, ($bits << (5 - $bit_count)) & 0x1f, 1;
    }

    return $out;
}

1;

__END__

=head1 NAME

GobanFTP::Auth::HMAC - advisory HMAC-SHA256 event attestations

=cut
