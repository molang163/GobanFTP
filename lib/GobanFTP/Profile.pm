package GobanFTP::Profile;

use v5.34;
use strict;
use warnings;

use Carp qw(croak);
use Exporter qw(import);

our @EXPORT_OK = qw(profile profile_ids profile_version known_profile);

my @PROFILE_IDS = qw(
    local-goftp1
    ftp-goftp1
    git-tree-goftp1
    dns-record-goftp1
    webdav-goftp1
    signed-hmac-goftp1
);

my %PROFILES = (
    'local-goftp1' => {
        profile_id     => 'local-goftp1',
        profile_status => 'implemented',
        consensus_version => 'GOFTP-PROFILE/local-goftp1/1',
        substrate      => 'local filesystem directory tree',
        adapter_id     => 'local-listing-goftp1',
        adapter_status => 'implemented',
        auth_stance    => 'unsigned',
    },
    'ftp-goftp1' => {
        profile_id     => 'ftp-goftp1',
        profile_status => 'implemented',
        consensus_version => 'GOFTP-PROFILE/ftp-goftp1/1',
        substrate      => 'FTP directory listing',
        adapter_id     => 'ftp-listing-goftp1',
        adapter_status => 'implemented',
        auth_stance    => 'transport-auth-only',
    },
    'git-tree-goftp1' => {
        profile_id     => 'git-tree-goftp1',
        profile_status => 'planned',
        consensus_version => 'GOFTP-PROFILE/git-tree-goftp1/1',
        substrate      => 'Git-like tree fixture',
        adapter_id     => 'git-tree-listing-goftp1',
        adapter_status => 'read-normalizer',
        auth_stance    => 'unsigned',
    },
    'dns-record-goftp1' => {
        profile_id     => 'dns-record-goftp1',
        profile_status => 'planned',
        consensus_version => 'GOFTP-PROFILE/dns-record-goftp1/1',
        substrate      => 'DNS-like record fixture',
        adapter_id     => 'dns-record-listing-goftp1',
        adapter_status => 'read-normalizer',
        auth_stance    => 'unsigned',
    },
    'webdav-goftp1' => {
        profile_id     => 'webdav-goftp1',
        profile_status => 'planned',
        consensus_version => 'GOFTP-PROFILE/webdav-goftp1/1',
        substrate      => 'WebDAV PROPFIND fixture',
        adapter_id     => 'webdav-listing-goftp1',
        adapter_status => 'read-normalizer',
        auth_stance    => 'unsigned',
    },
    'signed-hmac-goftp1' => {
        profile_id     => 'signed-hmac-goftp1',
        profile_status => 'implemented',
        consensus_version => 'GOFTP-PROFILE/signed-hmac-goftp1/1',
        substrate      => 'GOFTP/1 event listing with per-event HMAC attestations',
        adapter_id     => 'signed-hmac-listing-goftp1',
        adapter_status => 'implemented',
        auth_stance    => 'signed-consensus',
    },
);

sub profile_ids {
    return @PROFILE_IDS;
}

sub known_profile {
    my ($profile_id) = @_;
    return defined($profile_id) && exists $PROFILES{$profile_id} ? 1 : 0;
}

sub profile_version {
    my ($profile_id) = @_;
    return profile($profile_id)->{consensus_version};
}

sub profile {
    my ($profile_id) = @_;
    croak 'profile_id is required' if !defined($profile_id) || $profile_id eq '';
    croak "unknown profile_id: $profile_id" if !exists $PROFILES{$profile_id};

    return { %{ $PROFILES{$profile_id} } };
}

1;

__END__

=head1 NAME

GobanFTP::Profile - v1 profile registry

=cut
