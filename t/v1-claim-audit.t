use v5.34;
use strict;
use warnings;
use utf8;

use FindBin;
use File::Spec;
use Test::More;

my $repo_root = File::Spec->rel2abs("$FindBin::Bin/..");

my @user_entry_files = qw(
    Changes
    README.md
    README.zh-CN.md
    README.ja.md
);

my %text = map { $_ => _read_text(File::Spec->catfile($repo_root, split '/', $_)) } (
    @user_entry_files,
    qw(
        docs/CLI.md
        docs/DIAGNOSTICS.md
        docs/ROADMAP.md
        docs/SHOWCASE.md
        docs/V1_1_RELEASE_GATE.md
        docs/V1_1_RELEASE_NOTES.md
        docs/V1_1_AUTH_BOUNDARY.md
        docs/PROFILES.md
        lib/GobanFTP/CLI.pm
        .gitignore
        MANIFEST
        MANIFEST.SKIP
    )
);

subtest 'beta release state stays guarded' => sub {
    like $text{'README.md'}, qr/^Current beta release: `v1[.]1[.]0-beta[.]1\/package 1[.]100_001`[.]$/m,
        'README current beta release is v1.1.0-beta.1/package 1.100_001';
    like $text{'docs/V1_1_RELEASE_GATE.md'},
        qr/^Status: v1[.]1[.]0-beta[.]1 \/ package 1[.]100_001 beta source gate[.]$/m,
        'v1.1 release gate names the beta source gate';
    like $text{'docs/V1_1_RELEASE_NOTES.md'},
        qr/^Status: public beta release notes for v1[.]1[.]0-beta[.]1 \/ package 1[.]100_001[.]$/m,
        'v1.1 release notes name the beta release';
    like $text{Changes}, qr/^1[.]100_001  2026-05-25$/m,
        'Changes records the v1.1.0-beta.1 package heading';
    like $text{'docs/V1_1_RELEASE_GATE.md'},
        qr/not tag, push, upload,\ndeploy/,
        'gate records no tag/push/upload/deploy';
    unlike $text{'docs/V1_1_RELEASE_GATE.md'}, qr/^make dist$/m,
        'gate does not run make dist as an evidence command';
    unlike $text{'docs/V1_1_RELEASE_GATE.md'}, qr/^make disttest$/m,
        'gate does not run make disttest';
    unlike $text{'docs/V1_1_RELEASE_GATE.md'}, qr/^make distcheck$/m,
        'gate does not run make distcheck';
    like $text{'docs/V1_1_RELEASE_GATE.md'}, qr/^gate_env git diff --check$/m,
        'gate includes exact whitespace hygiene evidence under gate_env';
    like $text{'docs/V1_1_RELEASE_GATE.md'}, qr/ExtUtils::Manifest=fullcheck/,
        'gate includes ExtUtils::Manifest::fullcheck evidence';
    like $text{'docs/V1_1_RELEASE_GATE.md'}, qr/git archive --format=tar HEAD/,
        'gate includes committed HEAD archive hygiene evidence';
    like $text{'docs/V1_1_RELEASE_GATE.md'}, qr/disposable worktree copy.*MakeMaker\/shadow/ms,
        'gate records a disposable worktree MakeMaker/shadow evidence path';
    like $text{'docs/V1_1_RELEASE_GATE.md'}, qr/gate_env env -u GOBANFTP_RULES_DISABLE_C .*GOBANFTP_RULES_ENGINE=shadow make test/s,
        'gate unsets C-disable flag before shadow MakeMaker evidence';
    like $text{'docs/V1_1_RELEASE_GATE.md'}, qr/gate_env\(\).*GOBANFTP_FTP_TEST.*GOBANFTP_WEBDAV_URL.*GOBANFTP_DNS_RECORD_FILE.*GOBANFTP_GIT_REPO/ms,
        'gate_env unsets live-provider environment';
};

