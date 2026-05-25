use v5.34;
use strict;
use warnings;

use FindBin;
use File::Spec;
use Text::ParseWords qw(shellwords);
use Test::More;

my $repo_root = File::Spec->rel2abs("$FindBin::Bin/..");
my $workflow = _read_text(File::Spec->catfile($repo_root, qw(.github workflows ci.yml)));
my $gate = _read_text(File::Spec->catfile($repo_root, qw(docs V1_1_RELEASE_GATE.md)));

subtest 'forbidden command scanner catches executable release operations only' => sub {
    for my $case (
        ['env X=1 git push', 'git push'],
        ['env -u FOO git push', 'git push'],
        ['command git push', 'git push'],
        ['git -C . push', 'git push'],
        ['git --git-dir=.git push', 'git push'],
        ['make -C . dist', 'make dist'],
        ['make --directory . dist', 'make dist'],
        ['make --jobs=2 dist', 'make dist'],
        ["bash -lc 'git push'", 'git push'],
        ["bash -lc 'set -e; git push'", 'git push'],
        ["bash -lc 'git push && true'", 'git push'],
        ['run: git -C . push', 'git push'],
        [q{run: 'git push'}, 'git push'],
        [qq{run: "git push"}, 'git push'],
        ["run: >-\n  git\n  push", 'git push'],
        ["run: |\n  git \\\n    push", 'git push'],
        ['gh release upload artifact.tar.gz', 'gh release'],
        ['npx vercel deploy', 'vercel deploy'],
    ) {
        my ($line, $kind) = @$case;
        my @hits = _forbidden_command_hits($line);
        is scalar(@hits), 1, "$line is flagged once";
        like $hits[0] // '', qr/\Q$kind\E/, "$line is flagged as $kind";
    }

    for my $line (
        'must not tag, push, upload, deploy',
        'not P1 source-candidate evidence',
        'no_tag_push_upload_deploy=1',
        'recommended_checks=prove -lr t/ci-source-release-gate.t',
        q{echo "git push; make dist"},
    ) {
        is_deeply [_forbidden_command_hits($line)], [], "$line is not treated as a command";
    }
};

subtest 'CI stays source-only and fixture-local' => sub {
    is_deeply [_forbidden_command_hits($workflow)], [],
        'workflow avoids forbidden release/upload/deploy/dist commands';
    unlike $workflow, qr/\bGOBANFTP_STORE:\s*(?:ftp|webdav|dns-record|git-tree)\b/,
        'workflow avoids live store modes';
    unlike $workflow, qr/\bGOBANFTP_(?:FTP|WEBDAV|DNS|GIT)_/,
        'workflow avoids live substrate credentials and endpoints';
    like $workflow, qr/permissions:\n\s+contents: read/m, 'workflow has read-only repository permission';
    like $workflow, qr/prove -lr t/, 'workflow runs local test suite';
};

subtest 'release gate documents omissions without executing release commands' => sub {
    like $gate, qr/must not tag, push, upload,\ndeploy/,
        'gate explicitly forbids tag push upload deploy';
    like $gate, qr/run `make dist`, run\n`make disttest`, or run `make distcheck`/,
        'gate explicitly forbids make dist family';

    my @command_lines = _fenced_command_lines($gate);
    for my $line (@command_lines) {
        unlike $line, qr/\A\s*(?:git\s+tag|git\s+push|gh\s+release)\b/,
            "gate command does not release: $line";
        unlike $line, qr/\A\s*(?:make\s+dist|make\s+disttest|make\s+distcheck)\b/,
            "gate command does not build distributions: $line";
        unlike $line, qr/\A\s*(?:upload|deploy)\b/i,
            "gate command does not upload or deploy: $line";
    }
};

