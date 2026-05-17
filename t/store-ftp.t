use v5.34;
use strict;
use warnings;

use FindBin;
use Test::More;

use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/lib";

BEGIN {
    if (($ENV{GOBANFTP_FTP_TEST} // '') ne '1') {
        plan skip_all => 'live FTP test requires GOBANFTP_FTP_TEST=1';
    }

    my @missing = grep { !defined($ENV{$_}) || $ENV{$_} eq '' } qw(
        GOBANFTP_FTP_HOST
        GOBANFTP_FTP_USER
        GOBANFTP_FTP_PASSWORD
        GOBANFTP_FTP_ROOT
    );

    plan skip_all => 'live FTP test requires env: ' . join(', ', @missing) if @missing;
}

use GobanFTP::Store::FTP;
use GobanFTP::Test::StoreContract qw(run_store_contract);

my %args = (
    host     => $ENV{GOBANFTP_FTP_HOST},
    user     => $ENV{GOBANFTP_FTP_USER},
    password => $ENV{GOBANFTP_FTP_PASSWORD},
    root     => $ENV{GOBANFTP_FTP_ROOT},
);

$args{port} = $ENV{GOBANFTP_FTP_PORT} if defined($ENV{GOBANFTP_FTP_PORT}) && $ENV{GOBANFTP_FTP_PORT} ne '';
$args{passive} = $ENV{GOBANFTP_FTP_PASSIVE} ? 1 : 0 if defined($ENV{GOBANFTP_FTP_PASSIVE});

my $store = eval { GobanFTP::Store::FTP->new(%args) };
ok !$@, 'connected and logged in to live FTP server' or diag $@;
BAIL_OUT 'cannot continue live FTP store contract without a Store::FTP instance' if !$store;

my $suffix = time . "-$$";
my $game = "g1.id-ftp-live-$suffix.s9.r-chinese-area-v1.k7500.pb-alice.pw-bob";

run_store_contract(
    name                => 'Store::FTP live',
    store               => $store,
    game                => $game,
    strict_root_listing => 0,
);

$store->quit;

done_testing;
