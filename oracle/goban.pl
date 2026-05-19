#!/usr/bin/env perl
use v5.34;
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";

use GobanFTP::Oracle::Smoke qw(run_smoke);

binmode STDOUT, ':unix:utf8';
binmode STDERR, ':unix:utf8';

# +-------------------------------------------------------------------------+
# | GOFTP/1 ORACLE                                                          |
# | altar is source :: goban is lens :: gate is a reader-side spark          |
# | names are packets :: listing is reading :: board is projection           |
# | file bytes are shadow :: this wrapper only lights the smoke test         |
# +-------------------------------------------------------------------------+
#
# Source-art map:
#   altar     - the smoke wrapper stands on comments and inert labels.
#   goban     - @ORACLE_GOBAN is the only visual board handed to smoke.
#   arch-gate - a non-consensus easter egg; not a protocol input.
#
# arch-gate: non-consensus source-art threshold; not a protocol input.
#              /\
#             /__\
#            /_/\_\
#
my $SOURCE_ART_ALTAR_LABEL = 'ALTAR: reader-facing, smoke-inert';
my $SOURCE_ART_GOBAN_LABEL = 'GOBAN: @ORACLE_GOBAN is the smoke board';
my $SOURCE_ART_GATE_LABEL  = 'arch-gate: easter egg, source-art only';

my $SOURCE_ART_ALTAR = <<'ASCII_ALTAR';
                     /\
                    /__\
                   /_/\_\
          +---------+----+---------+
          |       ALTAR GOBAN      |
          |   smoke reads the grid |
          +----+-------------+----+
               |  GOFTP/1    |
               |  source art |
          +----+-------------+----+
ASCII_ALTAR

# The array below is executable source art. The Perl cells themselves form the
# visual goban passed to the smoke module. The glyphs are not protocol inputs:
# naming, hashing, replay, and rule behavior still live in lib/GobanFTP/*.
# Decoration does not decide truth; lib/GobanFTP/* owns that.
my @ORACLE_GOBAN = (
#                       /\             arch-gate over the board
#                      /__\
#                     /_/\_\
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
