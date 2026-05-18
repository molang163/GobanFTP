use v5.34;
use strict;
use warnings;

use FindBin;
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::Profile qw(known_profile profile profile_ids profile_version);

my @profile_ids = qw(
    local-goftp1
    ftp-goftp1
    git-tree-goftp1
    dns-record-goftp1
    webdav-goftp1
);

my %expected = (
    'local-goftp1' => {
        profile_status => 'implemented',
        substrate      => 'local filesystem directory tree',
        adapter_id     => 'local-listing-goftp1',
        adapter_status => 'implemented',
        auth_stance    => 'unsigned',
    },
    'ftp-goftp1' => {
        profile_status => 'implemented',
        substrate      => 'FTP directory listing',
        adapter_id     => 'ftp-listing-goftp1',
        adapter_status => 'implemented',
        auth_stance    => 'transport-auth-only',
    },
    'git-tree-goftp1' => {
        profile_status => 'planned',
        substrate      => 'Git-like tree fixture',
        adapter_id     => 'git-tree-listing-goftp1',
        adapter_status => 'read-normalizer',
        auth_stance    => 'unsigned',
    },
    'dns-record-goftp1' => {
        profile_status => 'planned',
        substrate      => 'DNS-like record fixture',
        adapter_id     => 'dns-record-listing-goftp1',
        adapter_status => 'read-normalizer',
        auth_stance    => 'unsigned',
    },
    'webdav-goftp1' => {
        profile_status => 'planned',
        substrate      => 'WebDAV PROPFIND fixture',
        adapter_id     => 'webdav-listing-goftp1',
        adapter_status => 'read-normalizer',
        auth_stance    => 'unsigned',
    },
);

is_deeply [profile_ids()], \@profile_ids, 'profile ids are stable and ordered';

for my $profile_id (@profile_ids) {
    my $profile = profile($profile_id);

    is $profile->{profile_id}, $profile_id, "$profile_id records its id";
    is $profile->{consensus_version}, "GOFTP-PROFILE/$profile_id/1",
        "$profile_id consensus version is sealed";
    is profile_version($profile_id), $profile->{consensus_version},
        "$profile_id profile_version returns sealed version";
    for my $field (sort keys %{ $expected{$profile_id} }) {
        is $profile->{$field}, $expected{$profile_id}{$field},
            "$profile_id records $field";
    }
    ok known_profile($profile_id), "$profile_id is known";
}

ok !known_profile('signed-hmac-goftp1'), 'signed-HMAC is not in the unsigned production registry yet';
like dies(sub { profile('signed-hmac-goftp1') }), qr/unknown profile_id/,
    'unknown profile croaks';
like dies(sub { profile(undef) }), qr/profile_id is required/,
    'missing profile croaks';

done_testing;

sub dies {
    my ($code) = @_;
    my $error = '';
    eval { $code->(); 1 } or $error = $@;
    return $error;
}
