use v5.34;
use strict;
use warnings;

use Digest::SHA qw(sha256_hex);
use FindBin;
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::Board;

sub exception (&) {
    my ($code) = @_;

    my $error;
    eval { $code->(); 1 } or $error = $@;

    return $error;
}

my $board = GobanFTP::Board->new(3);

is $board->size, 3, 'new stores board size';
is(GobanFTP::Board->new(size => 3)->size, 3, 'new also accepts named size');
is $board->get(0, 0), 0, 'new board starts empty';
is $board->stone_at('aa'), 0, 'stone_at reads empty point';

$board->set(1, 0, 1);
$board->place('ab', 2);

is $board->get(1, 0), 1, 'set writes by xy';
is $board->stone_at('ba'), 1, 'stone_at reads SGF point';
is $board->get(0, 1), 2, 'place writes by point';

my $copy = $board->copy;
$copy->set(1, 0, 2);
$copy->place('cc', 1);

is $copy->get(1, 0), 2, 'copy can be mutated';
is $board->get(1, 0), 1, 'copy mutation does not pollute parent';
is $board->stone_at('cc'), 0, 'copy added stone does not appear on parent';

my $bytes = $board->canonical_bytes;
is $bytes, pack('C*', 0, 1, 0, 2, 0, 0, 0, 0, 0), 'canonical bytes are row-major cell values';
is $board->board_hash_sha256, sha256_hex("GOFTP-BOARD/1\0" . 3 . "\0" . $bytes), 'board hash uses GOFTP-BOARD/1 framing';
is $board->board_hash_sha256, $board->copy->board_hash_sha256, 'copied board hash is stable';

like exception { $board->get(3, 0) }, qr/board\.bounds/, 'get rejects out-of-bounds x';
like exception { $board->set(0, 0, 3) }, qr/board\.stone/, 'set rejects invalid stone';
like exception { $board->place('da', 1) }, qr/coord\.bounds/, 'place rejects out-of-bounds point';

done_testing;
