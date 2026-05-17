package GobanFTP::Rules::C;

use v5.34;
use strict;
use warnings;

use Carp qw(croak);

my $BOUND;
my $BIND_ERROR;

sub available {
    my ($class) = @_;

    return 0 if defined _disabled_error();

    $class->_bind;
    return $BOUND ? 1 : 0;
}

sub load_error {
    my ($class) = @_;

    if (defined(my $disabled = _disabled_error())) {
        return $disabled;
    }

    $class->_bind;
    return $BOUND ? undef : $BIND_ERROR;
}

sub status {
    my ($class) = @_;

    my $available = $class->available ? 1 : 0;
    return {
        available => $available,
        error     => $available ? undef : $class->load_error,
    };
}

sub apply_play {
    my ($class, @args) = @_;

    my %args = @args == 1 && ref($args[0]) eq 'HASH' ? %{ $args[0] } : @args;
    my ($board_bytes, $size, $index, $stone) = _validate_args(\%args);

    if (defined(my $disabled = _disabled_error())) {
        croak "rules.c.unavailable: $disabled";
    }

    $class->_bind;
    croak 'rules.c.unavailable' . (defined($BIND_ERROR) ? ": $BIND_ERROR" : '')
        if !$BOUND;

    my $apply = __PACKAGE__->can('rules_c_apply_play')
        or croak 'rules.c.unavailable: missing bound symbol';

    return $apply->($board_bytes, $size, $index, $stone);
}

sub _bind {
    return if defined $BOUND;

    my $ok = eval {
        require Inline;
        require Inline::C;
        Inline->bind(C => _c_source());
        1;
    };

    if ($ok) {
        $BOUND      = 1;
        $BIND_ERROR = undef;
        return;
    }

    $BOUND      = 0;
    $BIND_ERROR = $@ || 'Inline::C load failed';
    chomp $BIND_ERROR;
    return;
}

sub _validate_args {
    my ($args) = @_;

    my $size = $args->{size};
    croak 'rules.c.size'
        if !defined($size) || ref($size) || $size !~ /\A(?:0|[1-9][0-9]*)\z/ || $size < 2 || $size > 26;

    my $total = $size * $size;
    my $board_bytes = $args->{board_bytes};
    croak 'rules.c.board_bytes'
        if !defined($board_bytes) || ref($board_bytes) || length($board_bytes) != $total;

    for my $cell (unpack 'C*', $board_bytes) {
        croak 'rules.c.board_bytes' if $cell > 2;
    }

    my $index = $args->{index};
    croak 'rules.c.index'
        if !defined($index) || ref($index) || $index !~ /\A(?:0|[1-9][0-9]*)\z/ || $index >= $total;

    my $stone = $args->{stone};
    croak 'rules.c.stone'
        if !defined($stone) || ref($stone) || $stone !~ /\A[12]\z/;

    return ($board_bytes, 0 + $size, 0 + $index, 0 + $stone);
}

sub _disabled_error {
    return undef if !$ENV{GOBANFTP_RULES_DISABLE_C};
    return 'disabled by GOBANFTP_RULES_DISABLE_C';
}

