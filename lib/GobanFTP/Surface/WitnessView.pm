package GobanFTP::Surface::WitnessView;

use v5.34;
use strict;
use warnings;

use Carp qw(croak);
use Exporter qw(import);

our @EXPORT_OK = qw(render_witness_html render_witness_terminal render_witness_text);

my @WITNESS_FIELDS = qw(
    profile_id
    profile_consensus_version
    adapter_id
    game_descriptor
    ruleset_id
    ruleset_semver
    ruleset_seal_version
    ruleset_fixture_digest
    ruleset_seal
    raw_count
    normalized_count
    accepted_count
    rejected_count
    rejected_codes
    rejected_classes
    event_set_root
    replay_status
    canonical_tip
    canonical_ids
    legal_ids
    diagnostic_codes
    diagnostic_classes
    diagnostic_count
    board_hash
    sgf_hash
    variations_sgf_hash
);

my @PROJECTION_FIELDS = qw(
    board
    verdict
    listing
    sgf
    sgf_main
    main_sgf
    sgf_variations
    variations_sgf
);

sub render_witness_text {
    my %args = _args(@_);
    my $witness = _required_hash($args{witness}, 'witness');
    my $projections = _optional_hash($args{projections}, 'projections');

    my @lines = ('GOFTP-WITNESS-SURFACE/1');
    push @lines, map { "$_->[0]=$_->[1]" } _witness_pairs($witness);
    push @lines, 'signature.status=' . _signature_status($witness);

    for my $projection (_projection_pairs($projections)) {
        push @lines, '', "--- projection.$projection->[0] ---", $projection->[1];
    }

    return join("\n", @lines, '');
}

sub render_witness_terminal {
    my %args = _args(@_);
    my $witness = _required_hash($args{witness}, 'witness');
    my $projections = _optional_hash($args{projections}, 'projections');

    my @lines = (
        'GOFTP-TERMINAL-OBSERVATORY/1',
        _terminal_box(
            'GobanFTP witness observatory',
            'display is derived from supplied witness fields only',
            _terminal_status_line($witness),
            _terminal_events_line($witness),
        ),
        'observatory.input=witness+projection-text',
        'status.profile=' . _value($witness->{profile_id}),
        'status.adapter=' . _value($witness->{adapter_id}),
        'status.replay_status=' . _value($witness->{replay_status}),
        'status.signature=' . _signature_status($witness),
        'truth.event_set_root=' . _value($witness->{event_set_root}),
        'truth.canonical_tip=' . _value($witness->{canonical_tip}),
        'truth.board_hash=' . _value($witness->{board_hash}),
        'truth.sgf_hash=' . _value($witness->{sgf_hash}),
        'truth.variations_sgf_hash=' . _value($witness->{variations_sgf_hash}),
        'truth.diagnostic_count=' . _value($witness->{diagnostic_count}),
    );

    for my $projection (_terminal_projection_pairs($projections)) {
        push @lines, '', "--- observed.$projection->[0] ---", $projection->[1];
    }

    return join("\n", @lines, '');
}

sub render_witness_html {
    my %args = _args(@_);
    my $witness = _required_hash($args{witness}, 'witness');
    my $projections = _optional_hash($args{projections}, 'projections');

    my @witness_rows = (
        (map { _html_field_row($_->[0], $_->[1]) } _witness_pairs($witness)),
        _html_field_row('signature.status', _signature_status($witness)),
    );
    my @projection_blocks = map { _html_projection_section($_->[0], $_->[1]) }
        _projection_pairs($projections);

    return join("\n",
        '<!doctype html>',
        '<html lang="en">',
        '<head>',
        '<meta charset="utf-8">',
        '<meta name="viewport" content="width=device-width, initial-scale=1">',
        '<title>GOFTP Witness Surface</title>',
        '<style>',
        _style(),
        '</style>',
        '</head>',
        '<body>',
        '<main>',
        '<header>',
        '<p class="eyebrow">GOFTP-WITNESS-SURFACE/1</p>',
        '<h1>Witness Surface</h1>',
        '<p class="subtitle">Rendered from witness fields and projection text only.</p>',
        '</header>',
        '<section class="witness">',
        '<h2>Witness</h2>',
        '<dl>',
        @witness_rows,
        '</dl>',
        '</section>',
        @projection_blocks,
        '</main>',
        '</body>',
        '</html>',
        '',
    );
}

