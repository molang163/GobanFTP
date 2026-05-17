use v5.34;
use strict;
use warnings;

use FindBin;
use File::Temp qw(tempdir);
use Test::More;

use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/lib";

use GobanFTP::Store::Local;
use GobanFTP::Test::StoreContract qw(run_store_contract);

my $root = tempdir(CLEANUP => 1);
my $store = GobanFTP::Store::Local->new(root => $root);

run_store_contract(
    name  => 'Store::Local',
    store => $store,
);

done_testing;
