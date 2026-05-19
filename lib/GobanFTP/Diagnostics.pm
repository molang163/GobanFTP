package GobanFTP::Diagnostics;

use v5.34;
use strict;
use warnings;

use Carp qw(croak);
use Exporter qw(import);

our @EXPORT_OK = qw(
    default_diagnostics_schema
    diagnostic_class
    diagnostic_classes
    diagnostic_codes
    diagnostics_schema_from_file
    replay_status
    schema_from_file
);

my %SCHEMA_CACHE;
my @DEFAULT_SCHEMA = map {
    my ($code, $selector, $class) = @$_;
    +{
        code     => $code,
        selector => $selector,
        class    => $class,
    };
} (
    ['parse_event',           'error=event_id.*', 'event-id'],
    ['parse_event',           'error=*',          'parse'],
    ['parse_game_descriptor', '*',                'parse'],
    ['parse_public_key',      '*',                'parse'],
    ['parse_hmac_key',        '*',                'parse'],
    ['parse_publish_token',   '*',                'parse'],
    ['parse_trust',           '*',                'parse'],
    ['invalid_event_item',    '*',                'parse'],
    ['event_id_collision',    '*',                'event-id'],
    ['missing_parent',        '*',                'dag'],
    ['parent_not_move',       '*',                'dag'],
    ['cycle',                 '*',                'dag'],
    ['dangling_ack_target',   '*',                'dag'],
    ['ack_target_not_move',   '*',                'dag'],
    ['ack_target_invalid',    '*',                'dag'],
    ['wrong_color',           '*',                'rules'],
    ['wrong_player',          '*',                'rules'],
    ['wrong_ply',             '*',                'rules'],
    ['illegal_move',          '*',                'rules'],
    ['parent_not_legal',      '*',                'rules'],
    ['ack_wrong_player',      '*',                'rules'],
    ['rules',                 '*',                'rules'],
    ['fork',                  '*',                'fork'],
    ['missing_signature',     '*',                'signature'],
    ['wrong_signature',       '*',                'signature'],
    ['untrusted_signature',   '*',                'signature'],
    ['malformed_signature',   '*',                'signature'],
);

sub default_diagnostics_schema {
    return [map { +{ %$_ } } @DEFAULT_SCHEMA];
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
    $schema = _array_ref($schema // [], 'schema');

    return _unique_sorted(map { diagnostic_class($_, $schema) // 'unknown' } @$diagnostics);
}

sub diagnostic_class {
    my ($diagnostic, $schema) = @_;
    croak 'diagnostic must be a hash reference' if ref($diagnostic) ne 'HASH';
    $schema = _array_ref($schema // [], 'schema');

    my $code = $diagnostic->{code} // '';
    return 'signature'
        if $code =~ /\Asignature(?:_|\z)/
            || $code =~ /\A(?:missing|wrong|untrusted|malformed)_signature\z/;

    my @candidates = grep { ($_->{code} // '') eq $code } @$schema;
    for my $row (@candidates) {
        return $row->{class} if _selector_matches($diagnostic, $row->{selector});
    }

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
    croak "bad diagnostic schema header: $header"
        if $header ne 'code|selector|class|required|optional';

    my @schema;
    for my $line (@lines) {
        my ($code, $selector, $class, $required, $optional) = split /\|/, $line, 5;
        croak "bad diagnostic schema line: $line"
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

1;

__END__

=head1 NAME

GobanFTP::Diagnostics - stable diagnostic code and class helpers

=cut
