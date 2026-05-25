package GobanFTP::JSON;

use v5.34;
use strict;
use warnings;

use Carp qw(croak);
use Exporter qw(import);
use JSON::PP;

our @EXPORT_OK = qw(encode_json_doc json_doc);

sub json_doc {
    my (%args) = @_;

    my $schema = $args{schema};
    croak 'schema is required' if !defined($schema) || $schema !~ /\Agobanftp[.][a-z0-9_.-]+[.]v1\z/;

    my %doc = (
        schema  => $schema,
        version => '1.1',
    );

    for my $key (sort keys %args) {
        next if $key eq 'schema' || $key eq 'version';
        $doc{$key} = $args{$key};
    }

    return \%doc;
}

sub encode_json_doc {
    my (%args) = @_;

    my $doc = json_doc(%args);
    return JSON::PP->new->canonical(1)->encode($doc) . "\n";
}

1;

__END__

=head1 NAME

GobanFTP::JSON - scoped v1.1 JSON document helpers

=cut
