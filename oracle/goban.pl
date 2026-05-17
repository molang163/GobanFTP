#!/usr/bin/env perl
use v5.34;
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";

use GobanFTP::Oracle::Smoke qw(run_smoke);

# +-------------------------------------------------------------------------+
# | GOFTP/1 ORACLE                                                          |
# | names are packets :: listing is reading :: board is projection           |
# | file bytes are shadow :: this wrapper only lights the smoke test         |
# +-------------------------------------------------------------------------+
#
# The array below is executable source art. The Perl cells themselves form the
# visual board passed to the smoke module. The glyphs are not protocol inputs:
# naming, hashing, replay, and rule behavior still live in lib/GobanFTP/*.
my @ORACLE_GOBAN = (
#             a        b        c        d        e        f        g        h        i
#        +--------+--------+--------+--------+--------+--------+--------+--------+--------+
    [   q(.)   , q(.)   , q(.)   , q(.)   , q(.)   , q(.)   , q(.)   , q(.)   , q(.)   ], # 9
#        +--------+--------+--------+--------+--------+--------+--------+--------+--------+
    [   q(.)   , q(.)   , q(.)   , q(.)   , q(.)   , q(.)   , q(.)   , q(.)   , q(.)   ], # 8
#        +--------+--------+--------+--------+--------+--------+--------+--------+--------+
    [   q(.)   , q(.)   , q(+)   , q(.)   , q(.)   , q(.)   , q(+)   , q(.)   , q(.)   ], # 7
#        +--------+--------+--------+--------+--------+--------+--------+--------+--------+
    [   q(.)   , q(.)   , q(.)   , q(.)   , q(.)   , q(.)   , q(.)   , q(.)   , q(.)   ], # 6
#        +--------+--------+--------+--------+--------+--------+--------+--------+--------+
    [   q(.)   , q(.)   , q(.)   , q(.)   , q(+)   , q(.)   , q(.)   , q(.)   , q(.)   ], # 5
#        +--------+--------+--------+--------+--------+--------+--------+--------+--------+
    [   q(.)   , q(.)   , q(.)   , q(.)   , q(.)   , q(.)   , q(.)   , q(.)   , q(.)   ], # 4
#        +--------+--------+--------+--------+--------+--------+--------+--------+--------+
    [   q(.)   , q(.)   , q(+)   , q(.)   , q(.)   , q(.)   , q(+)   , q(.)   , q(.)   ], # 3
#        +--------+--------+--------+--------+--------+--------+--------+--------+--------+
    [   q(.)   , q(.)   , q(.)   , q(.)   , q(.)   , q(.)   , q(.)   , q(.)   , q(.)   ], # 2
#        +--------+--------+--------+--------+--------+--------+--------+--------+--------+
    [   q(.)   , q(.)   , q(.)   , q(.)   , q(.)   , q(.)   , q(.)   , q(.)   , q(.)   ], # 1
#        +--------+--------+--------+--------+--------+--------+--------+--------+--------+
);

exit main(@ARGV) unless caller;

sub main {
    my (@argv) = @_;

    return run_smoke(visual_board => \@ORACLE_GOBAN) if @argv == 1 && $argv[0] eq '--smoke';
    return _usage(0) if @argv == 0 || (@argv == 1 && $argv[0] eq '--help');

    return _usage(64);
}

sub _usage {
    my ($status) = @_;

    my $fh = $status == 0 ? *STDOUT : *STDERR;
    print {$fh} "GOFTP/1 source-art smoke wrapper; protocol behavior lives in lib/GobanFTP/*.\n";
    print {$fh} "usage: perl oracle/goban.pl --smoke\n";

    return $status;
}