sub _witness_pairs {
    my ($witness) = @_;

    my @pairs;
    for my $field (@WITNESS_FIELDS) {
        next if !exists $witness->{$field};
        push @pairs, [$field, _value($witness->{$field})];
    }

    return @pairs;
}

sub _projection_pairs {
    my ($projections) = @_;

    my %known = map { $_ => 1 } @PROJECTION_FIELDS;
    my @names = (
        grep({ exists $projections->{$_} } @PROJECTION_FIELDS),
        grep({ !$known{$_} } sort keys %$projections),
    );

    my @pairs;
    for my $name (@names) {
        my $text = $projections->{$name};
        next if !defined $text || $text eq '';
        croak "projection $name must be plain text" if ref($text);
        push @pairs, [$name, $text];
    }

    return @pairs;
}

sub _terminal_projection_pairs {
    my ($projections) = @_;

    my @pairs;
    for my $name (qw(board verdict)) {
        next if !exists $projections->{$name};
        my $text = $projections->{$name};
        next if !defined $text || $text eq '';
        croak "projection $name must be plain text" if ref($text);
        push @pairs, [$name, $text];
    }

    return @pairs;
}

sub _terminal_box {
    my (@rows) = @_;

    my $inner = 74;
    my $rule = '+' . ('-' x ($inner + 2)) . '+';
    return join "\n",
        $rule,
        map({ '| ' . _terminal_cell($_, $inner) . ' |' } @rows),
        $rule;
}

sub _terminal_cell {
    my ($text, $width) = @_;

    $text = _value($text);
    $text =~ s/[\r\n\t]/ /g;
    $text = substr($text, 0, $width) if length($text) > $width;
    return $text . (' ' x ($width - length($text)));
}

sub _terminal_status_line {
    my ($witness) = @_;

    return join ' ',
        'replay_status=' . _value($witness->{replay_status}),
        'signature=' . _signature_status($witness),
        'diagnostics=' . _value($witness->{diagnostic_count});
}

sub _terminal_events_line {
    my ($witness) = @_;

    return join ' ',
        'events',
        'raw=' . _value($witness->{raw_count}),
        'normalized=' . _value($witness->{normalized_count}),
        'accepted=' . _value($witness->{accepted_count}),
        'rejected=' . _value($witness->{rejected_count});
}

sub _html_field_row {
    my ($name, $value) = @_;

    return '<dt>' . _html($name) . '</dt><dd>' . _html($value) . '</dd>';
}

sub _html_projection_section {
    my ($name, $text) = @_;

    if ($name eq 'board') {
        my $board = _parse_board_projection($text);
        if ($board) {
            return '<section class="projection projection-board">'
                . '<h2>' . _html('projection.board') . '</h2>'
                . '<div class="board-layout">'
                . _html_goban($board)
                . '<div class="projection-copy">'
                . '<div class="proof-panel">'
                . '<div class="proof-card">'
                . '<h3>Projection Skin</h3>'
                . '<p class="boundary-note">This is not terminal output. It is a static rendering of supplied projection text.</p>'
                . '</div>'
                . '<div class="proof-card">'
                . '<h3>Packet Boundary</h3>'
                . '<ul class="packet-list">'
                . '<li><strong>truth</strong> game descriptor basename</li>'
                . '<li><strong>truth</strong> direct events/ basenames</li>'
                . '<li><strong>shadow</strong> bytes, mtime, order, sidecars, projections, tmp</li>'
                . '</ul>'
                . '</div>'
                . '<div class="proof-card">'
                . '<h3>Raw Projection Witness</h3>'
                . '<pre class="projection-raw">' . _html($text) . '</pre>'
                . '</div>'
                . '</div>'
                . '</div>'
                . '</div>'
                . '</section>';
        }
    }

    return '<section class="projection">'
        . '<h2>' . _html("projection.$name") . '</h2>'
        . '<pre>' . _html($text) . '</pre>'
        . '</section>';
}

