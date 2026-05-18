package GobanFTP::Auth::TrustReport;

use v5.34;
use strict;
use warnings;

use Carp qw(croak);
use Exporter qw(import);

our @EXPORT_OK = qw(
    parse_trust_tsv
    trust_report_summary
);

my @TRUST_COLUMNS = qw(
    key_id
    suite
    principal
    role
    status
    not_before
    not_after
    revoked_at
    reason
);
my %TRUST_STATUS = map { $_ => 1 } qw(trusted rotated revoked expired);
my %TRUST_ABSENT = map { $_ => 1 } qw(not_before not_after revoked_at reason);

sub trust_report_summary {
    my %args = @_ == 1 && ref($_[0]) eq 'HASH' ? %{ $_[0] } : @_;

    my $public_keys = _array_ref($args{public_keys} // [], 'public_keys');
    my $trust_tsv = $args{trust_tsv};

    my %public_by_id;
    for my $index (0 .. $#$public_keys) {
        my $key = _hash_ref($public_keys->[$index], "public_keys[$index]");
        my $key_id = _key_id($key->{key_id}, "public_keys[$index].key_id");
        croak 'parse_public_key:duplicate_key' if exists $public_by_id{$key_id};
        $public_by_id{$key_id} = $key;
    }

    my @records = defined($trust_tsv) && $trust_tsv ne ''
        ? parse_trust_tsv($trust_tsv)
        : ();
    _validate_trust_records(\@records, \%public_by_id);

    my %by_status = map { $_ => [] } qw(trusted rotated revoked expired);
    for my $record (@records) {
        push @{ $by_status{ $record->{status} } }, $record->{key_id};
    }

    for my $status (keys %by_status) {
        @{ $by_status{$status} } = sort @{ $by_status{$status} };
    }

    my $trust_status = @records ? 'advisory'
        : keys(%public_by_id) ? 'untrusted'
        :                       'unsigned';

    return {
        status           => $trust_status,
        public_key_count => scalar(keys %public_by_id),
        public_key_ids   => [ sort keys %public_by_id ],
        record_count     => scalar(@records),
        trusted_count    => scalar @{ $by_status{trusted} },
        trusted_key_ids  => $by_status{trusted},
        rotated_count    => scalar @{ $by_status{rotated} },
        rotated_key_ids  => $by_status{rotated},
        revoked_count    => scalar @{ $by_status{revoked} },
        revoked_key_ids  => $by_status{revoked},
        expired_count    => scalar @{ $by_status{expired} },
        expired_key_ids  => $by_status{expired},
    };
}

sub parse_trust_tsv {
    my ($text) = @_;

    croak 'parse_trust:record.missing' if !defined $text;

    my @lines = map { s/\r\z//r } split /\n/, $text, -1;
    pop @lines while @lines && $lines[-1] eq '';
    croak 'parse_trust:header' if !@lines || shift(@lines) ne 'GOFTP-TRUST/1';

    my $column_header = join "\t", @TRUST_COLUMNS;
    croak 'parse_trust:columns' if !@lines || shift(@lines) ne $column_header;

    my @records;
    my %seen_key_id;
    for my $index (0 .. $#lines) {
        my $line = $lines[$index];
        next if $line eq '';

        my @fields = split /\t/, $line, -1;
        croak 'parse_trust:field_count' if @fields != @TRUST_COLUMNS;

        my %record;
        @record{@TRUST_COLUMNS} = @fields;
        _validate_record(\%record);

        croak 'parse_trust:duplicate_key' if $seen_key_id{ $record{key_id} }++;
        push @records, \%record;
    }

    return @records;
}

sub _validate_trust_records {
    my ($records, $public_by_id) = @_;

    for my $record (@$records) {
        my $key = $public_by_id->{ $record->{key_id} };
        croak 'parse_trust:key.missing' if !defined $key;
        croak 'parse_trust:suite.mismatch'
            if ($key->{suite} // '') ne $record->{suite};
    }

    return 1;
}

sub _validate_record {
    my ($record) = @_;

    _key_id($record->{key_id}, 'key_id');

    croak 'parse_trust:suite.unsupported'
        if ($record->{suite} // '') ne 'fixture-ed25519-v1';
    croak 'parse_trust:principal'
        if !_public_token($record->{principal});
    croak 'parse_trust:role'
        if !_public_token($record->{role});
    croak 'parse_trust:status'
        if !$TRUST_STATUS{ $record->{status} // '' };

    for my $field (qw(not_before not_after revoked_at)) {
        next if $record->{$field} eq '-';
        croak "parse_trust:$field"
            if $record->{$field} !~ /\A[0-9]{4}-[0-9]{2}-[0-9]{2}\z/;
    }

    croak 'parse_trust:reason'
        if $record->{reason} ne '-' && !_public_token($record->{reason});

    for my $field (keys %TRUST_ABSENT) {
        croak "parse_trust:$field.missing"
            if !defined($record->{$field}) || $record->{$field} eq '';
    }

    return 1;
}

sub _key_id {
    my ($value, $name) = @_;

    croak 'parse_trust:key_id' if !defined($value) || $value !~ /\Ak1[.][0-9a-v]{32}\z/;
    return $value;
}

sub _public_token {
    my ($value) = @_;
    return defined($value) && $value =~ /\A[A-Za-z0-9._:-]+\z/;
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

GobanFTP::Auth::TrustReport - public advisory trust fixture summaries

=cut
