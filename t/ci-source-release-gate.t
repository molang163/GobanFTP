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
        ['make manifest dist distcheck', 'make dist'],
        ['make test tardist zipdist', 'make tardist'],
        ["bash -lc 'git push'", 'git push'],
        ["bash -lc 'set -e; git push'", 'git push'],
        ["bash -lc 'git push && true'", 'git push'],
        ['run: git -C . push', 'git push'],
        [q{run: 'git push'}, 'git push'],
        [qq{run: "git push"}, 'git push'],
        ["run: >-\n  git\n  push", 'git push'],
        ["run: |\n  git \\\n    push", 'git push'],
        ['gh release create v1.1.0-beta.1 artifact.tar.gz', 'gh release create'],
        ['gh release upload artifact.tar.gz', 'gh release upload'],
        ['cpan-upload GobanFTP-1.000.tar.gz', 'cpan-upload'],
        ['pause-upload GobanFTP-1.000.tar.gz', 'pause-upload'],
        ['twine upload dist/*', 'twine upload'],
        ['python -m twine upload dist/*', 'python -m twine upload'],
        ['python3.11 -m twine upload dist/*', 'python -m twine upload'],
        ['npm publish', 'npm publish'],
        ['pnpm publish', 'pnpm publish'],
        ['yarn publish', 'yarn publish'],
        ['docker push ghcr.io/example/gobanftp:latest', 'docker push'],
        ['firebase deploy --only hosting', 'firebase deploy'],
        ['wrangler pages deploy public', 'wrangler pages deploy'],
        ['npx wrangler pages deploy public', 'wrangler pages deploy'],
        ['curl -T artifact.tar.gz ftp://example.invalid/artifact.tar.gz', 'curl upload'],
        ['curl --upload-file artifact.tar.gz https://example.invalid/artifact.tar.gz', 'curl upload'],
        ['scp artifact.tar.gz example.invalid:/tmp/', 'scp'],
        ['rsync -a dist/ example.invalid:/srv/dist/', 'rsync'],
        ['rclone copy dist remote:bucket', 'rclone'],
        ['aws s3 cp artifact.tar.gz s3://example-bucket/artifact.tar.gz', 'aws s3'],
        ['gsutil cp artifact.tar.gz gs://example-bucket/artifact.tar.gz', 'gsutil'],
        ['upload artifact.tar.gz', 'upload'],
        ['deploy production', 'deploy'],
        ["bash -lc 'upload artifact.tar.gz'", 'upload'],
        ["bash -lc 'deploy production'", 'deploy'],
        ['npx vercel deploy', 'vercel deploy'],
    ) {
        my ($line, $kind) = @$case;
        my @hits = _forbidden_command_hits($line);
        is scalar(@hits), 1, "$line is flagged once";
        like $hits[0] // '', qr/\Q$kind\E/, "$line is flagged as $kind";
    }

    for my $line (
        'must not tag, push, upload, deploy',
        'not P1 fixture-local beta evidence',
        'no_tag_push_upload_deploy=1',
        'recommended_checks=prove -lr t/ci-source-release-gate.t',
        q{echo "git push; make dist"},
        'The release gate mentions gh release create, docker push, and make dist as forbidden examples.',
        'Build docs mention `make dist`, `make disttest`, and `make distcheck` inline.',
        'perl -Ilib script/gobanftp publish-move g1.id-demo.s9.r-chinese-area-v1.k7500.pb-alice.pw-bob aa',
        'publish-move and publish-auth are GobanFTP protocol terms, not package publish commands',
        'The phrase curl -T/--upload-file is documentation prose.',
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

subtest 'documentation guard scans current README/docs with historical block exemptions' => sub {
    my @docs = _current_source_doc_paths();
    my %guarded_doc = map { $_ => 1 } @docs;

    for my $rel (
        qw(
            README.md
            README.zh-CN.md
            README.ja.md
            docs/BUILD.md
            docs/P14_RELEASE_GATE.md
            docs/P14_RELEASE_MANIFEST_AND_TAG_PLAN.md
            docs/V1_DOD.md
        )
    ) {
        ok $guarded_doc{$rel}, "$rel is included in the current documentation scan";
    }

    for my $spec (_historical_release_command_block_specs()) {
        my ($rel, $heading) = @$spec;
        my $text = _read_text(File::Spec->catfile($repo_root, $rel));
        my $block = _historical_release_command_block($rel, $heading, $text);
        ok scalar(_forbidden_command_hits($block)) > 0,
            "$rel $heading exemption covers an executable historical release command block";
    }

    for my $rel (@docs) {
        my $text = _read_text(File::Spec->catfile($repo_root, $rel));
        $text = _without_historical_release_command_blocks($rel, $text);
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

    my $gh = _gh_release_kind($command);
    return $gh if defined $gh;

    my $make = _make_dist_kind($command);
    return $make if defined $make;

    my $publish_upload_deploy = _publish_upload_deploy_kind($command);
    return $publish_upload_deploy if defined $publish_upload_deploy;

    my @tokens = _command_tokens($command);
    return 'upload' if @tokens && lc($tokens[0]) eq 'upload';
    return 'deploy' if @tokens && lc($tokens[0]) eq 'deploy';

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

sub _gh_release_kind {
    my ($command) = @_;

    my @tokens = _command_tokens($command);
    return if !@tokens || $tokens[0] ne 'gh';
    shift @tokens;

    while (@tokens) {
        my $token = $tokens[0];
        if ($token eq '-R' || $token eq '--repo'
            || $token eq '--hostname' || $token eq '--config') {
            shift @tokens;
            shift @tokens if @tokens;
            next;
        }
        if ($token =~ /\A--(?:repo|hostname|config)=/) {
            shift @tokens;
            next;
        }
        if ($token =~ /\A-/) {
            shift @tokens;
            next;
        }
        last;
    }

    return if @tokens < 2 || $tokens[0] ne 'release';
    return "gh release $tokens[1]" if $tokens[1] =~ /\A(?:create|upload)\z/;
    return;
}

sub _publish_upload_deploy_kind {
    my ($command) = @_;

    my @tokens = _command_tokens($command);
    return if !@tokens;

    return 'cpan-upload' if $tokens[0] eq 'cpan-upload';
    return 'pause-upload' if $tokens[0] eq 'pause-upload';

    return 'twine upload'
        if @tokens >= 2 && $tokens[0] eq 'twine' && $tokens[1] eq 'upload';
    return 'python -m twine upload'
        if _python_twine_upload(@tokens);

    if (@tokens >= 2 && $tokens[0] =~ /\A(?:npm|pnpm|yarn)\z/) {
        my @rest = @tokens[1 .. $#tokens];
        _drop_leading_cli_options(\@rest, qr/\A(?:--registry|--tag|--otp|--scope|--cwd|-C)\z/);
        return "$tokens[0] publish" if @rest && $rest[0] eq 'publish';
    }

    my @runner_tokens = _npx_unwrapped_tokens(@tokens);

    return 'docker push' if _subcommand_after_options(\@tokens, 'docker') eq 'push';
    return 'firebase deploy'
        if _subcommand_after_options(\@runner_tokens, 'firebase') eq 'deploy';
    return 'vercel deploy'
        if _subcommand_after_options(\@runner_tokens, 'vercel') eq 'deploy';
    return 'netlify deploy'
        if _subcommand_after_options(\@runner_tokens, 'netlify') eq 'deploy';
    return 'wrangler pages deploy'
        if @runner_tokens >= 3
            && $runner_tokens[0] eq 'wrangler'
            && $runner_tokens[1] eq 'pages'
            && $runner_tokens[2] eq 'deploy';
    return 'wrangler deploy'
        if _subcommand_after_options(\@runner_tokens, 'wrangler') eq 'deploy';

    return 'curl upload' if _curl_upload(@tokens);

    return 'scp' if $tokens[0] eq 'scp';
    return 'rsync' if $tokens[0] eq 'rsync';
    return 'rclone'
        if @tokens >= 2
            && $tokens[0] eq 'rclone'
            && $tokens[1] =~ /\A(?:copy|copyto|sync|move|moveto)\z/;
    return 'aws s3'
        if @tokens >= 3
            && $tokens[0] eq 'aws'
            && $tokens[1] eq 's3'
            && $tokens[2] =~ /\A(?:cp|sync|mv|rm)\z/;
    return 'gsutil'
        if @tokens >= 2
            && $tokens[0] eq 'gsutil'
            && $tokens[1] =~ /\A(?:cp|rsync|mv|rm)\z/;

    return;
}

sub _python_twine_upload {
    my (@tokens) = @_;

    return if @tokens < 4 || $tokens[0] !~ /\Apython(?:[0-9]+(?:[.][0-9]+)?)?\z/;
    for (my $i = 1; $i < @tokens - 2; $i++) {
        return 1 if $tokens[$i] eq '-m'
            && $tokens[$i + 1] eq 'twine'
            && $tokens[$i + 2] eq 'upload';
    }
    return;
}

sub _npx_unwrapped_tokens {
    my (@tokens) = @_;

    return @tokens if !@tokens || $tokens[0] ne 'npx';
    shift @tokens;
    _drop_leading_cli_options(\@tokens, qr/\A(?:--package|-p)\z/);
    return @tokens;
}

sub _subcommand_after_options {
    my ($tokens, $command_name) = @_;

    my @tokens = @$tokens;
    return '' if !@tokens || $tokens[0] ne $command_name;
    shift @tokens;
    _drop_leading_cli_options(\@tokens, qr/\A(?:--context|--config|--project|--cwd|-c|-C)\z/);
    return $tokens[0] // '';
}

sub _drop_leading_cli_options {
    my ($tokens, $takes_value) = @_;

    while (@$tokens) {
        my $token = $tokens->[0];
        if ($token =~ /\A--[^=]+\z/ && $token =~ $takes_value) {
            shift @$tokens;
            shift @$tokens if @$tokens;
            next;
        }
        if ($token =~ /\A-[A-Za-z]\z/ && $token =~ $takes_value) {
            shift @$tokens;
            shift @$tokens if @$tokens;
            next;
        }
        if ($token =~ /\A--/) {
            shift @$tokens;
            next;
        }
        if ($token =~ /\A-[A-Za-z]+\z/) {
            shift @$tokens;
            next;
        }
        last;
    }
}

sub _curl_upload {
    my (@tokens) = @_;

    return if !@tokens || $tokens[0] ne 'curl';
    for (my $i = 1; $i < @tokens; $i++) {
        my $token = $tokens[$i];
        return 1 if $token eq '-T' || $token eq '--upload-file';
        return 1 if $token =~ /\A-T\S/ || $token =~ /\A--upload-file=/;
    }
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

    my %forbidden_target = map { $_ => 1 } qw(dist disttest distcheck tardist zipdist);
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

        return "make $token" if $forbidden_target{$token};
        shift @tokens;
    }

    return;
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

sub _current_source_doc_paths {
    my @entries = _manifest_entries();

    return grep {
        /\AREADME(?:[.][^\/]+)?[.]md\z/ || /\Adocs\/.*[.]md\z/
    } @entries;
}

sub _historical_release_command_block_specs {
    return (
        [ 'docs/P14_RELEASE_GATE.md', '## Final Source Gates' ],
        [ 'docs/P14_RELEASE_MANIFEST_AND_TAG_PLAN.md', '## Release Matrix' ],
        [ 'docs/P14_RELEASE_MANIFEST_AND_TAG_PLAN.md', '## Tag Procedure' ],
        [ 'docs/V1_DOD.md', '## Release Gates' ],
    );
}

sub _without_historical_release_command_blocks {
    my ($rel, $text) = @_;

    my @lines = split /\n/, $text // '', -1;
    for my $spec (_historical_release_command_block_specs()) {
        my ($spec_rel, $heading) = @$spec;
        next if $spec_rel ne $rel;

        my ($start, $end) = _historical_release_command_block_span($rel, $heading, @lines);
        for my $i ($start .. $end) {
            $lines[$i] = '';
        }
    }

    return join "\n", @lines;
}

sub _historical_release_command_block {
    my ($rel, $heading, $text) = @_;

    my @lines = split /\n/, $text // '', -1;
    my ($start, $end) = _historical_release_command_block_span($rel, $heading, @lines);
    return join "\n", @lines[$start .. $end];
}

sub _historical_release_command_block_span {
    my ($rel, $heading, @lines) = @_;

    my $saw_heading = 0;
    my $start;
    for (my $i = 0; $i < @lines; $i++) {
        my $line = $lines[$i];
        if (!$saw_heading) {
            $saw_heading = 1 if $line eq $heading;
            next;
        }

        die "no ```sh block before next heading for $rel $heading"
            if !defined($start) && $line =~ /\A##\s+/;
        if (!defined($start) && $line =~ /\A```sh\s*\z/) {
            $start = $i;
            next;
        }
        if (defined($start) && $line =~ /\A```\s*\z/) {
            return ($start, $i);
        }
    }

    die "missing historical release command block for $rel $heading";
}

sub _manifest_entries {
    my $manifest = _read_text(File::Spec->catfile($repo_root, 'MANIFEST'));
    my @entries;
    for my $line (split /\n/, $manifest) {
        next if $line =~ /\A\s*\z/;
        my ($entry) = split /\s+/, $line, 2;
        push @entries, $entry;
    }
    return @entries;
}

sub _read_text {
    my ($path) = @_;

    open my $fh, '<:encoding(UTF-8)', $path or die "open $path: $!";
    local $/;
    my $text = <$fh>;
    close $fh or die "close $path: $!";
    return $text // '';
}
