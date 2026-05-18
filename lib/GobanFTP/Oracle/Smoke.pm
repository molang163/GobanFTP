package GobanFTP::Oracle::Smoke;

use v5.34;
use strict;
use warnings;

use Exporter qw(import);
use File::Temp qw(tempdir);

use GobanFTP::Witness qw(witness_for_listing);

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
    my $event = 'm1.p000001.b.play-aa.pa-genesis.by-black.n-smoke.h-nnj11k89biuv36dk';

    if (exists $args{visual_board}) {
        die "source-art: board shape mismatch\n"
            if !_visual_board_is($args{visual_board}, 9);
    }

    my $witness = witness_for_listing(
        profile_id      => 'local-goftp1',
        game_descriptor => $game,
        raw_names       => [$event],
    );
    die "witness: replay_status=$witness->{replay_status}\n"
        if $witness->{replay_status} ne 'ok';
    die "witness: expected one accepted event\n"
        if $witness->{accepted_count} != 1;

    return (
        'gobanftp.oracle=ok',
        'game.size=9',
        "event.id=$witness->{canonical_tip}",
        'rules.move=ok',
        "profile_id=$witness->{profile_id}",
        "adapter_id=$witness->{adapter_id}",
        "accepted_count=$witness->{accepted_count}",
        "event_set_root=$witness->{event_set_root}",
        "replay_status=$witness->{replay_status}",
        "canonical_tip=$witness->{canonical_tip}",
        "board_hash=$witness->{board_hash}",
        "sgf_hash=$witness->{sgf_hash}",
        "variations_sgf_hash=$witness->{variations_sgf_hash}",
        "diagnostic_count=$witness->{diagnostic_count}",
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