subtest 'release gate separates worktree and committed HEAD evidence' => sub {
    my $gate = $text{'docs/V1_1_RELEASE_GATE.md'};
    my ($worktree) = $gate =~ /^### Uncommitted Worktree Candidate\n(.*?)(?=^### Committed HEAD Candidate\n)/ms;
    my ($head) = $gate =~ /^### Committed HEAD Candidate\n(.*?)(?=^## |\z)/ms;

    ok defined($worktree), 'gate has an uncommitted worktree candidate section';
    ok defined($head),     'gate has a committed HEAD candidate section';
    $worktree //= '';
    $head     //= '';

    like $gate, qr/^gate_env perl -c oracle\/goban[.]pl$/m,
        'gate includes oracle syntax evidence under gate_env';
    like $gate, qr/^gate_env perl oracle\/goban[.]pl --smoke$/m,
        'gate includes oracle smoke evidence under gate_env';

    like $worktree, qr/git archive HEAD.*must not be used as\s+current-candidate evidence/s,
        'worktree phase says git archive HEAD is not current-candidate evidence before commit';
    unlike $worktree, qr/^gate_env git archive --format=tar HEAD/m,
        'worktree phase does not use git archive HEAD as evidence';
    unlike $worktree, qr/^gate_env git ls-files/m,
        'worktree phase avoids index-only git ls-files evidence';
    like $worktree, qr/^gate_env perl -MExtUtils::Manifest=maniread -E 'say for sort keys %\{ maniread\(\) \}' \| gate_env perl -ne/m,
        'worktree phase scans the current MANIFEST source set';
    like $worktree, qr/^gate_env perl -MExtUtils::Manifest=maniread -E 'say for sort keys %\{ maniread\(\) \}' \| gate_env tar -T - -cf - \| gate_env tar -x -C "\$tmpdir" -f -$/m,
        'worktree disposable copy is based on the current MANIFEST source set';

    like $head, qr/git status --short.*clean/s,
        'HEAD phase requires a clean worktree';
    like $head, qr/^gate_env sh -c 'test -z "\$\(git status --short\)"'$/m,
        'HEAD phase has executable clean-tree evidence';
    like $head, qr/^gate_env git archive --format=tar HEAD \| gate_env tar -tf - \| gate_env perl -ne/m,
        'HEAD phase uses git archive HEAD only after clean-tree evidence';

    for my $bare (
        qr/^perl -c oracle\/goban[.]pl$/m,
        qr/^perl oracle\/goban[.]pl --smoke$/m,
        qr/^perl Makefile[.]PL$/m,
        qr/^prove -l/m,
        qr/^prove -lr t$/m,
        qr/^git diff --check$/m,
        qr/^git archive --format=tar HEAD/m,
        qr/^git ls-files/m,
        qr/^GOBANFTP_[A-Z0-9_]+=.*\b(?:prove|make)\b/m,
    ) {
        unlike $gate, $bare, "gate has no bare source-gate evidence command: $bare";
    }

    for my $name (qw(
        GOBANFTP_FTP_TEST
        GOBANFTP_FTP_HOST
        GOBANFTP_FTP_USER
        GOBANFTP_FTP_PASSWORD
        GOBANFTP_FTP_ROOT
        GOBANFTP_WEBDAV_URL
        GOBANFTP_WEBDAV_USER
        GOBANFTP_WEBDAV_PASSWORD
        GOBANFTP_WEBDAV_TOKEN
        GOBANFTP_DNS_RECORD_FILE
        GOBANFTP_GIT_REPO
        GOBANFTP_STORE
    )) {
        like $gate, qr/^\s+-u \Q$name\E \\/m, "gate_env unsets $name";
    }

    for my $residue (
        'Makefile',
        'Makefile.old',
        'META.json',
        'META.yml',
        'MYMETA.*',
        'pm_to_blib',
        'blib/',
        '_Inline/',
        'docs/V1_1_UPDATE_CHECKLIST.md',
        'docs/references/',
    ) {
        like $gate, qr/\Q$residue\E/, "gate documents forbidden residue: $residue";
    }

    like $head, qr/Makefile\(\?:\[.\]old\)\?\$/,
        'HEAD archive scan rejects Makefile and Makefile.old';
    like $head, qr/META\[.\]\(\?:json\|yml\)\$/,
        'HEAD archive scan rejects META.json and META.yml';
    like $head, qr/MYMETA\[.\]\(\?:json\|yml\)\$/,
        'HEAD archive scan rejects MYMETA files';
    like $head, qr/pm_to_blib\$/,
        'HEAD archive scan rejects pm_to_blib';
    like $head, qr/\(\?:blib\|_Inline\)\(\?:\/\|\$\)/,
        'HEAD archive scan rejects blib and _Inline trees';
    like $head, qr/docs\/V1_1_UPDATE_CHECKLIST\[.\]md\$/,
        'HEAD archive scan rejects the retired checklist';
    like $head, qr/docs\/references\(\?:\/\|\$\)/,
        'HEAD archive scan rejects reference-only docs';
};