sub _c_source {
    return <<'END_C';
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include <string.h>

#define GOBANFTP_RULES_C_MAX 676

static int gobanftp_rules_c_neighbors(int index, int size, int *neighbors) {
    int count = 0;
    int x = index % size;
    int y = index / size;

    if (x > 0) {
        neighbors[count++] = index - 1;
    }
    if (x < size - 1) {
        neighbors[count++] = index + 1;
    }
    if (y > 0) {
        neighbors[count++] = index - size;
    }
    if (y < size - 1) {
        neighbors[count++] = index + size;
    }

    return count;
}

static void gobanftp_rules_c_flood_group(
    unsigned char *cells,
    int size,
    int start,
    unsigned char *seen,
    unsigned char *lib_seen,
    int *group,
    int *group_count,
    int *liberty_count
) {
    int stack[GOBANFTP_RULES_C_MAX];
    int top = 0;
    int total = size * size;
    unsigned char color = cells[start];

    memset(seen, 0, (size_t)total);
    memset(lib_seen, 0, (size_t)total);
    *group_count = 0;
    *liberty_count = 0;

    seen[start] = 1;
    stack[top++] = start;

    while (top > 0) {
        int index = stack[--top];
        int neighbors[4];
        int neighbor_count;
        int i;

        group[(*group_count)++] = index;
        neighbor_count = gobanftp_rules_c_neighbors(index, size, neighbors);

        for (i = 0; i < neighbor_count; i++) {
            int neighbor = neighbors[i];
            unsigned char value = cells[neighbor];

            if (value == 0) {
                if (!lib_seen[neighbor]) {
                    lib_seen[neighbor] = 1;
                    (*liberty_count)++;
                }
                continue;
            }

            if (value == color && !seen[neighbor]) {
                seen[neighbor] = 1;
                stack[top++] = neighbor;
            }
        }
    }
}

static SV *gobanftp_rules_c_result(
    int ok,
    const char *reason,
    unsigned char *cells,
    int total,
    unsigned char *captured
) {
    HV *result = newHV();
    AV *captures = newAV();
    int i;

    hv_store(result, "ok", 2, newSViv(ok), 0);

    if (reason != NULL) {
        hv_store(result, "reason", 6, newSVpv(reason, 0), 0);
    }

    hv_store(result, "board_bytes", 11, newSVpvn((const char *)cells, (STRLEN)total), 0);

    if (captured != NULL) {
        for (i = 0; i < total; i++) {
            if (captured[i]) {
                av_push(captures, newSViv(i));
            }
        }
    }

    hv_store(result, "captures", 8, newRV_noinc((SV *)captures), 0);
    return newRV_noinc((SV *)result);
}

SV *rules_c_apply_play(SV *board_sv, IV size_iv, IV index_iv, IV stone_iv) {
    STRLEN len;
    unsigned char *input = (unsigned char *)SvPVbyte(board_sv, len);
    unsigned char original[GOBANFTP_RULES_C_MAX];
    unsigned char cells[GOBANFTP_RULES_C_MAX];
    unsigned char checked[GOBANFTP_RULES_C_MAX];
    unsigned char captured[GOBANFTP_RULES_C_MAX];
    unsigned char seen[GOBANFTP_RULES_C_MAX];
    unsigned char lib_seen[GOBANFTP_RULES_C_MAX];
    int group[GOBANFTP_RULES_C_MAX];
    int size = (int)size_iv;
    int index = (int)index_iv;
    int stone = (int)stone_iv;
    int total;
    int opponent;
    int neighbors[4];
    int neighbor_count;
    int group_count = 0;
    int liberty_count = 0;
    int i;

    if (size < 2 || size > 26) {
        return gobanftp_rules_c_result(0, "rules.c.size", input, (int)len, NULL);
    }

    total = size * size;
    if ((int)len != total || total > GOBANFTP_RULES_C_MAX) {
        return gobanftp_rules_c_result(0, "rules.c.board_bytes", input, (int)len, NULL);
    }

    if (index < 0 || index >= total) {
        return gobanftp_rules_c_result(0, "rules.c.index", input, total, NULL);
    }

    if (stone != 1 && stone != 2) {
        return gobanftp_rules_c_result(0, "rules.c.stone", input, total, NULL);
    }

    for (i = 0; i < total; i++) {
        if (input[i] > 2) {
            return gobanftp_rules_c_result(0, "rules.c.board_bytes", input, total, NULL);
        }
        original[i] = input[i];
        cells[i] = input[i];
        checked[i] = 0;
        captured[i] = 0;
    }

    if (cells[index] != 0) {
        return gobanftp_rules_c_result(0, "occupied", original, total, NULL);
    }

    opponent = stone == 1 ? 2 : 1;
    cells[index] = (unsigned char)stone;

    neighbor_count = gobanftp_rules_c_neighbors(index, size, neighbors);
    for (i = 0; i < neighbor_count; i++) {
        int neighbor = neighbors[i];
        int j;

        if (cells[neighbor] != opponent || checked[neighbor]) {
            continue;
        }

        gobanftp_rules_c_flood_group(
            cells,
            size,
            neighbor,
            seen,
            lib_seen,
            group,
            &group_count,
            &liberty_count
        );

        for (j = 0; j < group_count; j++) {
            checked[group[j]] = 1;
        }

        if (liberty_count != 0) {
            continue;
        }

        for (j = 0; j < group_count; j++) {
            captured[group[j]] = 1;
        }
    }

    for (i = 0; i < total; i++) {
        if (captured[i]) {
            cells[i] = 0;
        }
    }

    gobanftp_rules_c_flood_group(
        cells,
        size,
        index,
        seen,
        lib_seen,
        group,
        &group_count,
        &liberty_count
    );

    if (liberty_count == 0) {
        return gobanftp_rules_c_result(0, "suicide", original, total, NULL);
    }

    return gobanftp_rules_c_result(1, NULL, cells, total, captured);
}
END_C
}

1;

__END__

=head1 NAME

GobanFTP::Rules::C - optional Inline::C board-mechanics boundary

=cut
