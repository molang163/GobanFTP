use v5.34;
use strict;
use warnings;

use FindBin;
use File::Spec;
use Test::More;

my $repo_root = File::Spec->rel2abs("$FindBin::Bin/..");

my %text = map { $_ => _read_text(File::Spec->catfile($repo_root, split '/', $_)) } qw(
    Changes
    README.md
    docs/CLI.md
    docs/DIAGNOSTICS.md
    docs/ROADMAP.md
    docs/SHOWCASE.md
    docs/V1_1_RELEASE_GATE.md
    docs/V1_1_RELEASE_NOTES.md
    docs/V1_1_UPDATE_CHECKLIST.md
    docs/V1_1_AUTH_BOUNDARY.md
    .gitignore
    MANIFEST
    MANIFEST.SKIP
);

subtest 'candidate release state stays guarded' => sub {
    like $text{'README.md'}, qr/^Current release: `v1[.]0[.]1\/package 1[.]001`[.]$/m,
        'README current release remains v1.0.1/package 1.001';
    like $text{'docs/V1_1_RELEASE_GATE.md'},
        qr/^Status: v1[.]1 integration candidate only; not released[.]$/m,
        'v1.1 release gate is candidate-only';
    like $text{'docs/V1_1_RELEASE_NOTES.md'},
        qr/^Status: integration candidate notes only; not released[.]$/m,
        'v1.1 release notes are candidate-only';
    like $text{Changes}, qr/^v1[.]1-candidate  2026-05-25 [(]not released[)]$/m,
        'Changes records the v1.1 candidate without making it a release';
    like $text{'docs/V1_1_RELEASE_GATE.md'},
        qr/not tag, push, upload,\ndeploy/,
        'gate records no tag/push/upload/deploy';
    unlike $text{'docs/V1_1_RELEASE_GATE.md'}, qr/^make dist$/m,
        'gate does not run make dist as an evidence command';
    unlike $text{'docs/V1_1_RELEASE_GATE.md'}, qr/^make disttest$/m,
        'gate does not run make disttest';
    unlike $text{'docs/V1_1_RELEASE_GATE.md'}, qr/^make distcheck$/m,
        'gate does not run make distcheck';
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
        is $row->{status}, 'CANDIDATE', "$claim is candidate status";
    }
};

subtest 'P2 preview helper claim stays narrow' => sub {
    my $preview_boundary =
        qr/Generated\s+bundle is static; optional P2 loopback preview helper is\s+local-only\/read-only\s+and not hosted UI\/deploy/;

    for my $rel (qw(
        docs/CLI.md
        docs/SHOWCASE.md
        docs/V1_1_RELEASE_GATE.md
        docs/V1_1_RELEASE_NOTES.md
    )) {
        like $text{$rel}, $preview_boundary,
            "$rel keeps static bundle and local preview boundary";
    }

    unlike $text{'docs/CLI.md'}, qr/does not\s*start\s+a\s+server/,
        'CLI no longer uses the old server-start wording';
    unlike $text{'docs/SHOWCASE.md'}, qr/not\s+a\s+server/,
        'showcase doc no longer uses the old generated-artifact wording';

};

subtest 'remaining P2 stretch work stays deferred' => sub {
    for my $rel (qw(
        docs/V1_1_RELEASE_GATE.md
        docs/V1_1_RELEASE_NOTES.md
        docs/V1_1_UPDATE_CHECKLIST.md
    )) {
        like $text{$rel}, qr/Remaining P2|remaining P2|剩余 P2/,
            "$rel names remaining P2 scope";
        like $text{$rel}, qr/deferred|Deferred|DEFERRED|defer/,
            "$rel keeps remaining P2 deferred";
    }

    like $text{'docs/V1_1_UPDATE_CHECKLIST.md'},
        qr/Local read-only `showcase preview` helper/,
        'checklist uses preview wording instead of serve helper wording';
    like $text{'docs/V1_1_UPDATE_CHECKLIST.md'},
        qr/Static generated showcase navigation polish/,
        'checklist records the accepted static navigation polish slice';
    unlike $text{'docs/V1_1_UPDATE_CHECKLIST.md'},
        qr/Local read-only `serve` helper/,
        'checklist does not revive serve helper wording';

    for my $rel (qw(
        docs/V1_1_RELEASE_GATE.md
        docs/V1_1_RELEASE_NOTES.md
        docs/V1_1_UPDATE_CHECKLIST.md
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
        docs/V1_1_UPDATE_CHECKLIST.md
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

subtest 'roadmap and manifest are candidate-safe' => sub {
    unlike $text{'docs/ROADMAP.md'}, qr/does not claim any fix is present/,
        'roadmap no longer says no v1.1 fix is present in the candidate';
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

    for my $entry (qw(
        docs/V1_1_GATE_MEMO.md
        docs/v1.1-unattended-plan.md
        evidence
    )) {
        unlike $text{MANIFEST}, qr/^\Q$entry\E(?:\/|\z)/m, "MANIFEST excludes internal $entry";
    }

    like $text{'MANIFEST.SKIP'}, qr/^\^evidence\//m, 'MANIFEST.SKIP excludes evidence directory';
    like $text{'MANIFEST.SKIP'}, qr/^\^docs\/V1_1_GATE_MEMO[\\][.]md\$$/m,
        'MANIFEST.SKIP excludes local gate memo';
    like $text{'MANIFEST.SKIP'}, qr/^\^docs\/v1[\\][.]1-unattended-plan[\\][.]md\$$/m,
        'MANIFEST.SKIP excludes unattended plan';
    like $text{'.gitignore'}, qr/^evidence\/$/m, '.gitignore excludes evidence directory';
    like $text{'.gitignore'}, qr/^docs\/V1_1_GATE_MEMO[.]md$/m,
        '.gitignore excludes local gate memo';
    like $text{'.gitignore'}, qr/^docs\/v1[.]1-unattended-plan[.]md$/m,
        '.gitignore excludes unattended plan';
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

sub _read_text {
    my ($path) = @_;

    open my $fh, '<:encoding(UTF-8)', $path or die "open $path: $!";
    local $/;
    my $text = <$fh>;
    close $fh or die "close $path: $!";

    return $text // '';
}