subtest 'public release hygiene wording stays source-gate scoped' => sub {
    unlike $text{'docs/PROFILES.md'}, qr/source-candidate/,
        'profiles avoid source-candidate wording';
    like $text{'docs/PROFILES.md'},
        qr{Optional maintainer-run live FTP provider smoke is outside the current beta\s+source-gate/review scope and fixture-local source evidence},
        'FTP live smoke stays outside the current beta source-gate/review scope and fixture-local source evidence';
    like $text{'docs/PROFILES.md'},
        qr{Optional maintainer-run live WebDAV smoke is outside the current beta\s+source-gate/review scope and fixture-local source evidence},
        'WebDAV live smoke stays outside the current beta source-gate/review scope and fixture-local source evidence';
    like $text{'docs/SHOWCASE.md'},
        qr{Current beta showcase review coverage is source-only, static, and\s+fixture-local},
        'showcase review scope names the current beta';
    unlike $text{'lib/GobanFTP/CLI.pm'}, qr/local-fixture-source-candidate/,
        'showcase release evidence does not use source-candidate scope';
    like $text{'lib/GobanFTP/CLI.pm'}, qr/scope=local-fixture-beta-source-gate/,
        'showcase release evidence names the local fixture beta source gate';
};

subtest 'JSON contract is explicit and narrow' => sub {
    for my $rel (qw(docs/V1_1_RELEASE_GATE.md docs/V1_1_RELEASE_NOTES.md)) {
        like $text{$rel}, qr/command-scoped|command-scoped opt-in JSON/,
            "$rel says JSON is command-scoped";
        like $text{$rel}, qr/no global JSON mode|There is no\nglobal JSON mode/i,
            "$rel says there is no global JSON mode";
        like $text{$rel}, qr/schema\s*=\s*gobanftp[.]<name>[.]v1/,
            "$rel requires schema";
        like $text{$rel}, qr/version\s*=\s*1[.]1/,
            "$rel requires version 1.1";
        like $text{$rel}, qr/structured data/,
            "$rel requires structured rendering";
        like $text{$rel}, qr/must not contain secrets|Secrets must\nnot appear/,
            "$rel excludes secrets from JSON and diagnostics";
    }
    like $text{'docs/DIAGNOSTICS.md'}, qr/This does not declare a complete JSON mode/,
        'diagnostics keeps the general JSON claim narrow';
};

