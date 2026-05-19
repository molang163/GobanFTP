use v5.34;
use strict;
use warnings;

use FindBin;
use File::Spec;
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::Surface::WitnessView qw(
    render_witness_html
    render_witness_terminal
    render_witness_text
);
use GobanFTP::Witness qw(witness_for_listing);

sub _dies (&);

my $root = "$FindBin::Bin/..";
my $fixture_dir = "$FindBin::Bin/fixtures/v1/cross-substrate/minimal";
my $surface_module = "$root/lib/GobanFTP/Surface/WitnessView.pm";

subtest 'surface renderer has no consensus imports' => sub {
    my $source = _slurp($surface_module);
    my @gobanftp_uses = $source =~ /^\s*use\s+(GobanFTP::[A-Za-z0-9_:]+)\b/mg;

    is_deeply \@gobanftp_uses, [], 'surface renderer imports no GobanFTP modules';
    unlike $source,
        qr/\b(?:witness_for_listing|render_projection|replay|event_set_root_result|normalize_listing|profile_listing_names|parse_event|event_id_for)\b/,
        'surface renderer does not name consensus entry points';
};

subtest 'renders witness fields and projection text only' => sub {
    my $witness = _minimal_witness();
    my $projections = _projection_text();

    my $text = render_witness_text(
        witness     => $witness,
        projections => $projections,
    );
    like $text, qr/\AGOFTP-WITNESS-SURFACE\/1\n/, 'text surface has version header';
    like $text, qr/^profile_id=local-goftp1$/m, 'text surface prints profile id';
    like $text, qr/^adapter_id=local-listing-goftp1$/m, 'text surface prints adapter id';
    like $text,
        qr/^event_set_root=599c00f0614e400274a92ab1c96d09087a53d0d88bd8b0ecba481ac60a1f1461$/m,
        'text surface prints event_set_root';
    like $text, qr/^replay_status=ok$/m, 'text surface prints replay status';
    like $text, qr/^canonical_tip=kcvtlonfje163p9q$/m, 'text surface prints canonical tip';
    like $text,
        qr/^board_hash=15d477c5602f55fd5e90624226a791e92b2c1feb1be6e2a5c4bdcb6457ea262c$/m,
        'text surface prints board hash';
    like $text,
        qr/^sgf_hash=c18781ad0ed14358917d489286f257f0ff906ed3df6c35f937d52763b0a94553$/m,
        'text surface prints SGF hash';
    like $text, qr/^diagnostic_count=0$/m, 'text surface prints diagnostic count';
    like $text, qr/^signature[.]status=unsigned$/m, 'text surface prints signature status';
    like $text, qr/^--- projection[.]board ---\n3 \. \. \.$/m,
        'text surface includes projection board';
    like $text, qr/^--- projection[.]unsafe ---\n<script>alert\('shadow'\)<\/script>$/m,
        'text surface keeps projection text literal';

    my $terminal = render_witness_terminal(
        witness     => $witness,
        projections => $projections,
    );
    like $terminal, qr/\AGOFTP-TERMINAL-OBSERVATORY\/1\n/,
        'terminal surface has observatory header';
    like $terminal, qr/^status[.]profile=local-goftp1$/m,
        'terminal surface prints profile id';
    like $terminal, qr/^status[.]adapter=local-listing-goftp1$/m,
        'terminal surface prints adapter id';
    like $terminal,
        qr/^truth[.]event_set_root=599c00f0614e400274a92ab1c96d09087a53d0d88bd8b0ecba481ac60a1f1461$/m,
        'terminal surface prints event_set_root';
    like $terminal, qr/^truth[.]canonical_tip=kcvtlonfje163p9q$/m,
        'terminal surface prints canonical tip';
    like $terminal, qr/^status[.]signature=unsigned$/m,
        'terminal surface prints signature status';
    like $terminal, qr/^--- observed[.]board ---\n3 \. \. \.$/m,
        'terminal surface includes observed board';
    like $terminal, qr/^--- observed[.]verdict ---\nstatus=ok$/m,
        'terminal surface includes observed verdict';
    unlike $terminal, qr/<script>alert/,
        'terminal surface omits projection text not shown in terminal view';

    my $html = render_witness_html(
        witness     => $witness,
        projections => $projections,
    );
    like $html, qr/<dt>event_set_root<\/dt><dd>599c00f0614e400274a92ab1c96d09087a53d0d88bd8b0ecba481ac60a1f1461<\/dd>/,
        'HTML surface includes event_set_root';
    like $html, qr/<dt>signature[.]status<\/dt><dd>unsigned<\/dd>/,
        'HTML surface includes signature status';
    like $html, qr/<h2>projection[.]board<\/h2>/, 'HTML surface includes projection section';
    like $html, qr/<div class="goban" style="--board-size: 3">/,
        'HTML surface renders board projection as a visual goban';
    like $html, qr/data-point="aa"/,
        'HTML visual goban keeps point coordinates';
    like $html, qr/data-point="ab"><span class="stone black"/,
        'HTML visual goban maps supplied black stone text to the matching point';
    like $html, qr/data-point="bb"><span class="stone white"/,
        'HTML visual goban maps supplied white stone text to the matching point';
    like $html, qr/data-point="aa"><span class="empty"/,
        'HTML visual goban leaves supplied empty points empty';
    like $html, qr/<pre class="projection-raw">3 \. \. \./,
        'HTML surface keeps the raw board projection beside the visual skin';
    like $html, qr/&lt;script&gt;alert\(&#39;shadow&#39;\)&lt;\/script&gt;/,
        'HTML projection text is escaped';
    unlike $html, qr/<script>alert/, 'HTML surface does not emit raw script text';
};

subtest 'malformed board projection falls back to raw escaped pre text' => sub {
    my $witness = _minimal_witness();
    my $html = render_witness_html(
        witness     => $witness,
        projections => {
            board => "3 . . .\n3 B W .\n1 . . .\n  a b c\n",
        },
    );

    unlike $html, qr/<div class="goban"/,
        'malformed board labels do not render as a visual goban';
    like $html, qr/<h2>projection[.]board<\/h2><pre>3 \. \. \.\n3 B W \.\n1 \. \. \./,
        'malformed board text remains visible as raw projection text';
};

subtest 'does not call witness, replay, root, listing, rules, projection, or parser code' => sub {
    my $witness = _minimal_witness();
    my $projections = _projection_text();
    my $expected_text = render_witness_text(
        witness     => $witness,
        projections => $projections,
    );

    {
        no warnings 'redefine';
        local *GobanFTP::Witness::witness_for_listing = sub { die 'surface called witness' };
        local *GobanFTP::Replay::replay = sub { die 'surface called replay' };
        local *GobanFTP::EventSetRoot::event_set_root_result = sub { die 'surface called root' };
        local *GobanFTP::Listing::normalize_listing = sub { die 'surface called listing' };
        local *GobanFTP::Profile::Adapter::profile_listing_names = sub { die 'surface called adapter' };
        local *GobanFTP::Projection::render_projection = sub { die 'surface called projection' };
        local *GobanFTP::Rules::new = sub { die 'surface called rules' };
        local *GobanFTP::Filename::Grammar::parse_event = sub { die 'surface called parser' };
        local *GobanFTP::Filename::Grammar::event_id_for = sub { die 'surface called event id' };

        is render_witness_text(witness => $witness, projections => $projections),
            $expected_text,
            'text rendering is pure formatting after witness assembly';
        like render_witness_terminal(witness => $witness, projections => $projections),
            qr/^truth[.]event_set_root=\Q$witness->{event_set_root}\E$/m,
            'terminal rendering is pure formatting after witness assembly';
        like render_witness_html(witness => $witness, projections => $projections),
            qr/<dt>event_set_root<\/dt><dd>\Q$witness->{event_set_root}\E<\/dd>/,
            'HTML rendering is pure formatting after witness assembly';
    }
};

subtest 'signature status is derived from supplied witness fields' => sub {
    my $witness = _minimal_witness();

    my %signed_ok = (
        %$witness,
        profile_id        => 'signed-hmac-goftp1',
        rejected_classes  => [],
    );
    like render_witness_text(witness => \%signed_ok), qr/^signature[.]status=ok$/m,
        'signed witness without signature rejection is ok';
    like render_witness_terminal(witness => \%signed_ok), qr/^status[.]signature=ok$/m,
        'terminal signed witness without signature rejection is ok';

    my %signed_failed = (
        %$witness,
        profile_id        => 'signed-hmac-goftp1',
        rejected_classes  => ['signature'],
    );
    like render_witness_text(witness => \%signed_failed), qr/^signature[.]status=failed$/m,
        'signed witness with signature rejection is failed';
    like render_witness_terminal(witness => \%signed_failed), qr/^status[.]signature=failed$/m,
        'terminal signed witness with signature rejection is failed';
    is $signed_failed{event_set_root}, $witness->{event_set_root},
        'surface signature display does not alter event_set_root';
};

subtest 'rejects non-hash inputs and non-text projections' => sub {
    like _dies { render_witness_text() }, qr/witness is required/,
        'witness is required';
    like _dies { render_witness_text(witness => [], projections => {}) },
        qr/witness must be a hash reference/,
        'witness must be a hash reference';
    like _dies { render_witness_text(witness => {}, projections => []) },
        qr/projections must be a hash reference/,
        'projections must be a hash reference';
    like _dies { render_witness_text(witness => {}, projections => { board => [] }) },
        qr/projection board must be plain text/,
        'projection values must be plain text';
};

done_testing;

sub _minimal_witness {
    my $game = _read_single(File::Spec->catfile($fixture_dir, 'game.name'));
    my @raw = _read_names(File::Spec->catfile($fixture_dir, 'local-goftp1', 'listing.names'));

    return witness_for_listing(
        profile_id      => 'local-goftp1',
        game_descriptor => $game,
        raw_names       => \@raw,
    );
}

sub _projection_text {
    return {
        board   => "3 . . .\n2 B W .\n1 . . .\n  a b c\n",
        verdict => "status=ok\nworldline=main\n",
        unsafe  => "<script>alert('shadow')</script>",
    };
}

sub _read_single {
    my ($path) = @_;

    my @names = _read_names($path);
    die "$path must contain exactly one nonblank line" if @names != 1;
    return $names[0];
}

sub _read_names {
    my ($path) = @_;

    open my $fh, '<:encoding(UTF-8)', $path or die "open $path: $!";
    my @names;
    while (my $line = <$fh>) {
        chomp $line;
        next if $line =~ /\A\s*\z/;
        push @names, $line;
    }
    close $fh or die "close $path: $!";

    return @names;
}

sub _slurp {
    my ($path) = @_;

    open my $fh, '<:encoding(UTF-8)', $path or die "open $path: $!";
    my $text = do { local $/; <$fh> };
    close $fh or die "close $path: $!";
    return $text;
}

sub _dies (&) {
    my ($code) = @_;

    my $ok = eval {
        $code->();
        1;
    };
    return '' if $ok;

    my $error = $@ || 'unknown error';
    chomp $error;
    return $error;
}
