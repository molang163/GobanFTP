use v5.34;
use strict;
use warnings;

use Test::More;
use FindBin;
use JSON::PP qw(decode_json);

use lib "$FindBin::Bin/../lib";
use GobanFTP::GameSpec qw(parse_basename);

my $fixture_dir = "$FindBin::Bin/fixtures/gamespec";

for my $case (_read_jsonl("$fixture_dir/valid.jsonl")) {
    my ($fields, $error) = parse_basename($case->{name});

    is($error, undef, "$case->{id}: no error");
    is_deeply($fields, $case->{fields}, "$case->{id}: parsed fields");
    is_deeply(scalar parse_basename($case->{name}), $case->{fields},
        "$case->{id}: scalar context returns fields");
}

for my $case (_read_jsonl("$fixture_dir/invalid.jsonl")) {
    my ($fields, $error) = parse_basename($case->{name});

    is($fields, undef, "$case->{id}: no fields");
    is($error, $case->{error}, "$case->{id}: stable error code");
    is(scalar parse_basename($case->{name}), undef,
        "$case->{id}: scalar context returns undef");
}

done_testing;

sub _read_jsonl {
    my ($file) = @_;

    open my $fh, '<', $file or die "cannot open $file: $!";

    my @cases;
    while (defined(my $line = <$fh>)) {
        chomp $line;
        next if $line =~ /\A\s*\z/;
        push @cases, decode_json($line);
    }

    return @cases;
}