subtest 'claim audit rows carry evidence, test, non-goal, and status' => sub {
    my %rows = _claim_rows($text{'docs/V1_1_RELEASE_GATE.md'});
    for my $claim (
        'WebDAV listing confirmation is hardened.',
        'DNS record-file parsing rejects poisoning cases.',
        'Local store paths reject static symlink components.',
        'FTP publish confirmation uses exact basename checks.',
        'Auth preflight can block explicitly enabled publish.',
        'Auth is not production writer authorization.',
        'Static HTML/Web projection is not hosted Web UI.',
        'Git and DNS remain read-only runtime substrates.',
        'Scoring/result events remain outside GOFTP/1.',
        'Input size and timeout boundaries produce stable public diagnostics.',
        'Cross-substrate roots and replay stay equal across Local, FTP, Git, DNS, and WebDAV fixtures.',
        'Store capability and doctor JSON are scoped and dry-run by default.',
        'Publish result JSON exposes candidate/store/auth state without secrets.',
        'Auth boundary metadata keeps fixture preflight separate from production authorization.',
        'Compact live watch is recordable and still listing-derived.',
        'Static showcase generation is local fixture output only.',
        'Static showcase navigation polish is generated-bundle-only.',
        'P2 local showcase preview helper is loopback-only and read-only.',
    ) {
        my $row = $rows{$claim};
        ok $row, "claim row exists: $claim";
        next if !$row;
        like $row->{evidence}, qr/\bprove -l\b/, "$claim has an evidence command";
        like $row->{test}, qr/\bt\/[A-Za-z0-9_.\/-]+[.]t\b/, "$claim has a test file";
        ok length($row->{non_goal}) > 20, "$claim has a non-goal";
        is $row->{status}, 'BETA', "$claim is beta status";
    }
};

subtest 'P2 preview helper claim stays narrow' => sub {
    my $preview_boundary =
        qr/Generated\s+bundle is static; optional P2 loopback preview helper is\s+local-only\/read-only\s+and not hosted UI\/deploy/;
    my $preview_platform_caveat =
        qr/Preview(?: helper)? support is limited to supported local platforms with the\s+required local\s+safety\/process primitives/;
    my $preview_unsupported_caveat =
        qr/unsupported platforms (?:should )?report\s+unsupported\/skip(?:, and\s+an unsupported or skipped preview run)?\s+(?:and\s+)?must not be used as release evidence/i;

    for my $rel (qw(
        docs/CLI.md
        docs/SHOWCASE.md
        docs/V1_1_RELEASE_GATE.md
        docs/V1_1_RELEASE_NOTES.md
    )) {
        like $text{$rel}, $preview_boundary,
            "$rel keeps static bundle and local preview boundary";
        like $text{$rel}, $preview_platform_caveat,
            "$rel limits preview support to required local safety/process primitives";
        like $text{$rel}, $preview_unsupported_caveat,
            "$rel keeps unsupported preview runs out of release evidence";
    }

    unlike $text{'docs/CLI.md'}, qr/does not\s*start\s+a\s+server/,
        'CLI no longer uses the old server-start wording';
    unlike $text{'docs/SHOWCASE.md'}, qr/not\s+a\s+server/,
        'showcase doc no longer uses the old generated-artifact wording';

    for my $rel (@user_entry_files) {
        my @hits = _user_entry_preview_detail_hits($rel, $text{$rel});
        is_deeply \@hits, [],
            "$rel keeps preview-helper details out of user entry docs";
    }

};

subtest 'user-entry preview detail scanner covers synthetic cases' => sub {
    for my $case (
        [ showcase_preview => 'showcase preview' ],
        [ preview_ip       => 'Preview helper binds 127.0.0.1' ],
        [ zh_preview       => '本地预览' ],
        [ ja_preview       => 'プレビュー ヘルパー' ],
        [ loopback_helper  => 'loopback-only showcase helper' ],
    ) {
        my @hits = _user_entry_preview_detail_hits('synthetic-hit', $case->[1]);
        ok @hits, "scanner rejects $case->[0]";
    }

    for my $case (
        'read-only Git tree',
        'local-only showcase artifact generation from checked-in fixtures',
    ) {
        my @hits = _user_entry_preview_detail_hits('synthetic-pass', $case);
        is_deeply \@hits, [], "scanner allows: $case";
    }
};

