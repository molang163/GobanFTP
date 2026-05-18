package GobanFTP::Surface::WitnessView;

use v5.34;
use strict;
use warnings;

use Carp qw(croak);
use Exporter qw(import);

our @EXPORT_OK = qw(render_witness_html render_witness_text);

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

sub render_witness_html {
    my %args = _args(@_);
    my $witness = _required_hash($args{witness}, 'witness');
    my $projections = _optional_hash($args{projections}, 'projections');

    my @witness_rows = (
        (map { _html_field_row($_->[0], $_->[1]) } _witness_pairs($witness)),
        _html_field_row('signature.status', _signature_status($witness)),
    );
    my @projection_blocks = map {
        '<section class="projection">'
            . '<h2>' . _html("projection.$_->[0]") . '</h2>'
            . '<pre>' . _html($_->[1]) . '</pre>'
            . '</section>'
    } _projection_pairs($projections);

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

sub _html_field_row {
    my ($name, $value) = @_;

    return '<dt>' . _html($name) . '</dt><dd>' . _html($value) . '</dd>';
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
@media (max-width: 720px) {
  dl {
    grid-template-columns: 1fr;
  }
  dd {
    margin-bottom: 8px;
  }
}
CSS
}

1;

__END__

=head1 NAME

GobanFTP::Surface::WitnessView - render witness and projection inspection surfaces

=cut