subtest 'documentation guard has no executable release commands' => sub {
    my @docs = (
        'README.md',
        'README.zh-CN.md',
        'README.ja.md',
        File::Spec->catfile(qw(docs SHOWCASE.md)),
        File::Spec->catfile(qw(docs PROFILES.md)),
        File::Spec->catfile(qw(docs V1_1_RELEASE_GATE.md)),
    );

    for my $rel (@docs) {
        my $text = _read_text(File::Spec->catfile($repo_root, $rel));
        is_deeply [_forbidden_command_hits($text)], [],
            "$rel has no executable tag/push/upload/deploy/dist command";
    }
};

done_testing;

sub _forbidden_command_hits {
    my ($text) = @_;

    my @hits;
    for my $entry (_logical_command_entries($text)) {
        my ($line_no, $raw) = @$entry;
        my @segments = _command_segments($raw);
        for my $segment (@segments) {
            my $kind = _forbidden_command_kind($segment);
            push @hits, "$line_no:$kind:$raw" if defined $kind;
        }
    }

    return @hits;
}

sub _logical_command_entries {
    my ($text) = @_;

    my @raw_lines = split /\n/, $text // '';
    my @entries;

    for (my $i = 0; $i < @raw_lines; $i++) {
        my $raw = $raw_lines[$i];

        if ($raw =~ /\A(\s*)(?:-\s*)?(?:run|command|script):\s*([>|])-?\s*(?:#.*)?\z/) {
            my $base_indent = length($1);
            my $style = $2;
            my @block;
            my $j = $i + 1;

            while ($j < @raw_lines) {
                my $next = $raw_lines[$j];
                if ($next =~ /\S/) {
                    my ($indent) = $next =~ /\A(\s*)/;
                    last if length($indent) <= $base_indent;
                }
                push @block, [ $j + 1, $next ];
                $j++;
            }

            if ($style eq '>') {
                my @parts = map {
                    my $line = $_->[1];
                    $line =~ s/\A\s+//;
                    $line =~ s/\s+\z//;
                    $line;
                } grep { $_->[1] =~ /\S/ } @block;
                push @entries, [ $i + 1, 'run: ' . join(' ', @parts) ] if @parts;
            }
            else {
                for my $part (@block) {
                    my $line = $part->[1];
                    $line =~ s/\A\s+//;
                    push @entries, [ $part->[0], $line ] if $line =~ /\S/;
                }
            }

            $i = $j - 1;
            next;
        }

        push @entries, [ $i + 1, $raw ];
    }

    return _join_shell_continuations(@entries);
}

sub _join_shell_continuations {
    my (@entries) = @_;

    my @joined;
    my ($start_line, $buffer);
    for my $entry (@entries) {
        my ($line_no, $raw) = @$entry;
        my $line = $raw // '';

        if (defined $buffer) {
            $line =~ s/\A\s+//;
            $buffer .= ' ' . $line;
        }
        else {
            $start_line = $line_no;
            $buffer = $line;
        }

        if (_has_shell_continuation($buffer)) {
            $buffer =~ s/\s*\\\s*\z/ /;
            next;
        }

        push @joined, [ $start_line, $buffer ];
        undef $buffer;
    }

    push @joined, [ $start_line, $buffer ] if defined $buffer;
    return @joined;
}

sub _has_shell_continuation {
    my ($line) = @_;

    my $trimmed = $line // '';
    $trimmed =~ s/\s+\z//;
    return $trimmed =~ /(?<!\\)\\\z/ ? 1 : 0;
}

sub _command_segments {
    my ($raw) = @_;

    my $line = $raw // '';
    $line =~ s/\A\s+|\s+\z//g;
    return if $line eq '' || $line =~ /\A```/ || $line =~ /\A#/;

    $line =~ s/\A[-*]\s+//;
    $line =~ s/\A(?:run|command|script):\s*//;
    return if $line =~ /\A[|>]-?\s*\z/;
    $line =~ s/\A\$\s+//;
    $line = _unwrap_quoted_scalar($line);

    return _shell_segments($line);
}

sub _unwrap_quoted_scalar {
    my ($line) = @_;

    return $line if $line !~ /\A(?:"(?:[^"\\]|\\.)*"|'[^']*')\z/;
    my @tokens = _command_tokens($line);
    return @tokens == 1 ? $tokens[0] : $line;
}

sub _shell_segments {
    my ($line) = @_;

    my @segments;
    my $buffer = '';
    my $quote = '';
    my $escape = 0;
    my @chars = split //, $line // '';

    for (my $i = 0; $i < @chars; $i++) {
        my $char = $chars[$i];

        if ($escape) {
            $buffer .= $char;
            $escape = 0;
            next;
        }
        if ($char eq '\\' && $quote ne q{'}) {
            $buffer .= $char;
            $escape = 1;
            next;
        }
        if ($quote ne '') {
            $quote = '' if $char eq $quote;
            $buffer .= $char;
            next;
        }
        if ($char eq q{'} || $char eq q{"}) {
            $quote = $char;
            $buffer .= $char;
            next;
        }
        if ($char eq ';') {
            _push_shell_segment(\@segments, $buffer);
            $buffer = '';
            next;
        }
        if (($char eq '&' || $char eq '|') && (($chars[$i + 1] // '') eq $char)) {
            _push_shell_segment(\@segments, $buffer);
            $buffer = '';
            $i++;
            next;
        }

        $buffer .= $char;
    }

    _push_shell_segment(\@segments, $buffer);
    return @segments;
}

sub _push_shell_segment {
    my ($segments, $segment) = @_;

    $segment //= '';
    $segment =~ s/\A\s+|\s+\z//g;
    push @$segments, $segment if $segment ne '';
}

sub _forbidden_command_kind {
    my ($segment) = @_;

    my $command = _strip_command_prefixes($segment);
    return if $command eq '';

    my $shell = _shell_wrapper_forbidden_kind($command);
    return $shell if defined $shell;

    my $git = _git_forbidden_kind($command);
    return $git if defined $git;

    return 'gh release' if $command =~ /\Agh\s+release\b/;

    my $make = _make_dist_kind($command);
    return $make if defined $make;

    return 'vercel deploy' if $command =~ /\A(?:npx\s+)?vercel\s+deploy\b/;
    return 'netlify deploy' if $command =~ /\A(?:npx\s+)?netlify\s+deploy\b/;
    return 'wrangler deploy' if $command =~ /\A(?:npx\s+)?wrangler\s+deploy\b/;

    return;
}

sub _first_forbidden_kind_in_text {
    my ($text) = @_;

    for my $hit (_forbidden_command_hits($text)) {
        return $1 if $hit =~ /\A[0-9]+:([^:]+):/;
    }

    return;
}

sub _shell_wrapper_forbidden_kind {
    my ($command) = @_;

    my @tokens = _command_tokens($command);
    return if !@tokens || $tokens[0] !~ /\A(?:bash|sh)\z/;

    for (my $i = 1; $i < @tokens; $i++) {
        my $token = $tokens[$i];
        next if !defined $token;
        if ($token eq '-c' || $token =~ /\A-[^-]*c[^-]*\z/) {
            return if !defined $tokens[$i + 1];
            return _first_forbidden_kind_in_text($tokens[$i + 1]);
        }
    }

    return;
}

sub _git_forbidden_kind {
    my ($command) = @_;

    my @tokens = _command_tokens($command);
    return if !@tokens || $tokens[0] ne 'git';
    shift @tokens;

    while (@tokens) {
        my $token = $tokens[0];
        if ($token eq '-C' || $token eq '-c'
            || $token eq '--git-dir' || $token eq '--work-tree'
            || $token eq '--namespace' || $token eq '--config-env') {
            shift @tokens;
            shift @tokens if @tokens;
            next;
        }
        if ($token =~ /\A--(?:git-dir|work-tree|namespace|config-env|exec-path)=/) {
            shift @tokens;
            next;
        }
        if ($token =~ /\A-[Cc].+\z/) {
            shift @tokens;
            next;
        }
        if ($token =~ /\A--(?:no-pager|paginate|bare|literal-pathspecs|glob-pathspecs|noglob-pathspecs|icase-pathspecs)\z/) {
            shift @tokens;
            next;
        }
        if ($token =~ /\A-[A-Za-z]+\z/) {
            shift @tokens;
            next;
        }
        last;
    }

    return if !@tokens;
    return 'git tag' if $tokens[0] eq 'tag';
    return 'git push' if $tokens[0] eq 'push';
    return;
}

sub _strip_command_prefixes {
    my ($segment) = @_;

    my $command = $segment // '';
    $command =~ s/\A\s+|\s+\z//g;

    if ($command =~ s/\Aenv\s+//) {
        while (1) {
            if ($command =~ s/\A(?:-i|--ignore-environment)\s+//) {
                next;
            }
            if ($command =~ s/\A(?:-u|--unset|-C|--chdir)\s+(?:"[^"]*"|'[^']*'|\S+)\s+//) {
                next;
            }
            if ($command =~ s/\A--(?:unset|chdir)=(?:"[^"]*"|'[^']*'|\S+)\s+//) {
                next;
            }
            if ($command =~ s/\A[A-Za-z_][A-Za-z0-9_]*=(?:"[^"]*"|'[^']*'|\S+)\s+//) {
                next;
            }
            last;
        }
    }

    $command =~ s/\A(?:command|builtin)\s+//;
    while ($command =~ s/\A[A-Za-z_][A-Za-z0-9_]*=(?:"[^"]*"|'[^']*'|\S+)\s+//) {
        next;
    }
    $command =~ s/\A\s+|\s+\z//g;

    return $command;
}

sub _make_dist_kind {
    my ($command) = @_;

    my @tokens = _command_tokens($command);
    return if !@tokens || $tokens[0] ne 'make';
    shift @tokens;
    while (@tokens) {
        my $token = $tokens[0];
        if ($token eq '-C' || $token eq '--directory'
            || $token eq '-f' || $token eq '--file'
            || $token eq '-I' || $token eq '--include-dir') {
            shift @tokens;
            shift @tokens if @tokens;
            next;
        }
        if ($token =~ /\A--(?:directory|file|include-dir)=/) {
            shift @tokens;
            next;
        }
        if ($token eq '-j' || $token eq '--jobs'
            || $token eq '-l' || $token eq '--load-average'
            || $token eq '--max-load' || $token eq '--output-sync') {
            shift @tokens;
            shift @tokens if @tokens;
            next;
        }
        if ($token =~ /\A--(?:jobs|load-average|max-load|output-sync)=/) {
            shift @tokens;
            next;
        }
        if ($token =~ /\A--[A-Za-z][A-Za-z0-9_-]*(?:=.*)?\z/) {
            shift @tokens;
            next;
        }
        if ($token =~ /\A-[A-Za-z].*\z/) {
            shift @tokens;
            next;
        }
        if ($token =~ /\A[A-Za-z_][A-Za-z0-9_]*=/) {
            shift @tokens;
            next;
        }
        last;
    }

    return if !@tokens || $tokens[0] !~ /\Adist(?:test|check)?\z/;
    return "make $tokens[0]";
}

sub _command_tokens {
    my ($command) = @_;

    my @tokens = eval { shellwords($command // '') };
    return @tokens if !$@;
    return split /\s+/, $command // '';
}

sub _fenced_command_lines {
    my ($markdown) = @_;

    my @lines;
    my $in_sh = 0;
    for my $line (split /\n/, $markdown) {
        if ($line =~ /\A```sh\s*\z/) {
            $in_sh = 1;
            next;
        }
        if ($line =~ /\A```\s*\z/) {
            $in_sh = 0;
            next;
        }
        push @lines, $line if $in_sh && $line !~ /\A\s*\z/;
    }

    return @lines;
}

sub _read_text {
    my ($path) = @_;

    open my $fh, '<:encoding(UTF-8)', $path or die "open $path: $!";
    local $/;
    my $text = <$fh>;
    close $fh or die "close $path: $!";
    return $text // '';
}