subtest 'remaining P2 stretch work stays deferred' => sub {
    for my $rel (qw(
        docs/V1_1_RELEASE_GATE.md
        docs/V1_1_RELEASE_NOTES.md
    )) {
        like $text{$rel}, qr/Remaining P2|remaining P2|剩余 P2/,
            "$rel names remaining P2 scope";
        like $text{$rel}, qr/deferred|Deferred|DEFERRED|defer/,
            "$rel keeps remaining P2 deferred";
    }

    for my $rel (qw(
        docs/V1_1_RELEASE_GATE.md
        docs/V1_1_RELEASE_NOTES.md
    )) {
        unlike $text{$rel}, qr/^\| P2 high-risk stretch work \| PASS \|/m,
            "$rel does not mark high-risk P2 pass";
        unlike $text{$rel}, qr/^\| P2 stretch work \| PASS \|/m,
            "$rel does not mark all P2 stretch work pass";
        unlike $text{$rel}, qr/\bP2\s+(?:complete|completed|done)\b/i,
            "$rel avoids whole-P2 completion wording";
    }

    for my $forbidden (
        qr/\bGitHub Pages\b[^,\n.]{0,80}\b(?:deployed|shipped|implemented|enabled)\b/i,
        qr/\bTUI GIF\/asciinema\b[^,\n.]{0,80}\b(?:shipped|generated|included|implemented)\b/i,
        qr/\bresult\/scoring profile\b[^,\n.]{0,80}\b(?:shipped|implemented|complete)\b/i,
        qr/\bproduction auth\b[^,\n.]{0,80}\b(?:shipped|implemented|complete)\b/i,
        qr/\bDNSSEC\b[^,\n.]{0,80}\b(?:shipped|implemented|complete)\b/i,
        qr/\bGit\/DNS publishing\b[^,\n.]{0,80}\b(?:shipped|implemented|complete)\b/i,
        qr/\bstatic generated-bundle navigation polish\b[^,\n.]{0,80}\b(?:hosted|deploy|server|provider|runtime)\b/i,
    ) {
        for my $rel (qw(
            docs/V1_1_RELEASE_GATE.md
            docs/V1_1_RELEASE_NOTES.md
        )) {
            for my $line (split /\n/, $text{$rel}) {
                next if $line =~ /\b(?:no|not|does not|without|deferred|avoid|outside|out of scope|remain outside|remains outside)\b/i;
                unlike $line, $forbidden, "$rel avoids forbidden P2 shipped claim: $forbidden";
            }
        }
    }
};

subtest 'release notes document compatibility, diagnostics, and non-goals' => sub {
    my $notes = $text{'docs/V1_1_RELEASE_NOTES.md'};
    like $notes, qr/`GOFTP\/1` consensus is unchanged/,
        'release notes keep GOFTP/1 unchanged';
    like $notes, qr/Default CLI output remains key\/value stdout/,
        'release notes document key/value compatibility';
    like $notes, qr/JSON is opt-in per command only/,
        'release notes document command-scoped JSON';
    like $notes, qr/Malformed attestation and publish-token JSONL now report validation/,
        'release notes document auth JSONL validation diagnostics';
    like $notes, qr/Oversized WebDAV, DNS record-file, FTP listing, attestation JSONL, and\n\s+publish-token JSONL inputs report stable/,
        'release notes document oversized input diagnostics';
    like $notes, qr/does not claim hosted Web UI, browser application, server\s+deployment, provider deploy, production auth, production writer authorization/,
        'release notes document public non-goals';
    like $notes, qr/complete scoring\/result system/,
        'release notes keep scoring/result out of GOFTP/1';
};

