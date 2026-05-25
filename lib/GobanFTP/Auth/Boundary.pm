package GobanFTP::Auth::Boundary;

use v5.34;
use strict;
use warnings;

use Exporter qw(import);

our @EXPORT_OK = qw(
    auth_boundary_record
    is_public_key_namespace_selector
    publish_preflight_scope
);

sub auth_boundary_record {
    return {
        schema  => 'gobanftp.auth.boundary.v1',
        version => '1.1',
        unsigned_replay => {
            scope => 'consensus-input',
            changes_goftp1_replay => 0,
        },
        advisory_trust => {
            scope => 'local-report',
            production_authorization => 0,
        },
        signed_hmac_witness_gate => {
            scope => 'fixture-witness',
            accepts_public_key_namespace_selectors => 0,
            production_authorization => 0,
        },
        publish_preflight => publish_preflight_scope(),
        transport_credentials => {
            scope => 'store-transport',
            exposed_in_output => 0,
            production_authorization => 0,
        },
    };
}

sub publish_preflight_scope {
    return {
        scope => 'fixture-preflight',
        status_literal_authorized_means => 'candidate event matches a checked publish token and trusted fixture HMAC key',
        production_authorization => 0,
        changes_goftp1_replay => 0,
        writes_transport_credentials => 0,
    };
}

sub is_public_key_namespace_selector {
    my ($value) = @_;
    return defined($value) && $value =~ /\Ak1[.]/ ? 1 : 0;
}

1;

__END__

=head1 NAME

GobanFTP::Auth::Boundary - explicit auth scope records for v1.1 candidate docs

=cut
