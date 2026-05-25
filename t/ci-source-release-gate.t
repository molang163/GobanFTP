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
        ['true & git push', 'git push'],
        ["bash -lc 'true & git push'", 'git push'],
        ['( git push )', 'git push'],
        ["bash -lc '( git push )'", 'git push'],
        ['{ git push; }', 'git push'],
        ["bash -lc '{ git push; }'", 'git push'],
        [q{case "$target" in prod) git push ;; esac}, 'git push'],
        [q{case "$target" in prod|staging) git push ;; esac}, 'git push'],
        [q{case "$target" in dev) true ;; prod) git push ;; esac}, 'git push'],
        [q{bash -lc 'case "$target" in prod) git push ;; esac'}, 'git push'],
        ['prod) git push ;;', 'git push'],
        ['printf ok | git push', 'git push'],
        ["bash -lc 'printf ok | git push'", 'git push'],
        ['if true; then git push; fi', 'git push'],
        ["bash -lc 'if true; then git push; fi'", 'git push'],
        ['if git push; then true; fi', 'git push'],
        ['! git push', 'git push'],
        ['run: git -C . push', 'git push'],
        [q{run: 'git push'}, 'git push'],
        [qq{run: "git push"}, 'git push'],
        ["run: >-\n  git\n  push", 'git push'],
        ["run: >+\n  git\n  push", 'git push'],
        ["run: >2\n  git\n  push", 'git push'],
        ["run: >\n  echo ok\n\n  git push", 'git push'],
        ["run: >\n  echo ok\n    git push", 'git push'],
        ["run: |\n  git \\\n    push", 'git push'],
        ["run: |+\n  git push", 'git push'],
        ["run: |2\n    git push", 'git push'],
        ['artifact=$(git push)', 'git push'],
        ['export artifact=$(git push)', 'git push'],
        ['env artifact=$(git push) true', 'git push'],
        [q{echo "$(git push)"}, 'git push'],
        [q{echo `git push`}, 'git push'],
        [q{echo "$(echo $(git push))"}, 'git push'],
        [q{tar -czf artifact.tgz "$(git push)"}, 'git push'],
        [q{custom-tool --target=$(git push)}, 'git push'],
        [q{prove -l t `git push`}, 'git push'],
        ['gh release create v1.1.0-beta.1 artifact.tar.gz', 'gh release create'],
        ['gh release upload artifact.tar.gz', 'gh release upload'],
        ['cpan-upload GobanFTP-1.000.tar.gz', 'cpan-upload'],
        ['pause-upload GobanFTP-1.000.tar.gz', 'pause-upload'],
        ['twine upload dist/*', 'twine upload'],
        ['python -m twine upload dist/*', 'python -m twine upload'],
        ['python3.11 -m twine upload dist/*', 'python -m twine upload'],
        ['npm publish', 'npm publish'],
        ['npm --registry https://registry.example.invalid publish', 'npm publish'],
        ['npm --workspace pkg publish', 'npm publish'],
        ['npm --workspace=pkg publish', 'npm publish'],
        ['npm -w pkg publish', 'npm publish'],
        ['pnpm publish', 'pnpm publish'],
        ['yarn publish', 'yarn publish'],
        ['docker push ghcr.io/example/gobanftp:latest', 'docker push'],
        ['docker --log-level debug push ghcr.io/example/gobanftp:latest', 'docker push'],
        ['docker image push ghcr.io/example/gobanftp:latest', 'docker image push'],
        ['docker buildx build --push .', 'docker buildx build --push'],
        ['docker buildx build --output=type=registry .', 'docker buildx build --output=type=registry'],
        ['docker buildx build --output type=registry .', 'docker buildx build --output=type=registry'],
        ['firebase deploy --only hosting', 'firebase deploy'],
        ['wrangler pages deploy public', 'wrangler pages deploy'],
        ['npx wrangler pages deploy public', 'wrangler pages deploy'],
        ['npx --yes -- wrangler pages deploy public', 'wrangler pages deploy'],
        ['npx wrangler@latest pages deploy public', 'wrangler pages deploy'],
        ['pnpm dlx wrangler pages deploy public', 'wrangler pages deploy'],
        ['pnpm dlx wrangler@latest pages deploy public', 'wrangler pages deploy'],
        ['npm exec -- wrangler pages deploy public', 'wrangler pages deploy'],
        ['npm exec -- wrangler@latest pages deploy public', 'wrangler pages deploy'],
        ['wrangler --config wrangler.toml pages deploy public', 'wrangler pages deploy'],
        ['wrangler --config=wrangler.toml pages deploy public', 'wrangler pages deploy'],
        ['curl -T artifact.tar.gz ftp://example.invalid/artifact.tar.gz', 'curl upload'],
        ['curl --upload-file artifact.tar.gz https://example.invalid/artifact.tar.gz', 'curl upload'],
        ['curl -X PUT https://example.invalid/artifact.tar.gz', 'curl upload'],
        ['curl -XPUT https://example.invalid/artifact.tar.gz', 'curl upload'],
        ['curl --request PUT https://example.invalid/artifact.tar.gz', 'curl upload'],
        ['scp artifact.tar.gz example.invalid:/tmp/', 'scp'],
        ['rsync -a dist/ example.invalid:/srv/dist/', 'rsync'],
        ['rclone copy dist remote:bucket', 'rclone'],
        ['aws s3 cp artifact.tar.gz s3://example-bucket/artifact.tar.gz', 'aws s3'],
        ['aws --profile prod s3 cp artifact.tar.gz s3://example-bucket/artifact.tar.gz', 'aws s3'],
        ['aws --profile=prod s3 sync dist/ s3://example-bucket/dist/', 'aws s3'],
        ['gsutil cp artifact.tar.gz gs://example-bucket/artifact.tar.gz', 'gsutil'],
        ['gsutil -m cp artifact.tar.gz gs://example-bucket/artifact.tar.gz', 'gsutil'],
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
        'npm --script-shell publish test',
        'npx --yes echo wrangler pages deploy',
        'aws --profile prod configure list',
        'gsutil -m ls',
        'printf ok | cat',
        "run: >\n  git\n\n  push",
        "run: >2\n    git\n    push",
        q{echo '$(git push)'},
        q{echo "\$(git push)"},
        q{echo \`git push\`},
        q{VALUE='$(git push)' echo ok},
        q{custom-tool '$(git push)'},
        q{custom-tool "\$(git push)"},
        q{custom-tool \`git push\`},
        'docker image ls',
        'docker buildx build --output=type=local,dest=dist .',
        'curl -X GET https://example.invalid/artifact.tar.gz',
        'pnpm dlx echo wrangler pages deploy',
        'pnpm dlx echo wrangler@latest pages deploy',
        'npm exec -- echo wrangler pages deploy',
        'npm exec -- echo wrangler@latest pages deploy',
        q{echo "true & git push"},
        q{echo "( git push )"},
        q{echo "{ git push; }"},
        'array=(git push)',
        'This prose mentions git push but is not a command.',
        'README prose says $(git push) is a forbidden example.',
        'README prose says `git push` is a forbidden example.',
    ) {
        is_deeply [_forbidden_command_hits($line)], [], "$line is not treated as a command";
    }
};

subtest 'live store scanner covers workflow YAML and run commands only' => sub {
    for my $case (
        ["env:\n  GOBANFTP_STORE: ftp\n", 'GOBANFTP_STORE=ftp'],
        ["env:\n  GOBANFTP_STORE: 'webdav'\n", 'GOBANFTP_STORE=webdav'],
        ["env:\n  GOBANFTP_STORE: \"git-tree\"\n", 'GOBANFTP_STORE=git-tree'],
        ["env:\n  GOBANFTP_STORE: \${{ matrix.store }}\n", 'GOBANFTP_STORE=dynamic'],
        ["env: { GOBANFTP_STORE: ftp }\n", 'GOBANFTP_STORE=ftp'],
        ["env: { OTHER: ok, GOBANFTP_STORE: 'webdav' }\n", 'GOBANFTP_STORE=webdav'],
        ["env: { \"GOBANFTP_STORE\": \"git-tree\" }\n", 'GOBANFTP_STORE=git-tree'],
        ["env: { OTHER: ok, GOBANFTP_STORE: \${{ matrix.store }} }\n", 'GOBANFTP_STORE=dynamic'],
        ["env:\n  GOBANFTP_FTP_HOST: ftp.example.invalid\n", 'GOBANFTP_FTP_HOST'],
        ["env: { GOBANFTP_FTP_HOST: ftp.example.invalid }\n", 'GOBANFTP_FTP_HOST'],
        ["run: 'export GOBANFTP_STORE=ftp'\n", 'GOBANFTP_STORE=ftp'],
        ["run: env GOBANFTP_STORE=webdav prove -l t\n", 'GOBANFTP_STORE=webdav'],
        ["run: GOBANFTP_STORE=dns-record prove -l t\n", 'GOBANFTP_STORE=dns-record'],
        ["run: echo \"GOBANFTP_STORE=ftp\" >> \$GITHUB_ENV\n", 'GOBANFTP_STORE=ftp'],
        ["run: echo \"GOBANFTP_STORE=\$STORE\" >> \$GITHUB_ENV\n", 'GOBANFTP_STORE=dynamic'],
    ) {
        my ($text, $kind) = @$case;
        my @hits = _live_store_hits($text);
        is scalar(@hits), 1, "$kind is flagged once";
        like $hits[0] // '', qr/\Q$kind\E/, "$kind is treated as a live store blocker";
    }

    for my $text (
        'README prose mentions GOBANFTP_STORE=ftp as documentation.',
        "GOBANFTP_STORE=ftp\n",
        "env:\n  GOBANFTP_STORE: local\n",
        "env: { GOBANFTP_STORE: local }\n",
        "env: { GOBANFTP_RULES_ENGINE: perl }\n",
        "with: { GOBANFTP_STORE: ftp }\n",
        "env:\n  GOBANFTP_RULES_ENGINE: perl\n",
        "run: GOBANFTP_STORE=local prove -l t\n",
        "run: export GOBANFTP_STORE=local\n",
        "run: env GOBANFTP_STORE=local prove -l t\n",
        "run: echo \"GOBANFTP_STORE=ftp\"\n",
        "run: echo \"GOBANFTP_STORE=ftp\" >> ./not-github-env\n",
    ) {
        is_deeply [_live_store_hits($text)], [], "$text has no live store hit";
    }
};

subtest 'CI stays source-only and fixture-local' => sub {
    is_deeply [_forbidden_command_hits($workflow)], [],
        'workflow avoids forbidden release/upload/deploy/dist commands';
    is_deeply [_live_store_hits($workflow)], [],
        'workflow avoids live store modes and substrate credentials/endpoints';
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
        my @hits = _forbidden_command_hits($block);
        ok scalar(@hits) > 0,
            "$rel $heading exemption covers an executable historical release command block";
        is_deeply [_unexpected_historical_release_command_hits($spec, @hits)], [],
            "$rel $heading exemption contains only expected historical release command kinds";
        is_deeply [_missing_historical_release_command_kinds($spec, @hits)], [],
            "$rel $heading exemption contains every expected historical release command kind";
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
            for my $kind (_forbidden_command_kinds($segment)) {
                push @hits, "$line_no:$kind:$raw";
            }
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

        if ($raw =~ /\A(\s*)(?:-\s*)?(?:run|command|script):\s*([>|])([+-][1-9]?|[1-9][+-]?|[+-]|[1-9])?\s*(?:#.*)?\z/) {
            my $base_indent = length($1);
            my $style = $2;
            my $indent_indicator = _yaml_block_indent_indicator($3);
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

            push @entries, _yaml_block_command_entries(
                $style,
                $base_indent,
                $indent_indicator,
                \@block,
            );

            $i = $j - 1;
            next;
        }

        push @entries, [ $i + 1, $raw ];
    }

    return _join_shell_continuations(@entries);
}

sub _live_store_hits {
    my ($text) = @_;

    my @hits = _live_store_yaml_env_hits($text);
    for my $entry (_yaml_run_command_entries($text)) {
        my ($line_no, $raw) = @$entry;
        for my $segment (_command_segments($raw)) {
            for my $kind (_live_store_command_kinds($segment)) {
                push @hits, "$line_no:$kind:$raw";
            }
        }
    }

    return @hits;
}

sub _yaml_run_command_entries {
    my ($text) = @_;

    my @raw_lines = split /\n/, $text // '';
    my @entries;

    for (my $i = 0; $i < @raw_lines; $i++) {
        my $raw = $raw_lines[$i];

        if ($raw =~ /\A(\s*)(?:-\s*)?(?:run|command|script):\s*([>|])([+-][1-9]?|[1-9][+-]?|[+-]|[1-9])?\s*(?:#.*)?\z/) {
            my $base_indent = length($1);
            my $style = $2;
            my $indent_indicator = _yaml_block_indent_indicator($3);
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

            push @entries, _yaml_block_command_entries(
                $style,
                $base_indent,
                $indent_indicator,
                \@block,
            );

            $i = $j - 1;
            next;
        }

        if ($raw =~ /\A\s*(?:-\s*)?(?:run|command|script):\s*\S/) {
            push @entries, [ $i + 1, $raw ];
        }
    }

    return _join_shell_continuations(@entries);
}

sub _yaml_block_command_entries {
    my ($style, $base_indent, $indent_indicator, $block) = @_;

    my $content_indent = _yaml_block_content_indent($base_indent, $indent_indicator, $block);
    return _folded_yaml_command_entries($content_indent, $block) if $style eq '>';

    my @entries;
    for my $part (@$block) {
        my $line = _yaml_block_content_line($part->[1], $content_indent);
        push @entries, [ $part->[0], $line ] if $line =~ /\S/;
    }

    return @entries;
}

sub _folded_yaml_command_entries {
    my ($content_indent, $block) = @_;

    my @entries;
    my @paragraph;
    my $paragraph_start;
    for my $part (@$block, [ undef, '' ]) {
        my ($line_no, $raw) = @$part;
        if (defined($line_no) && $raw =~ /\S/) {
            my $line = _yaml_block_content_line($raw, $content_indent);
            $line =~ s/\s+\z//;

            if (_yaml_line_indent($raw) > $content_indent) {
                _flush_folded_yaml_command_paragraph(\@entries, \@paragraph, \$paragraph_start);
                push @entries, [ $line_no, $line ] if $line =~ /\S/;
                next;
            }

            $line =~ s/\A\s+//;
            $paragraph_start //= $line_no;
            push @paragraph, $line;
            next;
        }

        _flush_folded_yaml_command_paragraph(\@entries, \@paragraph, \$paragraph_start);
    }

    return @entries;
}

sub _flush_folded_yaml_command_paragraph {
    my ($entries, $paragraph, $paragraph_start) = @_;

    return if !@$paragraph;
    push @$entries, [ $$paragraph_start, join(' ', @$paragraph) ];
    @$paragraph = ();
    $$paragraph_start = undef;
}

sub _yaml_block_content_indent {
    my ($base_indent, $indent_indicator, $block) = @_;

    return $base_indent + $indent_indicator if defined $indent_indicator;

    my $content_indent;
    for my $part (@$block) {
        my $line = $part->[1];
        next if $line !~ /\S/;
        my $indent = _yaml_line_indent($line);
        next if $indent <= $base_indent;
        $content_indent = $indent if !defined($content_indent) || $indent < $content_indent;
    }

    return $content_indent // ($base_indent + 1);
}

sub _yaml_block_content_line {
    my ($line, $content_indent) = @_;

    $line //= '';
    $line =~ s/\A {0,$content_indent}//;
    return $line;
}

sub _yaml_block_indent_indicator {
    my ($modifiers) = @_;

    return if !defined $modifiers;
    return $1 + 0 if $modifiers =~ /([1-9])/;
    return;
}

sub _yaml_line_indent {
    my ($line) = @_;

    my ($indent) = ($line // '') =~ /\A( *)/;
    return length($indent // '');
}

sub _live_store_yaml_env_hits {
    my ($text) = @_;

    my @hits;
    my @raw_lines = split /\n/, $text // '';
    my $env_indent;

    for (my $i = 0; $i < @raw_lines; $i++) {
        my $raw = $raw_lines[$i];

        if (defined $env_indent && $raw =~ /\S/) {
            my ($indent) = $raw =~ /\A(\s*)/;
            undef $env_indent if length($indent) <= $env_indent;
        }

        if (defined $env_indent) {
            my ($name, $value) = _yaml_env_assignment($raw);
            if (defined $name) {
                my $kind = _live_store_assignment_kind($name, _yaml_scalar_value($value));
                push @hits, ($i + 1) . ":$kind:$raw" if defined $kind;
            }
        }

        if (!defined($env_indent)) {
            for my $pair (_yaml_env_flow_map_pairs($raw)) {
                my ($name, $value) = @$pair;
                my $kind = _live_store_assignment_kind($name, _yaml_scalar_value($value));
                push @hits, ($i + 1) . ":$kind:$raw" if defined $kind;
            }
        }

        if (!defined($env_indent) && $raw =~ /\A(\s*)(?:-\s*)?env:\s*(?:#.*)?\z/) {
            $env_indent = length($1);
        }
    }

    return @hits;
}

sub _yaml_env_flow_map_pairs {
    my ($line) = @_;

    return if ($line // '') !~ /\A\s*(?:-\s*)?env:\s*(\{.*\})\s*(?:#.*)?\z/s;
    return _yaml_flow_map_pairs($1);
}

sub _yaml_flow_map_pairs {
    my ($map) = @_;

    $map //= '';
    $map =~ s/\A\s+|\s+\z//g;
    return if $map !~ /\A\{(.*)\}\z/s;

    my @pairs;
    for my $item (_split_yaml_flow_top_level($1, ',')) {
        $item =~ s/\A\s+|\s+\z//g;
        next if $item eq '';
        my ($key, $value) = _split_yaml_flow_top_level($item, ':', 2);
        next if !defined $value;
        my $name = _yaml_scalar_value($key);
        push @pairs, [ $name, $value ] if defined $name;
    }

    return @pairs;
}

sub _split_yaml_flow_top_level {
    my ($text, $separator, $limit) = @_;

    my @parts;
    my $buffer = '';
    my $quote = '';
    my $escape = 0;
    my $depth = 0;
    my @chars = split //, $text // '';

    for my $char (@chars) {
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
        if ($char eq '{' || $char eq '[') {
            $depth++;
            $buffer .= $char;
            next;
        }
        if ($char eq '}' || $char eq ']') {
            $depth-- if $depth > 0;
            $buffer .= $char;
            next;
        }
        if ($char eq $separator && $depth == 0 && (!defined($limit) || @parts < $limit - 1)) {
            push @parts, $buffer;
            $buffer = '';
            next;
        }

        $buffer .= $char;
    }

    push @parts, $buffer;
    return @parts;
}

sub _yaml_env_assignment {
    my ($line) = @_;

    return if ($line // '') !~ /\S/;
    return if $line =~ /\A\s*#/;
    return if $line !~ /\A\s*(?:"([^"]+)"|'([^']+)'|([A-Za-z_][A-Za-z0-9_]*))\s*:\s*(.*?)\s*\z/;
    my $name = $1 // $2 // $3;
    return ($name, $4);
}

sub _yaml_scalar_value {
    my ($value) = @_;

    $value //= '';
    $value =~ s/\s+#.*\z//;
    $value =~ s/\A\s+|\s+\z//g;
    return undef if $value eq '';
    return _unwrap_quoted_scalar($value);
}

sub _live_store_command_kinds {
    my ($segment) = @_;

    my $command = _strip_live_command_prefixes($segment);
    my @tokens = _command_tokens($command);
    return if !@tokens;

    my @kinds;
    my $command_index = 0;
    while ($command_index < @tokens) {
        my ($name, $value) = _shell_assignment($tokens[$command_index]);
        last if !defined $name;
        my $kind = _live_store_assignment_kind($name, $value);
        push @kinds, $kind if defined $kind;
        $command_index++;
    }

    if ($command_index < @tokens && $tokens[$command_index] eq 'export') {
        push @kinds, _live_store_export_kinds(@tokens[($command_index + 1) .. $#tokens]);
    }
    elsif ($command_index < @tokens && $tokens[$command_index] eq 'env') {
        push @kinds, _live_store_env_command_kinds(@tokens[($command_index + 1) .. $#tokens]);
    }
    elsif ($command_index < @tokens && $tokens[$command_index] =~ /\A(?:echo|printf)\z/) {
        push @kinds, _live_store_github_env_kinds(@tokens[$command_index .. $#tokens]);
    }

    return _unique_strings(@kinds);
}

sub _strip_live_command_prefixes {
    my ($segment) = @_;

    my $command = $segment // '';
    $command =~ s/\A\s+|\s+\z//g;
    $command = _strip_leading_compound_shell($command);
    $command = _case_pattern_command($command);
    $command = _case_arm_pattern_command($command) // $command;
    while ($command =~ s/\A(?:command|builtin|!|if|then|elif|else|while|until|do|time)\s+//) {
        next;
    }
    $command =~ s/\A\s+|\s+\z//g;
    return $command;
}

sub _live_store_export_kinds {
    my (@tokens) = @_;

    my @kinds;
    while (@tokens) {
        my $token = shift @tokens;
        next if $token =~ /\A-[A-Za-z]+\z/;

        my ($name, $value) = _shell_assignment($token);
        if (defined $name) {
            my $kind = _live_store_assignment_kind($name, $value);
            push @kinds, $kind if defined $kind;
            next;
        }
        if ($token =~ /\AGOBANFTP_(?:STORE|(?:FTP|WEBDAV|DNS|GIT)_)/) {
            my $kind = _live_store_assignment_kind($token, undef);
            push @kinds, $kind if defined $kind;
        }
    }

    return @kinds;
}

sub _live_store_env_command_kinds {
    my (@tokens) = @_;

    my @kinds;
    while (@tokens) {
        my $token = $tokens[0];
        if ($token eq '-i' || $token eq '--ignore-environment') {
            shift @tokens;
            next;
        }
        if ($token eq '-u' || $token eq '--unset' || $token eq '-C' || $token eq '--chdir') {
            shift @tokens;
            shift @tokens if @tokens;
            next;
        }
        if ($token =~ /\A--(?:unset|chdir)=/) {
            shift @tokens;
            next;
        }
        if ($token eq '--') {
            shift @tokens;
            next;
        }

        my ($name, $value) = _shell_assignment($token);
        last if !defined $name;
        my $kind = _live_store_assignment_kind($name, $value);
        push @kinds, $kind if defined $kind;
        shift @tokens;
    }

    return @kinds;
}

sub _live_store_github_env_kinds {
    my (@tokens) = @_;

    return if !_writes_github_env(@tokens);

    my @kinds;
    for my $token (@tokens[1 .. $#tokens]) {
        last if _is_redirect_token($token);
        my ($name, $value) = _shell_assignment($token);
        next if !defined $name;
        $value =~ s/\\n\z// if defined $value;
        my $kind = _live_store_assignment_kind($name, $value);
        push @kinds, $kind if defined $kind;
    }

    return @kinds;
}

sub _writes_github_env {
    my (@tokens) = @_;

    for (my $i = 0; $i < @tokens; $i++) {
        my $token = $tokens[$i];
        if ($token =~ /\A(?:[0-9]?>>|[0-9]?>)(.+)\z/) {
            return 1 if _is_github_env_target($1);
        }
        if (_is_redirect_token($token) && defined($tokens[$i + 1])) {
            return 1 if _is_github_env_target($tokens[$i + 1]);
        }
    }

    return;
}

sub _is_redirect_token {
    my ($token) = @_;

    return ($token // '') =~ /\A(?:[0-9]?>>|[0-9]?>)\z/ ? 1 : 0;
}

sub _is_github_env_target {
    my ($token) = @_;

    return ($token // '') =~ /\A(?:\$GITHUB_ENV|\$\{GITHUB_ENV\})\z/ ? 1 : 0;
}

sub _shell_assignment {
    my ($token) = @_;

    return if ($token // '') !~ /\A([A-Za-z_][A-Za-z0-9_]*)=(.*)\z/s;
    return ($1, $2);
}

sub _live_store_assignment_kind {
    my ($name, $value) = @_;

    return if !defined $name;
    if ($name eq 'GOBANFTP_STORE') {
        return 'GOBANFTP_STORE=dynamic' if _dynamic_shell_value($value);
        my $mode = lc($value // '');
        return if $mode eq 'local';
        return "GOBANFTP_STORE=$mode";
    }
    return $name if $name =~ /\AGOBANFTP_(?:FTP|WEBDAV|DNS|GIT)_/;
    return;
}

sub _dynamic_shell_value {
    my ($value) = @_;

    return 1 if !defined($value) || $value eq '';
    return 1 if $value =~ /(?:\$\(|`|\$\{?|\$\{\{)/;
    return;
}

sub _unique_strings {
    my (@values) = @_;

    my %seen;
    return grep { !$seen{$_}++ } grep { defined } @values;
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

    my @case_commands = _case_branch_commands($line);
    return map { _shell_segments($_) } @case_commands if @case_commands;

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
        if ($char eq '|' && _inside_case_pattern($buffer)) {
            $buffer .= $char;
            next;
        }
        if (($char eq '&' || $char eq '|') && (($chars[$i + 1] // '') eq $char)) {
            _push_shell_segment(\@segments, $buffer);
            $buffer = '';
            $i++;
            next;
        }
        if ($char eq '&') {
            my $previous = $chars[$i - 1] // '';
            my $next = $chars[$i + 1] // '';
            if ($previous eq '>' || $previous eq '<' || $next eq '>') {
                $buffer .= $char;
                next;
            }
            _push_shell_segment(\@segments, $buffer);
            $buffer = '';
            next;
        }
        if ($char eq '|') {
            _push_shell_segment(\@segments, $buffer);
            $buffer = '';
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

sub _inside_case_pattern {
    my ($buffer) = @_;

    $buffer //= '';
    return $buffer =~ /\A\s*case\b.*?\bin\b\s+[^)]*\z/s ? 1 : 0;
}

sub _case_branch_commands {
    my ($line) = @_;

    return if ($line // '') !~ /\A\s*case\b/s;
    return if $line !~ /\A\s*case\b.*?\bin\b\s*(.*?)\s*\z/s;

    my $body = $1;
    $body =~ s/\s*\besac\s*\z//;

    my @commands;
    for my $arm (_split_case_arms($body)) {
        my $command = _case_arm_pattern_command($arm);
        push @commands, $command if defined($command) && $command ne '';
    }

    return @commands;
}

sub _split_case_arms {
    my ($body) = @_;

    my @arms;
    my $buffer = '';
    my $quote = '';
    my $escape = 0;
    my @chars = split //, $body // '';

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
            my $next = $chars[$i + 1] // '';
            my $after_next = $chars[$i + 2] // '';
            if ($next eq ';' && $after_next eq '&') {
                _push_shell_segment(\@arms, $buffer);
                $buffer = '';
                $i += 2;
                next;
            }
            if ($next eq ';' || $next eq '&') {
                _push_shell_segment(\@arms, $buffer);
                $buffer = '';
                $i++;
                next;
            }
        }

        $buffer .= $char;
    }

    _push_shell_segment(\@arms, $buffer);
    return @arms;
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
        _drop_leading_cli_options(
            \@rest,
            qr/\A(?:--registry|--tag|--otp|--scope|--cwd|--script-shell|--workspace|-C|-w)\z/,
            qr/\A(?:--dry-run|--force|--ignore-scripts|--no-git-checks)\z/,
        );
        return "$tokens[0] publish" if @rest && $rest[0] eq 'publish';
    }

    my @runner_tokens = _node_runner_unwrapped_tokens(@tokens);

    my $docker = _docker_forbidden_kind(@tokens);
    return $docker if defined $docker;
    return 'firebase deploy'
        if _subcommand_after_options(\@runner_tokens, 'firebase') eq 'deploy';
    return 'vercel deploy'
        if _subcommand_after_options(\@runner_tokens, 'vercel') eq 'deploy';
    return 'netlify deploy'
        if _subcommand_after_options(\@runner_tokens, 'netlify') eq 'deploy';
    my @wrangler_tokens = _tokens_after_command_options(
        \@runner_tokens,
        'wrangler',
        qr/\A(?:--config|--cwd|-c|-C)\z/,
        qr/\A(?:--debug|--verbose|--quiet|-v|-q)\z/,
    );
    return 'wrangler pages deploy'
        if @wrangler_tokens >= 2
            && $wrangler_tokens[0] eq 'pages'
            && $wrangler_tokens[1] eq 'deploy';
    return 'wrangler deploy'
        if @wrangler_tokens && $wrangler_tokens[0] eq 'deploy';

    return 'curl upload' if _curl_upload(@tokens);

    return 'scp' if $tokens[0] eq 'scp';
    return 'rsync' if $tokens[0] eq 'rsync';
    return 'rclone'
        if @tokens >= 2
            && $tokens[0] eq 'rclone'
            && $tokens[1] =~ /\A(?:copy|copyto|sync|move|moveto)\z/;
    my @aws_tokens = _tokens_after_command_options(
        \@tokens,
        'aws',
        qr/\A(?:--profile|--region|--endpoint-url|--ca-bundle)\z/,
        qr/\A(?:--debug|--no-paginate|--no-verify-ssl)\z/,
    );
    return 'aws s3'
        if @aws_tokens >= 2
            && $aws_tokens[0] eq 's3'
            && $aws_tokens[1] =~ /\A(?:cp|sync|mv|rm)\z/;
    my @gsutil_tokens = _tokens_after_command_options(
        \@tokens,
        'gsutil',
        qr/\A(?:-h|-o)\z/,
        qr/\A(?:-m|-q|-D)\z/,
    );
    return 'gsutil'
        if @gsutil_tokens
            && $gsutil_tokens[0] =~ /\A(?:cp|rsync|mv|rm)\z/;

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
    _drop_leading_cli_options(
        \@tokens,
        qr/\A(?:--package|-p)\z/,
        qr/\A(?:--yes|-y|--no-install)\z/,
    );
    shift @tokens if @tokens && $tokens[0] eq '--';
    return @tokens;
}

sub _node_runner_unwrapped_tokens {
    my (@tokens) = @_;

    for (1 .. 3) {
        my @unwrapped = _one_node_runner_unwrapped_tokens(@tokens);
        last if join("\0", @unwrapped) eq join("\0", @tokens);
        @tokens = @unwrapped;
    }

    return _node_runner_package_spec_tokens(@tokens);
}

sub _one_node_runner_unwrapped_tokens {
    my (@tokens) = @_;

    return _npx_unwrapped_tokens(@tokens) if @tokens && $tokens[0] eq 'npx';
    return _pnpm_dlx_unwrapped_tokens(@tokens) if @tokens && $tokens[0] eq 'pnpm';
    return _npm_exec_unwrapped_tokens(@tokens) if @tokens && $tokens[0] eq 'npm';
    return @tokens;
}

sub _node_runner_package_spec_tokens {
    my (@tokens) = @_;

    return @tokens if !@tokens;
    if ($tokens[0] =~ /\A((?:\@[^\/\s]+\/)?[A-Za-z0-9_.-]+)\@[^\/\s]+\z/) {
        my $package = $1;
        my ($binary) = $package =~ /([^\/]+)\z/;
        $tokens[0] = $binary if defined $binary;
    }

    return @tokens;
}

sub _pnpm_dlx_unwrapped_tokens {
    my (@tokens) = @_;

    return @tokens if !@tokens || $tokens[0] ne 'pnpm';
    shift @tokens;
    _drop_leading_cli_options(
        \@tokens,
        qr/\A(?:--dir|--store-dir|--package|-C)\z/,
        qr/\A(?:--silent|-s|--offline|--prefer-offline)\z/,
    );
    return ('pnpm', @tokens) if !@tokens || $tokens[0] ne 'dlx';
    shift @tokens;
    _drop_leading_cli_options(
        \@tokens,
        qr/\A(?:--package|-p)\z/,
        qr/\A(?:--shell-mode|-c|--silent|-s)\z/,
    );
    shift @tokens if @tokens && $tokens[0] eq '--';
    return @tokens;
}

sub _npm_exec_unwrapped_tokens {
    my (@tokens) = @_;

    return @tokens if !@tokens || $tokens[0] ne 'npm';
    shift @tokens;
    _drop_leading_cli_options(
        \@tokens,
        qr/\A(?:--registry|--workspace|--prefix|--cache|--userconfig|-w|-C)\z/,
        qr/\A(?:--yes|-y|--ignore-scripts|--silent|-s)\z/,
    );
    return ('npm', @tokens) if !@tokens || $tokens[0] ne 'exec';
    shift @tokens;
    _drop_leading_cli_options(
        \@tokens,
        qr/\A(?:--package|--workspace|-p|-w)\z/,
        qr/\A(?:--yes|-y|--ignore-existing|--silent|-s)\z/,
    );
    shift @tokens if @tokens && $tokens[0] eq '--';
    return @tokens;
}

sub _docker_forbidden_kind {
    my (@tokens) = @_;

    my @docker_tokens = _tokens_after_command_options(
        \@tokens,
        'docker',
        qr/\A(?:--config|--context|--host|--log-level|-H)\z/,
        qr/\A(?:--debug|-D)\z/,
    );
    return if !@docker_tokens;
    return 'docker push' if $docker_tokens[0] eq 'push';

    if ($docker_tokens[0] eq 'image') {
        shift @docker_tokens;
        _drop_leading_cli_options(
            \@docker_tokens,
            qr/\A(?:--format)\z/,
            qr/(?!)/,
        );
        return 'docker image push' if @docker_tokens && $docker_tokens[0] eq 'push';
        return;
    }

    return if $docker_tokens[0] ne 'buildx';
    shift @docker_tokens;
    _drop_leading_cli_options(
        \@docker_tokens,
        qr/\A(?:--builder|-b)\z/,
        qr/\A(?:--debug)\z/,
    );
    return if !@docker_tokens || $docker_tokens[0] ne 'build';
    shift @docker_tokens;

    for (my $i = 0; $i < @docker_tokens; $i++) {
        my $token = $docker_tokens[$i];
        return 'docker buildx build --push'
            if $token eq '--push' || $token =~ /\A--push=(?:1|true)\z/i;
        if (($token eq '--output' || $token eq '-o') && defined($docker_tokens[$i + 1])) {
            return 'docker buildx build --output=type=registry'
                if _docker_output_is_registry($docker_tokens[$i + 1]);
            $i++;
            next;
        }
        if ($token =~ /\A--output=(.+)\z/) {
            return 'docker buildx build --output=type=registry'
                if _docker_output_is_registry($1);
        }
    }

    return;
}

sub _docker_output_is_registry {
    my ($value) = @_;

    return ($value // '') =~ /(?:\A|,)type=registry(?:,|\z)/ ? 1 : 0;
}

sub _subcommand_after_options {
    my ($tokens, $command_name, $takes_value, $value_less) = @_;

    my @tokens = _tokens_after_command_options($tokens, $command_name, $takes_value, $value_less);
    return $tokens[0] // '';
}

sub _tokens_after_command_options {
    my ($tokens, $command_name, $takes_value, $value_less) = @_;

    my @tokens = @$tokens;
    return if !@tokens || $tokens[0] ne $command_name;
    shift @tokens;
    _drop_leading_cli_options(
        \@tokens,
        $takes_value // qr/\A(?:--context|--config|--project|--cwd|-c|-C)\z/,
        $value_less // qr/\A(?:--debug|--verbose|--quiet|-v|-q)\z/,
    );
    shift @tokens if @tokens && $tokens[0] eq '--';
    return @tokens;
}

sub _drop_leading_cli_options {
    my ($tokens, $takes_value, $value_less) = @_;
    $value_less //= qr/(?!)/;

    while (@$tokens) {
        my $token = $tokens->[0];
        if ($token =~ /\A(--[A-Za-z0-9_-]+)=/ && $1 =~ $takes_value) {
            shift @$tokens;
            next;
        }
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
        if ($token =~ /\A--/ && $token =~ $value_less) {
            shift @$tokens;
            next;
        }
        if ($token =~ /\A-[A-Za-z]+\z/ && $token =~ $value_less) {
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
        if (($token eq '-X' || $token eq '--request') && defined($tokens[$i + 1])) {
            return 1 if uc($tokens[$i + 1]) eq 'PUT';
            $i++;
            next;
        }
        return 1 if $token =~ /\A-X(.+)\z/ && uc($1) eq 'PUT';
        return 1 if $token =~ /\A--request=(.+)\z/ && uc($1) eq 'PUT';
    }
    return;
}

sub _strip_command_prefixes {
    my ($segment) = @_;

    my $command = $segment // '';
    $command =~ s/\A\s+|\s+\z//g;
    $command = _strip_leading_compound_shell($command);
    $command = _case_pattern_command($command);
    $command = _case_arm_pattern_command($command) // $command;

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
    while ($command =~ s/\A(?:!|if|then|elif|else|while|until|do|time)\s+//) {
        next;
    }
    while ($command =~ s/\A[A-Za-z_][A-Za-z0-9_]*=(?:"[^"]*"|'[^']*'|\S+)\s+//) {
        next;
    }
    while ($command =~ s/\A(?:command|builtin)\s+// || $command =~ s/\A(?:!|if|then|elif|else|while|until|do|time)\s+//) {
        while ($command =~ s/\A[A-Za-z_][A-Za-z0-9_]*=(?:"[^"]*"|'[^']*'|\S+)\s+//) {
            next;
        }
    }
    $command = _strip_leading_compound_shell($command);
    $command = _case_pattern_command($command);
    $command = _case_arm_pattern_command($command) // $command;
    $command =~ s/\A\s+|\s+\z//g;

    return $command;
}

sub _strip_leading_compound_shell {
    my ($command) = @_;

    $command //= '';
    $command =~ s/\A\s+|\s+\z//g;

    while (1) {
        my $before = $command;
        if ($command =~ s/\A\(\s*//) {
            $command =~ s/\s*\)\z//;
        }
        if ($command =~ s/\A\{\s*//) {
            $command =~ s/\s*\}\z//;
        }
        $command =~ s/\A\s+|\s+\z//g;
        last if $command eq $before;
    }

    return $command;
}

sub _case_pattern_command {
    my ($command) = @_;

    return $command if ($command // '') !~ /\Acase\b/;
    if ($command =~ /\Acase\b.*?\bin\b\s+[^)]*\)\s*(.*?)\s*\z/s) {
        my $after = $1;
        $after =~ s/\s*(?:;;&|;&|;;)\s*esac\s*\z//;
        $after =~ s/\s*\besac\s*\z//;
        $after =~ s/\s*(?:;;&|;&|;;)\s*\z//;
        $after =~ s/\A\s+|\s+\z//g;
        return $after if $after ne '';
    }

    return $command;
}

sub _case_arm_pattern_command {
    my ($command) = @_;

    return if !defined $command;
    $command =~ s/\A\s+|\s+\z//g;
    if ($command =~ /\A[^()\s;]+(?:\|[^()\s;]+)*\)\s*(.*?)\s*\z/s) {
        my $after = $1;
        $after =~ s/\s*(?:;;&|;&|;;)\s*\z//;
        $after =~ s/\A\s+|\s+\z//g;
        return $after if $after ne '';
    }

    return;
}

sub _forbidden_command_kinds {
    my ($segment) = @_;

    my @kinds;
    my $kind = _forbidden_command_kind($segment);
    push @kinds, $kind if defined $kind;
    return @kinds if !_segment_runs_command_substitutions($segment);

    for my $substitution (_command_substitution_texts($segment)) {
        for my $hit (_forbidden_command_hits($substitution)) {
            my ($substitution_kind) = $hit =~ /\A[0-9]+:([^:]+):/;
            push @kinds, $substitution_kind if defined $substitution_kind;
        }
    }

    return @kinds;
}

sub _segment_runs_command_substitutions {
    my ($segment) = @_;

    my $command = _strip_live_command_prefixes($segment);
    return if !_command_substitution_texts($command);
    return if _looks_like_documentation_sentence($command);
    return 1 if $command =~ /\A\s*(?:\$\(|`)/;

    my @tokens = _command_tokens($command);
    return if !@tokens;
    return 1 if $tokens[0] =~ /\A[A-Za-z_][A-Za-z0-9_]*=/;
    return 1 if $tokens[0] =~ /\A(?:export|env|echo|printf|bash|sh|command|builtin)\z/;
    return 1 if _looks_like_simple_shell_command($command, @tokens);
    return;
}

sub _looks_like_simple_shell_command {
    my ($command, @tokens) = @_;

    return if !@tokens;
    return if _looks_like_documentation_sentence($command);

    my $first = $tokens[0] // '';
    return if $first !~ /\A[A-Za-z0-9_.\/+-]+\z/;
    return if $first =~ /\A[[:upper:]]/;
    return if $first =~ /\A(?:a|an|and|are|as|build|but|can|cannot|command|commands|const|do|docs?|documentation|does|dont|don't|example|examples|if|is|line|lines|mention|mentions|mentioned|must|my|no|not|or|our|phrase|prose|readme|release|return|run|says?|should|sub|the|these|this|those|use|using|when|while|workflow|workflows)\z/i;

    return 1;
}

sub _looks_like_documentation_sentence {
    my ($line) = @_;

    $line //= '';
    $line =~ s/\A\s+|\s+\z//g;
    return 1 if $line =~ /\A(?:README|Readme|The|This|These|Those|Build docs|Documentation|Docs|Release gate|Workflow|The phrase)\b/;
    return 1 if $line =~ /\A`[^`]+`\s*(?:,|\b(?:and|is|may|must|or|should|so|then)\b)/i;
    return 1 if $line =~ /`[^`]+`/ && $line =~ /\b(?:archive|build and test|distribution|inside|may|or run|then)\b/i;
    return 1 if $line =~ /\b(?:documentation|forbidden example|forbidden examples|inline|mentions?|phrase|prose)\b/i;
    return 1 if $line =~ /[.!?]\z/ && $line =~ /\b(?:and|are|as|but|is|mentions?|not|or|that|with|without)\b/i;
    return;
}

sub _command_substitution_texts {
    my ($line) = @_;

    my @substitutions;
    my @chars = split //, $line // '';
    my $quote = '';
    my $escape = 0;

    for (my $i = 0; $i < @chars; $i++) {
        my $char = $chars[$i];

        if ($escape) {
            $escape = 0;
            next;
        }
        if ($char eq '\\' && $quote ne q{'}) {
            $escape = 1;
            next;
        }
        if ($quote eq q{'}) {
            $quote = '' if $char eq q{'};
            next;
        }
        if ($quote eq q{"}) {
            if ($char eq q{"}) {
                $quote = '';
                next;
            }
        }
        elsif ($char eq q{'}) {
            $quote = q{'};
            next;
        }
        elsif ($char eq q{"}) {
            $quote = q{"};
            next;
        }

        if ($char eq '$' && (($chars[$i + 1] // '') eq '(')) {
            my ($content, $end) = _extract_dollar_paren_substitution(\@chars, $i);
            if (defined $content) {
                push @substitutions, $content;
                $i = $end;
            }
            next;
        }
        if ($char eq '`') {
            my ($content, $end) = _extract_backtick_substitution(\@chars, $i);
            if (defined $content) {
                push @substitutions, $content;
                $i = $end;
            }
            next;
        }
    }

    return @substitutions;
}

sub _extract_dollar_paren_substitution {
    my ($chars, $start) = @_;

    my @content;
    my $depth = 1;
    my $quote = '';
    my $in_backtick = 0;
    my $escape = 0;

    for (my $i = $start + 2; $i < @$chars; $i++) {
        my $char = $chars->[$i];

        if ($escape) {
            push @content, $char;
            $escape = 0;
            next;
        }
        if ($char eq '\\' && $quote ne q{'}) {
            push @content, $char;
            $escape = 1;
            next;
        }
        if ($in_backtick) {
            $in_backtick = 0 if $char eq '`';
            push @content, $char;
            next;
        }
        if ($quote eq q{'}) {
            $quote = '' if $char eq q{'};
            push @content, $char;
            next;
        }
        if ($quote eq q{"}) {
            if ($char eq q{"}) {
                $quote = '';
                push @content, $char;
                next;
            }
            if ($char eq '$' && (($chars->[$i + 1] // '') eq '(')) {
                push @content, '$', '(';
                $depth++;
                $i++;
                next;
            }
            push @content, $char;
            next;
        }
        if ($char eq q{'}) {
            $quote = q{'};
            push @content, $char;
            next;
        }
        if ($char eq q{"}) {
            $quote = q{"};
            push @content, $char;
            next;
        }
        if ($char eq '`') {
            $in_backtick = 1;
            push @content, $char;
            next;
        }
        if ($char eq '$' && (($chars->[$i + 1] // '') eq '(')) {
            push @content, '$', '(';
            $depth++;
            $i++;
            next;
        }
        if ($char eq '(') {
            $depth++;
            push @content, $char;
            next;
        }
        if ($char eq ')') {
            $depth--;
            return (join('', @content), $i) if $depth == 0;
            push @content, $char;
            next;
        }

        push @content, $char;
    }

    return;
}

sub _extract_backtick_substitution {
    my ($chars, $start) = @_;

    my @content;
    my $escape = 0;
    for (my $i = $start + 1; $i < @$chars; $i++) {
        my $char = $chars->[$i];

        if ($escape) {
            push @content, $char;
            $escape = 0;
            next;
        }
        if ($char eq '\\') {
            push @content, $char;
            $escape = 1;
            next;
        }
        return (join('', @content), $i) if $char eq '`';
        push @content, $char;
    }

    return;
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
        [ 'docs/P14_RELEASE_GATE.md', '## Final Source Gates',
            [ 'make dist', 'make disttest', 'make distcheck' ] ],
        [ 'docs/P14_RELEASE_MANIFEST_AND_TAG_PLAN.md', '## Release Matrix',
            [ 'make dist', 'make disttest', 'make distcheck' ] ],
        [ 'docs/P14_RELEASE_MANIFEST_AND_TAG_PLAN.md', '## Tag Procedure',
            [ 'git tag' ] ],
        [ 'docs/V1_DOD.md', '## Release Gates',
            [ 'make dist', 'make disttest', 'make distcheck' ] ],
    );
}

sub _unexpected_historical_release_command_hits {
    my ($spec, @hits) = @_;

    my %allowed = map { $_ => 1 } @{ $spec->[2] // [] };
    my @unexpected;
    for my $hit (@hits) {
        my ($kind) = $hit =~ /\A[0-9]+:([^:]+):/;
        push @unexpected, $hit if !defined($kind) || !$allowed{$kind};
    }
    return @unexpected;
}

sub _missing_historical_release_command_kinds {
    my ($spec, @hits) = @_;

    my %seen;
    for my $hit (@hits) {
        my ($kind) = $hit =~ /\A[0-9]+:([^:]+):/;
        $seen{$kind} = 1 if defined $kind;
    }

    return grep { !$seen{$_} } @{ $spec->[2] // [] };
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