subtest 'roadmap and manifest are beta-safe' => sub {
    unlike $text{'docs/ROADMAP.md'}, qr/does not claim any fix is present/,
        'roadmap no longer says no v1.1 fix is present in the beta';
    for my $stale (
        qr/currently extracts every/,
        qr/scan whole rows/,
        qr/newline-injectable/,
        qr/current impact/,
        qr/can still produce non-empty/,
    ) {
        unlike $text{'docs/ROADMAP.md'}, $stale,
            "roadmap avoids stale unresolved-risk wording: $stale";
    }
    for my $entry (qw(
        docs/V1_1_RELEASE_GATE.md
        docs/V1_1_RELEASE_NOTES.md
        docs/V1_1_AUTH_BOUNDARY.md
        lib/GobanFTP/Auth/Boundary.pm
        lib/GobanFTP/JSON.pm
        lib/GobanFTP/Showcase/StaticPreview.pm
        t/auth-boundary.t
        t/cli-config-doctor.t
        t/ci-source-release-gate.t
        t/json-helper.t
        t/publish-result-json.t
        t/showcase-preview.t
        t/showcase-v1_1.t
        t/v1-claim-audit.t
        t/v1-conformance-boundary.t
    )) {
        like $text{MANIFEST}, qr/^\Q$entry\E$/m, "MANIFEST includes $entry";
    }

    unlike $text{MANIFEST}, qr/^evidence(?:\/|\z)/m, 'MANIFEST excludes local evidence directories';
    unlike $text{MANIFEST}, qr/^docs\/V1_1_UPDATE_CHECKLIST[.]md$/m,
        'MANIFEST excludes the retired v1.1 update checklist';
    like $text{'MANIFEST.SKIP'}, qr/^\^docs\/V1_1_UPDATE_CHECKLIST\\[.]md\$$/m,
        'MANIFEST.SKIP keeps the retired v1.1 checklist from returning';
};

done_testing;

sub _claim_rows {
    my ($markdown) = @_;

    my %rows;
    for my $line (split /\n/, $markdown) {
        next if $line !~ /\A\| /;
        next if $line =~ /\A\| ---/;
        my @cells = map {
            s/\A\s+//r =~ s/\s+\z//r
        } split /\|/, $line;
        shift @cells if @cells && $cells[0] eq '';
        pop @cells if @cells && $cells[-1] eq '';
        next if @cells != 5 || $cells[0] eq 'Claim';
        $rows{$cells[0]} = {
            evidence => $cells[1],
            test     => $cells[2],
            non_goal => $cells[3],
            status   => $cells[4],
        };
    }

    return %rows;
}

sub _user_entry_preview_detail_hits {
    my ($source, $body) = @_;

    my @rules = (
        [ 'showcase preview', qr/\bshowcase\b.*\bpreview\b/is ],
        [
            'preview helper/detail',
            qr/\bpreview\b.*(?:\b(?:helper|loopback|localhost|local-only|read-only|hosted|deploy)\b|127[.]0[.]0[.]1|\brelease\s+evidence\b)/is,
        ],
        [ 'Chinese preview wording', qr/预览/ ],
        [ 'Japanese preview wording', qr/プレビュー/ ],
        [
            'loopback preview/showcase detail',
            qr/(?:(?:\bshowcase\b|\bpreview\b).*(?:\bloopback\b|\blocalhost\b|127[.]0[.]0[.]1)|(?:\bloopback\b|\blocalhost\b|127[.]0[.]0[.]1).*(?:\bshowcase\b|\bpreview\b))/is,
        ],
        [ 'local-only/read-only combo', qr/(?:\blocal-only\b.*\bread-only\b|\bread-only\b.*\blocal-only\b)/is ],
        [ 'helper/showcase local-read combo', qr/(?=.*\b(?:helper|showcase)\b)(?=.*\blocal-only\b)(?=.*\bread-only\b)/is ],
    );

    my @lines = split /\n/, $body, -1;
    my @hits;
    for my $idx (0 .. $#lines) {
        my @window = ($lines[$idx]);
        push @window, $lines[$idx + 1] if $idx + 1 <= $#lines;
        my $window = join "\n", @window;

        for my $rule (@rules) {
            next if $window !~ $rule->[1];

            my $excerpt = $window;
            $excerpt =~ s/\s+/ /g;
            $excerpt =~ s/\A\s+//;
            $excerpt =~ s/\s+\z//;
            push @hits, sprintf '%s:%d-%d %s: %s',
                $source, $idx + 1, $idx + @window, $rule->[0], $excerpt;
            last;
        }
    }

    return @hits;
}

sub _read_text {
    my ($path) = @_;

    open my $fh, '<:encoding(UTF-8)', $path or die "open $path: $!";
    local $/;
    my $text = <$fh>;
    close $fh or die "close $path: $!";

    return $text // '';
}
