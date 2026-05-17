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

ok -f $script, 'source-art oracle exists';

my $source = _slurp($script);
like $source, qr/GobanFTP::Oracle::Smoke/, 'source-art wrapper delegates smoke scenario to a module';
my @gobanftp_uses = $source =~ /^\s*use\s+(GobanFTP::[A-Za-z0-9_:]+)\b/mg;
is_deeply \@gobanftp_uses, ['GobanFTP::Oracle::Smoke'],
    'source-art wrapper only imports the smoke module';
unlike $source, qr/^\s*use\s+GobanFTP::(?:DAG|EventID|Filename::Grammar|GameSpec|Projection|Replay|Rules|SGF|Store)\b/m,
    'source-art wrapper does not import protocol, replay, rules, SGF, projection, or store modules directly';
unlike $source, qr/\b(?:event_id_for|parse_event|build\(|apply_move|GOFTP-EVENT|m1\.|a1\.|g1\.id-)\b/,
    'source-art wrapper does not embed protocol or rule implementation traces';

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
like $smoke_out, qr/^inline_c=(?:missing|skip|ok value=361)$/m, 'Inline::C smoke is optional';

my @module_report = smoke_report(visual_board => _alternate_visual_board());
like join("\n", @module_report), qr/^gobanftp\.oracle=ok$/m,
    'smoke module can run without the source-art wrapper';

my @wrapper_report = split /\n/, $smoke_out;
for my $field (qw(game.size event.id rules.move)) {
    is _field(\@module_report, $field), _field(\@wrapper_report, $field),
        "visual glyphs do not change $field";
}

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
