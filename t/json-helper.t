use v5.34;
use strict;
use warnings;

use FindBin;
use JSON::PP qw(decode_json);
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::JSON qw(encode_json_doc json_doc);

my $doc = json_doc(
    schema => 'gobanftp.example.v1',
    status => 'ok',
);

is $doc->{schema}, 'gobanftp.example.v1', 'json_doc keeps the scoped schema';
is $doc->{version}, '1.1', 'json_doc pins the beta JSON contract version';
is $doc->{status}, 'ok', 'json_doc carries caller fields';

my $version_override = json_doc(
    schema  => 'gobanftp.example.v1',
    version => '9.9',
    status  => 'ok',
);
is $version_override->{version}, '1.1', 'caller-provided version cannot override output version';

my $encoded = encode_json_doc(
    schema => 'gobanftp.example.v1',
    zed    => 1,
    alpha  => 2,
);
like $encoded, qr/\n\z/, 'encoded JSON ends with a newline';
my $roundtrip = decode_json($encoded);
is $roundtrip->{schema}, 'gobanftp.example.v1', 'encoded document is parseable';
is $roundtrip->{version}, '1.1', 'encoded document includes version';

my $encoded_override = encode_json_doc(
    schema  => 'gobanftp.example.v1',
    version => '9.9',
);
my $override_roundtrip = decode_json($encoded_override);
is $override_roundtrip->{version}, '1.1', 'encoded document ignores caller-provided version';

like exception(sub { json_doc(schema => 'example.v1') }),
    qr/schema is required/,
    'schema must stay under the gobanftp namespace';

done_testing;

sub exception {
    my ($code) = @_;

    my $error;
    eval { $code->(); 1 } or $error = $@;

    return $error;
}
