use v5.34;
use strict;
use warnings;

use FindBin;
use File::Spec;
use Test::More;

my $root = File::Spec->catdir($FindBin::Bin, '..');
my $specimen = File::Spec->catfile($root, qw(examples static witness-specimen.html));

ok -f $specimen, 'static witness specimen exists';

my $html = _slurp($specimen);
like $html, qr/\A<!doctype html>\n/, 'specimen is a direct-open static HTML document';
like $html, qr/GOFTP-WITNESS-SPECIMEN\/1/, 'specimen carries a surface version';
like $html, qr/data-boundary="static-supplied-witness"/,
    'specimen names its supplied-field boundary';
like $html, qr/<dt>profile_id<\/dt><dd>local-goftp1<\/dd>/,
    'specimen includes the witness profile';
like $html,
    qr/<dt>event_set_root<\/dt><dd>12699daa3f344c6f65358bb36587933aed4657fbb9ddba7db8ff3909b9f451f4<\/dd>/,
    'specimen exposes the stable witness root';
like $html, qr/<dt>signature[.]status<\/dt><dd>unsigned<\/dd>/,
    'specimen exposes unsigned signature status';
like $html, qr/<h2 id="board-heading">projection[.]board<\/h2>/,
    'specimen includes a board projection section';
like $html, qr/<h2 id="sgf-heading">projection[.]sgf_main<\/h2>/,
    'specimen includes a canonical SGF projection section';
like $html,
    qr/<pre>\(;GM\[1\]FF\[4\]CA\[UTF-8\]AP\[GobanFTP\]SZ\[9\]KM\[7[.]5\]PB\[daemon\]PW\[pilgrim\]RU\[chinese-area-v1\];B\[dd\];W\[ff\];B\[de\];W\[ef\];B\[df\];W\[fe\]\)<\/pre>/,
    'specimen SGF matches the displayed shrine witness root';
unlike $html, qr/KM\[7[.]50\]|PB\[black\]|PW\[white\]/,
    'specimen does not mix in unrelated SGF metadata';

my @points = $html =~ /\bdata-point="([a-i][a-i])"/g;
is scalar(@points), 81, 'specimen board is a fixed 9x9 projection grid';
is_deeply [@points[0 .. 8]], [qw(aa ba ca da ea fa ga ha ia)],
    'specimen board starts with the top row';
is_deeply [@points[-9 .. -1]], [qw(ai bi ci di ei fi gi hi ii)],
    'specimen board ends with the bottom row';
is scalar(() = $html =~ /class="stone black"/g), 3, 'specimen visual board has three black stones';
is scalar(() = $html =~ /class="stone white"/g), 3, 'specimen visual board has three white stones';
like $html, qr/data-point="dd"><span class="stone black"/,
    'specimen places black at dd';
like $html, qr/data-point="ff"><span class="stone white"/,
    'specimen places white at ff';

unlike $html, qr/<script\b/i, 'specimen has no script';
unlike $html, qr/\b(?:https?:)?\/\//i, 'specimen loads no remote resources';
unlike $html, qr/<(?:form|input|button)\b/i, 'specimen is not an interactive hosted UI';
unlike $html, qr/\b(?:fetch|XMLHttpRequest|WebSocket|EventSource)\b/,
    'specimen contains no network client code';

done_testing;

sub _slurp {
    my ($path) = @_;

    open my $fh, '<:encoding(UTF-8)', $path or die "open $path: $!";
    my $text = do { local $/; <$fh> };
    close $fh or die "close $path: $!";
    return $text // '';
}
