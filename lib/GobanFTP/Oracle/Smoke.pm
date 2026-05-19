package GobanFTP::Oracle::Smoke;

use v5.34;
use strict;
use warnings;

use Exporter qw(import);
use Config qw(%Config);
use File::Spec;
use File::Temp qw(tempdir);

use GobanFTP::Witness qw(witness_for_listing);

our @EXPORT_OK = qw(run_smoke smoke_report inline_c_smoke asm_ritual_smoke);

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
        'asm_ritual=' . asm_ritual_smoke(),
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

sub asm_ritual_smoke {
    return 'disabled' if !$ENV{GOBANFTP_ORACLE_ASM_SMOKE};

    my $arch = $Config{archname} // '';
    return 'skip platform=' . _token($^O)
        if $^O ne 'linux';
    return 'skip platform=' . _token($arch || 'unknown')
        if $arch !~ /(?:x86_64|amd64)/i;

    my @cc = _command_words($ENV{CC} // $Config{cc} // 'cc');
    return 'skip cc=missing' if !@cc || !_command_available($cc[0]);

    my $dir = tempdir('gobanftp-asm-XXXXXX', TMPDIR => 1, CLEANUP => 1);
    my $asm = File::Spec->catfile($dir, 'ritual.S');
    my $c = File::Spec->catfile($dir, 'main.c');
    my $exe = File::Spec->catfile($dir, 'ritual-smoke');

    _write_file($asm, <<'ASM');
.text
.globl gobanftp_asm_ritual
.type gobanftp_asm_ritual, @function
gobanftp_asm_ritual:
    movl $361, %eax
    ret
.size gobanftp_asm_ritual, .-gobanftp_asm_ritual
.section .note.GNU-stack,"",@progbits
ASM

    _write_file($c, <<'C');
extern int gobanftp_asm_ritual(void);
int main(void) {
    return gobanftp_asm_ritual() == 361 ? 0 : 1;
}
C

    return 'skip compile' if !_quiet_system(@cc, '-o', $exe, $c, $asm);
    return _quiet_system($exe) ? 'ok value=361' : 'skip runtime';
}

sub _visual_board_is {
    my ($board, $size) = @_;

    return 0 if ref($board) ne 'ARRAY' || @$board != $size;
    for my $row (@$board) {
        return 0 if ref($row) ne 'ARRAY' || @$row != $size;
    }

    return 1;
}

sub _write_file {
    my ($path, $text) = @_;

    open my $fh, '>:encoding(UTF-8)', $path or die "write $path: $!";
    print {$fh} $text;
    close $fh or die "close $path: $!";
}

sub _quiet_system {
    my (@cmd) = @_;

    open my $null_out, '>', File::Spec->devnull or die 'open devnull: ' . $!;
    open my $null_err, '>', File::Spec->devnull or die 'open devnull: ' . $!;
    local *STDOUT = $null_out;
    local *STDERR = $null_err;
    return system(@cmd) == 0;
}

sub _command_words {
    my ($command) = @_;
    return grep { $_ ne '' } split /\s+/, $command // '';
}

sub _command_available {
    my ($command) = @_;
    return 0 if !defined($command) || $command eq '';
    return -x $command && !-d $command if File::Spec->file_name_is_absolute($command);
    for my $dir (File::Spec->path) {
        my $path = File::Spec->catfile($dir, $command);
        return 1 if -x $path && !-d $path;
    }
    return 0;
}

sub _token {
    my ($value) = @_;
    $value //= 'unknown';
    $value =~ s/[^A-Za-z0-9_.-]+/_/g;
    return $value eq '' ? 'unknown' : $value;
}

1;

__END__

=head1 NAME

GobanFTP::Oracle::Smoke - smoke scenario used by the source-art wrapper

=cut
