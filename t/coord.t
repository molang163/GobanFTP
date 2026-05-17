use v5.34;
use strict;
use warnings;

use FindBin;
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::Coord qw(index_to_point point_to_index point_to_xy);

my $size = 9;

is_deeply scalar point_to_xy('aa', $size), [ 0, 0 ], 'aa is top-left';
is scalar point_to_index('aa', $size), 0, 'aa maps to index 0';
is scalar point_to_index('ba', $size), 1, 'ba advances x first';
is scalar point_to_index('ab', $size), $size, 'ab starts second row';

is_deeply [ point_to_xy('aa', $size) ], [ [ 0, 0 ], undef ], 'point_to_xy returns value and no error';
is_deeply [ point_to_index('ba', $size) ], [ 1, undef ], 'point_to_index returns value and no error';
is_deeply [ index_to_point($size, $size) ], [ 'ab', undef ], 'index_to_point returns value and no error';

is scalar index_to_point(0, $size), 'aa', 'index 0 maps back to aa';
is scalar index_to_point(1, $size), 'ba', 'index 1 maps back to ba';
is scalar index_to_point($size, $size), 'ab', 'row-major index maps back to ab';
is scalar index_to_point(8, $size), 'ia', 'SGF alphabet does not skip i';

is_deeply [ point_to_xy('ja', $size) ], [ undef, 'coord.bounds' ], 'point x outside board reports bounds';
is_deeply [ point_to_xy('aj', $size) ], [ undef, 'coord.bounds' ], 'point y outside board reports bounds';
is scalar point_to_xy('ja', $size), undef, 'out-of-bounds scalar point_to_xy returns undef';

is_deeply [ point_to_index('a', $size) ], [ undef, 'coord.point' ], 'malformed point reports point error';
is_deeply [ point_to_index('AA', $size) ], [ undef, 'coord.point' ], 'uppercase point reports point error';
is_deeply [ point_to_index('aa', 27) ], [ undef, 'coord.size' ], 'unsupported size reports size error';
is_deeply [ index_to_point($size * $size, $size) ], [ undef, 'coord.bounds' ], 'index outside board reports bounds';
is_deeply [ index_to_point('x', $size) ], [ undef, 'coord.index' ], 'malformed index reports index error';

done_testing;
