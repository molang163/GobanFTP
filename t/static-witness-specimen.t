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
    qr/<dt>event_set_root<\/dt><dd>599c00f0614e400274a92ab1c96d09087a53d0d88bd8b0ecba481ac60a1f1461<\/dd>/,
    'specimen exposes the stable witness root';
like $html, qr/<dt>signature[.]status<\/dt><dd>unsigned<\/dd>/,
    'specimen exposes unsigned signature status';
like $html, qr/<h2 id="board-heading">projection[.]board<\/h2>/,
    'specimen includes a board projection section';
like $html, qr/<h2 id="sgf-heading">projection[.]sgf_main<\/h2>/,
    'specimen includes a canonical SGF projection section';

my @points = $html =~ /\bdata-point="([a-c][a-c])"/g;
is_deeply \@points, [qw(aa ba ca ab bb cb ac bc cc)],
    'specimen board is a fixed 3x3 projection grid';
is scalar(() = $html =~ /class="stone black"/g), 1, 'specimen visual board has one black stone';
is scalar(() = $html =~ /class="stone white"/g), 1, 'specimen visual board has one white stone';

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
