use v5.34;
use strict;
use warnings;

use FindBin;
use IPC::Open3;
use Symbol qw(gensym);
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::Oracle::Smoke qw(smoke_report);

my $root = "$FindBin::Bin/..";
my $script = "$root/oracle/goban.pl";
my $smoke_module = "$root/lib/GobanFTP/Oracle/Smoke.pm";
my $source_art_doc = "$root/docs/SOURCE_ART.md";

ok -f $script, 'source-art oracle exists';
ok -f $source_art_doc, 'source-art boundary documentation exists';

my $source = _slurp($script);
my $doc = _slurp($source_art_doc);
unlike $source, qr/[^\x00-\x7F]/, 'source-art wrapper stays ASCII';
is_deeply [ _source_motifs($source) ], [qw(altar goban arch-gate)],
    'source-art wrapper carries the altar, goban, and arch-gate motifs';
like $source, qr/GobanFTP::Oracle::Smoke/, 'source-art wrapper delegates smoke scenario to a module';
like $source, qr/arch-gate\s*[-:]\s*(?:a\s+)?(?:non-consensus|easter egg).*?(?:not a protocol input|source-art only)/s,
    'source-art wrapper carries hidden arch-gate non-consensus marker';
like $source, qr/^(?:#\s*)?\s*\/\\\n(?:#\s*)?\s*\/__\\\n(?:#\s*)?\s*\/_\/\\_\\$/m,
    'source-art wrapper carries ASCII arch-gate threshold';
unlike $source, qr/Arch Linux|archlinux|official|endorse|wordmark/i,
    'source-art wrapper does not claim Arch Linux branding or affiliation';
my @gobanftp_uses = $source =~ /^\s*use\s+(GobanFTP::[A-Za-z0-9_:]+)\b/mg;
is_deeply \@gobanftp_uses, ['GobanFTP::Oracle::Smoke'],
    'source-art wrapper only imports the smoke module';
like $source, qr/^\s*use\s+GobanFTP::Oracle::Smoke\s+qw\(run_smoke\);$/m,
    'source-art wrapper imports only the smoke runner';
unlike $source, qr/^\s*use\s+GobanFTP::(?:DAG|EventID|Filename::Grammar|GameSpec|Projection|Replay|Rules|SGF|Store)\b/m,
    'source-art wrapper does not import protocol, replay, rules, SGF, projection, or store modules directly';
unlike $source, qr/\b(?:event_id_for|parse_event|build\(|apply_move|GOFTP-EVENT|m1\.|a1\.|g1\.id-)\b/,
    'source-art wrapper does not embed protocol or rule implementation traces';

like $doc, qr/`oracle\/goban\.pl` is currently the strong altar\/goban source wrapper\./,
    'source-art documentation names the current oracle as the strong altar/goban wrapper';
like $doc, qr/does not\s+make a release-status claim for source art, P14, or v1\.0\./,
    'source-art documentation keeps release-status claims out of the wrapper boundary';
unlike $doc,
    qr/\b(?:source[- ]art|P14|v1\.0)\b[^\n.]{0,80}\bcomplete\b|\bcomplete\b[^\n.]{0,80}\b(?:source[- ]art|P14|v1\.0)\b/i,
    'source-art documentation does not claim source art, P14, or v1.0 complete';

my $smoke_source = _slurp($smoke_module);
like $smoke_source, qr/GobanFTP::Witness/, 'smoke module delegates replay truth to Witness';
unlike $smoke_source,
    qr/^\s*use\s+GobanFTP::(?:DAG|EventID|Filename::Grammar|GameSpec|Projection|Replay|Rules|SGF|Store|EventSetRoot)\b/m,
    'smoke module does not import consensus engines directly';

my @board = _executable_board_from($source);
is scalar(@board), 9, 'source-art wrapper contains nine executable goban rows';
is_deeply [ map { $_->{label} } @board ], [qw(9 8 7 6 5 4 3 2 1)],
    'source-art row labels descend like a board';
is _cell_count(\@board), 81, 'source-art wrapper contains 81 executable cells';

my @stars = _star_points(\@board);
is_deeply \@stars, [qw(c7 g7 e5 c3 g3)],
    'source-art wrapper uses standard 9x9 star points in executable code';

my ($compile_status, undef, $compile_err) = run_cmd($^X, '-c', $script);
is $compile_status, 0, 'source-art oracle passes perl -c'
    or diag $compile_err;

my ($smoke_status, $smoke_out, $smoke_err) = run_cmd($^X, $script, '--smoke');
is $smoke_status, 0, 'source-art oracle --smoke succeeds without requiring Inline::C'
    or diag $smoke_err;

like $smoke_out, qr/^gobanftp\.oracle=ok$/m, 'smoke reports oracle status';
like $smoke_out, qr/^rules\.move=ok$/m, 'smoke reaches rules module';
like $smoke_out, qr/^profile_id=local-goftp1$/m, 'smoke reports witness profile';
like $smoke_out, qr/^adapter_id=local-listing-goftp1$/m, 'smoke reports witness adapter';
like $smoke_out, qr/^accepted_count=1$/m, 'smoke reports accepted witness count';
like $smoke_out,
    qr/^event_set_root=7b329a82474f5297e1bd42c85801b510ed170e99b013f337e04e1f848bed267d$/m,
    'smoke reports witness event_set_root';
like $smoke_out, qr/^replay_status=ok$/m, 'smoke reports witness replay status';
like $smoke_out, qr/^canonical_tip=nnj11k89biuv36dk$/m, 'smoke reports witness canonical tip';
like $smoke_out,
    qr/^board_hash=2a86a2fe1efb4a3fab88b8bbe889023bd6e96684739e8331fe9052760818dd04$/m,
    'smoke reports witness board hash';
like $smoke_out,
    qr/^sgf_hash=a4a7248b452f722852d7895c8f738c35eea3f947759b3adc8403a4d366369b95$/m,
    'smoke reports witness SGF hash';
like $smoke_out,
    qr/^variations_sgf_hash=a4a7248b452f722852d7895c8f738c35eea3f947759b3adc8403a4d366369b95$/m,
    'smoke reports witness variations SGF hash';
like $smoke_out, qr/^diagnostic_count=0$/m, 'smoke reports witness diagnostics count';
like $smoke_out, qr/^inline_c=(?:missing|skip|ok value=361)$/m, 'Inline::C smoke is optional';
unlike $smoke_out, qr/arch-gate|\/__\\|\/_\/\\_\\/,
    'arch-gate source art is not emitted as witness truth';
is_deeply [ grep { !/^[A-Za-z0-9_.]+=/ } grep { length } split /\n/, $smoke_out ], [],
    'smoke output contains witness-style field lines, not decoration';
unlike $smoke_out, qr/GOFTP\/1 ORACLE|source-art|wrapper|arch-gate|\/__\\|\/_\/\\_\\|\+--------\+/,
    'decorative source-art motifs are not emitted as witness truth';

my @module_report = smoke_report(visual_board => _alternate_visual_board());
like join("\n", @module_report), qr/^gobanftp\.oracle=ok$/m,
    'smoke module can run without the source-art wrapper';

my @wrapper_report = split /\n/, $smoke_out;
my @truth_fields = qw(
    game.size
    event.id
    rules.move
    profile_id
    adapter_id
    accepted_count
    event_set_root
    replay_status
    canonical_tip
    board_hash
    sgf_hash
    variations_sgf_hash
    diagnostic_count
);
for my $field (@truth_fields) {
    is _field(\@module_report, $field), _field(\@wrapper_report, $field),
        "alternate visual glyphs do not change $field";
}

my @no_inline_report;
{
    no warnings 'redefine';
    local *GobanFTP::Oracle::Smoke::inline_c_smoke = sub { 'forced value=0' };
    @no_inline_report = smoke_report(visual_board => _alternate_visual_board());
}
for my $field (@truth_fields) {
    is _field(\@no_inline_report, $field), _field(\@wrapper_report, $field),
        "Inline::C availability does not change $field";
}
is _field(\@no_inline_report, 'inline_c'), 'forced value=0',
    'Inline::C smoke line can vary independently';

my ($help_status, $help_out, $help_err) = run_cmd($^X, $script, '--help');
is $help_status, 0, 'source-art oracle --help exits 0';
like $help_out, qr/^usage: perl oracle\/goban\.pl --smoke$/m, 'source-art oracle prints usage';

my ($bad_status, $bad_out, $bad_err) = run_cmd($^X, $script, '--replay');
is $bad_status, 64, 'source-art oracle rejects non-wrapper commands';
like $bad_err, qr/^usage: perl oracle\/goban\.pl --smoke$/m, 'source-art oracle prints usage on bad command';

done_testing;

sub run_cmd {
    my (@cmd) = @_;

    my $err = gensym;
    my $pid = open3(my $in, my $out, $err, @cmd);
    close $in or die "close stdin for @cmd: $!";

    my $stdout = do { local $/; <$out> // '' };
    my $stderr = do { local $/; <$err> // '' };

    waitpid $pid, 0;
    return ($? >> 8, $stdout, $stderr);
}

sub _slurp {
    my ($path) = @_;

    open my $fh, '<:encoding(UTF-8)', $path or die "open $path: $!";
    my $text = do { local $/; <$fh> };
    close $fh or die "close $path: $!";

    return $text;
}

sub _alternate_visual_board {
    return [
        [qw(+ + + + + + + + +)],
        [qw(+ . . . . . . . +)],
        [qw(+ . . . . . . . +)],
        [qw(+ . . . . . . . +)],
        [qw(+ . . . + . . . +)],
        [qw(+ . . . . . . . +)],
        [qw(+ . . . . . . . +)],
        [qw(+ . . . . . . . +)],
        [qw(+ + + + + + + + +)],
    ];
}

sub _source_motifs {
    my ($source) = @_;

    my @motifs;
    push @motifs, 'altar'
        if $source =~ /^# \| GOFTP\/1 ORACLE\s+\|$/m
        && $source =~ /^# \| file bytes are shadow :: this wrapper only lights the smoke test\s+\|$/m;
    push @motifs, 'goban'
        if $source =~ /^\s*my\s+\@ORACLE_GOBAN\s*=\s*\(/m
        && $source =~ /^#\s+a\s+b\s+c\s+d\s+e\s+f\s+g\s+h\s+i\s*$/m;
    push @motifs, 'arch-gate'
        if $source =~ /arch-gate\s*[-:]\s*(?:a\s+)?(?:non-consensus|easter egg).*?(?:not a protocol input|source-art only)/s
        && $source =~ /^(?:#\s*)?\s*\/\\\n(?:#\s*)?\s*\/__\\\n(?:#\s*)?\s*\/_\/\\_\\$/m;

    return @motifs;
}

sub _executable_board_from {
    my ($source) = @_;

    my @board;
    while ($source =~ /^\s*\[\s+(.*?)\s+\],\s*#\s*([1-9])\b.*$/mg) {
        my ($row_text, $label) = ($1, $2);
        my @cells = $row_text =~ /q\(([.+])\)/g;
        is scalar(@cells), 9, "source-art row $label has nine executable cells";
        for my $cell (@cells) {
            ok $cell eq '.' || $cell eq '+', "source-art row $label uses a boring cell glyph";
        }
        push @board, { label => $label, cells => \@cells };
    }

    return @board;
}

sub _cell_count {
    my ($board) = @_;

    my $count = 0;
    $count += scalar @{ $_->{cells} } for @$board;

    return $count;
}

sub _star_points {
    my ($board) = @_;

    my @cols = qw(a b c d e f g h i);
    my @stars;
    for my $row (@$board) {
        for my $i (0 .. $#{ $row->{cells} }) {
            push @stars, "$cols[$i]$row->{label}" if $row->{cells}->[$i] eq '+';
        }
    }

    return @stars;
}

sub _field {
    my ($lines, $field) = @_;

    for my $line (@$lines) {
        return $1 if $line =~ /^\Q$field\E=(.*)$/;
    }

    die "missing field $field";
}
