package GobanFTP::Oracle::Smoke;

use v5.34;
use strict;
use warnings;

use Exporter qw(import);
use File::Temp qw(tempdir);

use GobanFTP::DAG qw(build);
use GobanFTP::Filename::Grammar qw(event_id_for parse_event);
use GobanFTP::GameSpec qw(parse_basename);
use GobanFTP::Rules;

our @EXPORT_OK = qw(run_smoke smoke_report inline_c_smoke);

sub run_smoke {
    my (%args) = @_;

    my $out = $args{out} // *STDOUT;
    print {$out} "$_\n" for smoke_report(%args);

    return 0;
}

sub smoke_report {
    my (%args) = @_;

    my $game = 'g1.id-smoke.s9.r-chinese-area-v1.k6500.pb-black.pw-white';
    my ($spec, $spec_error) = parse_basename($game);
    die "gamespec: $spec_error\n" if defined $spec_error;

    if (exists $args{visual_board}) {
        die "source-art: board shape mismatch\n"
            if !_visual_board_is($args{visual_board}, $spec->{size});
    }

    my $event_without_hash = 'm1.p000001.b.play-aa.pa-genesis.by-black.n-smoke';
    my $event_name = $event_without_hash . '.h-' . event_id_for($game, $event_without_hash);

    my ($event, $event_error) = parse_event($event_name, game_descriptor => $game);
    die "event: $event_error\n" if defined $event_error;

    my $dag = build(events => [{ name => $event_name, event => $event }]);
    my @moves = $dag->topological_move_ids;
    die "dag: expected one smoke move\n" if @moves != 1;

    my $rules = GobanFTP::Rules->new(size => $spec->{size}, rules => $spec->{rules});
    my $state = $rules->apply_move($rules->initial_state, $event);
    die "rules: $state->{reason}\n" if !$state->{ok};

    return (
        'gobanftp.oracle=ok',
        "game.size=$spec->{size}",
        "event.id=$moves[0]",
        'rules.move=ok',
        'inline_c=' . inline_c_smoke(),
    );
}

sub inline_c_smoke {
    my $load_ok = eval {
        require Inline;
        require Inline::C;
        1;
    };
    return 'missing' if !$load_ok;

    my $dir = tempdir('gobanftp-inline-XXXXXX', TMPDIR => 1, CLEANUP => 1);
    local $ENV{PERL_INLINE_DIRECTORY} = $dir;

    my $value = eval {
        Inline->bind(C => <<'END_C', DIRECTORY => $dir);
int gobanftp_inline_smoke(void) {
    return 361;
}
END_C
        gobanftp_inline_smoke();
    };

    return 'skip' if $@;
    return $value == 361 ? 'ok value=361' : "bad value=$value";
}

sub _visual_board_is {
    my ($board, $size) = @_;

    return 0 if ref($board) ne 'ARRAY' || @$board != $size;
    for my $row (@$board) {
        return 0 if ref($row) ne 'ARRAY' || @$row != $size;
    }

    return 1;
}

1;

__END__

=head1 NAME

GobanFTP::Oracle::Smoke - smoke scenario used by the source-art wrapper

=cut