sub _parse_board_projection {
    my ($text) = @_;
    return undef if !defined $text || ref($text);

    my $size;
    my @rows;
    my @labels;
    for my $line (split /\n/, $text) {
        $size = 0 + $1 if !defined($size) && $line =~ /\Asize=([1-9][0-9]*)\z/;
        if ($line =~ /\A\s*([1-9][0-9]*)\s+([.BW](?:\s+[.BW])*)\s*\z/) {
            push @labels, 0 + $1;
            my @cells = split /\s+/, $2;
            push @rows, \@cells;
            $size //= scalar @cells;
        }
    }

    return undef if !$size || $size < 1 || $size > 26;
    return undef if @rows != $size;
    for my $idx (0 .. $#rows) {
        return undef if $labels[$idx] != $size - $idx;
        return undef if @{ $rows[$idx] } != $size;
    }

    return {
        size => $size,
        rows => \@rows,
    };
}

sub _html_goban {
    my ($board) = @_;
    my $size = $board->{size};
    my @cells;

    for my $y (0 .. $size - 1) {
        my $row = $board->{rows}[$y];
        for my $x (0 .. $size - 1) {
            my $stone = $row->[$x];
            my $point = chr(97 + $x) . chr(97 + $y);
            my @classes = ('board-point');
            push @classes, 'star' if _is_star_point($x, $y, $size);
            my $content = '<span class="empty" aria-hidden="true"></span>';
            if ($stone eq 'B') {
                push @classes, 'has-stone';
                $content = '<span class="stone black" aria-label="black stone"></span>';
            }
            elsif ($stone eq 'W') {
                push @classes, 'has-stone';
                $content = '<span class="stone white" aria-label="white stone"></span>';
            }

            push @cells,
                '<span class="' . join(' ', @classes) . '" data-point="' . _html($point) . '">'
                . $content
                . '</span>';
        }
    }

    return '<figure class="goban-figure">'
        . '<div class="goban" style="--board-size: ' . _html($size) . '">'
        . join('', @cells)
        . '</div>'
        . '<figcaption>Projection skin; not a consensus input.</figcaption>'
        . '</figure>';
}

sub _is_star_point {
    my ($x, $y, $size) = @_;
    return 0 if $size < 7;

    my @points = $size == 9 ? (2, 4, 6) : $size == 13 ? (3, 6, 9) : (3, int($size / 2), $size - 4);
    my %point = map { $_ => 1 } @points;
    return $point{$x} && $point{$y} ? 1 : 0;
}

sub _value {
    my ($value) = @_;
    return '' if !defined $value;
    return join(',', @$value) if ref($value) eq 'ARRAY';
    return '' if ref($value);
    return "$value";
}

