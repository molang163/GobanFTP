use v5.34;
use strict;
use warnings;

use FindBin;
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::Auth::Boundary qw(
    auth_boundary_record
    is_public_key_namespace_selector
    publish_preflight_scope
);

my $boundary = auth_boundary_record();
is $boundary->{schema}, 'gobanftp.auth.boundary.v1', 'auth boundary has scoped schema';
is $boundary->{version}, '1.1', 'auth boundary has version 1.1';
is $boundary->{unsigned_replay}{changes_goftp1_replay}, 0, 'unsigned replay remains unchanged';
is $boundary->{advisory_trust}{production_authorization}, 0, 'advisory trust is not production authorization';
is $boundary->{signed_hmac_witness_gate}{accepts_public_key_namespace_selectors}, 0,
    'signed HMAC does not accept public key namespace selectors';
is $boundary->{transport_credentials}{exposed_in_output}, 0, 'transport credentials are not output material';

my $scope = publish_preflight_scope();
is $scope->{scope}, 'fixture-preflight', 'publish preflight scope is fixture-preflight';
is $scope->{production_authorization}, 0, 'publish preflight is not production authorization';
is $scope->{changes_goftp1_replay}, 0, 'publish preflight does not change GOFTP/1 replay';

ok is_public_key_namespace_selector('k1.abc'), 'k1. namespace is recognized as public key namespace';
ok !is_public_key_namespace_selector('hmac-key-id'), 'ordinary HMAC key id is not k1. namespace';

done_testing;