sub _signature_status {
    my ($witness) = @_;

    my $profile_id = $witness->{profile_id} // '';
    return 'unsigned' if $profile_id ne 'signed-hmac-goftp1';

    return grep({ $_ eq 'signature' } @{ $witness->{rejected_classes} // [] })
        ? 'failed'
        : 'ok';
}

sub _html {
    my ($text) = @_;
    $text = _value($text);
    $text =~ s/&/&amp;/g;
    $text =~ s/</&lt;/g;
    $text =~ s/>/&gt;/g;
    $text =~ s/"/&quot;/g;
    $text =~ s/'/&#39;/g;
    return $text;
}

sub _args {
    return %{ $_[0] } if @_ == 1 && ref($_[0]) eq 'HASH';
    croak 'named arguments must be key/value pairs' if @_ % 2;
    return @_;
}

sub _required_hash {
    my ($value, $name) = @_;
    croak "$name is required" if !defined $value;
    croak "$name must be a hash reference" if ref($value) ne 'HASH';
    return $value;
}

sub _optional_hash {
    my ($value, $name) = @_;
    return {} if !defined $value;
    croak "$name must be a hash reference" if ref($value) ne 'HASH';
    return $value;
}

sub _style {
    return <<'CSS';
:root {
  color-scheme: dark;
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  background: #11130f;
  color: #ece8dc;
}
body {
  margin: 0;
  background: #11130f;
}
main {
  width: min(1120px, calc(100% - 32px));
  margin: 0 auto;
  padding: 32px 0 40px;
}
header,
section {
  border-left: 3px solid #b9442e;
  padding: 4px 0 6px 18px;
  margin: 0 0 28px;
}
.eyebrow {
  color: #9fbf8f;
  margin: 0 0 8px;
}
h1,
h2 {
  color: #f4f0e6;
  font-size: 24px;
  font-weight: 700;
  letter-spacing: 0;
  margin: 0 0 14px;
}
h2 {
  font-size: 18px;
}
h3 {
  color: #f4f0e6;
  font-size: 15px;
  margin: 0 0 10px;
}
.subtitle {
  color: #c7bea9;
  margin: 0;
}
dl {
  display: grid;
  grid-template-columns: minmax(180px, 280px) minmax(0, 1fr);
  gap: 8px 18px;
  margin: 0;
}
dt {
  color: #9fbf8f;
}
dd {
  color: #ece8dc;
  margin: 0;
  overflow-wrap: anywhere;
}
pre {
  margin: 0;
  overflow: auto;
  max-width: 100%;
  color: #ece8dc;
  background: #1b1d18;
  border: 1px solid #3b3d34;
  padding: 14px;
}
.board-layout {
  display: grid;
  grid-template-columns: minmax(280px, 420px) minmax(0, 1fr);
  gap: 24px;
  align-items: start;
}
.goban-figure {
  margin: 0;
}
.goban {
  --cell: clamp(24px, 6vw, 38px);
  display: grid;
  grid-template-columns: repeat(var(--board-size), var(--cell));
  grid-template-rows: repeat(var(--board-size), var(--cell));
  width: max-content;
  max-width: 100%;
  padding: calc(var(--cell) * .35);
  background: #c79a5b;
  border: 1px solid #4a3321;
  box-shadow: inset 0 0 0 2px rgba(255,255,255,.12);
  overflow: auto;
}
.board-point {
  position: relative;
  display: grid;
  place-items: center;
  width: var(--cell);
  height: var(--cell);
}
.board-point::before,
.board-point::after {
  content: "";
  position: absolute;
  background: rgba(31, 22, 15, .72);
  pointer-events: none;
}
.board-point::before {
  width: 100%;
  height: 1px;
}
.board-point::after {
  width: 1px;
  height: 100%;
}
.board-point.star .empty::before {
  content: "";
  display: block;
  width: 6px;
  height: 6px;
  border-radius: 50%;
  background: rgba(31, 22, 15, .78);
}
.stone {
  position: relative;
  z-index: 1;
  width: calc(var(--cell) * .74);
  height: calc(var(--cell) * .74);
  border-radius: 50%;
  box-shadow: 0 4px 10px rgba(0,0,0,.35);
}
.stone.black {
  background: radial-gradient(circle at 34% 28%, #4e4e4b, #111);
}
.stone.white {
  background: radial-gradient(circle at 35% 28%, #fff, #d9d3c5 70%, #aaa08e);
}
.projection-copy {
  min-width: 0;
}
.proof-panel {
  display: grid;
  gap: 14px;
}
.proof-card {
  border: 1px solid #3b3d34;
  background: #171a15;
  padding: 14px;
}
.packet-list {
  display: grid;
  gap: 8px;
  list-style: none;
  margin: 0;
  padding: 0;
}
.packet-list strong {
  color: #9fbf8f;
}
.projection-raw {
  font-size: 13px;
  line-height: 1.45;
}
.boundary-note,
figcaption {
  color: #c7bea9;
  margin: 0 0 10px;
  font-size: 13px;
}
@media (max-width: 720px) {
  dl {
    grid-template-columns: 1fr;
  }
  dd {
    margin-bottom: 8px;
  }
  .board-layout {
    grid-template-columns: 1fr;
  }
}
CSS
}

1;

__END__

=head1 NAME

GobanFTP::Surface::WitnessView - render witness and projection inspection surfaces

=cut
