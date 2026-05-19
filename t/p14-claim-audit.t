use v5.34;
use strict;
use warnings;

use FindBin;
use File::Spec;
use Test::More;

my $repo_root = File::Spec->rel2abs("$FindBin::Bin/..");

my @release_files = (
    ['README.md',                                      0],
    ['Changes',                                        0],
    ['docs/ROADMAP.md',                                0],
    ['docs/V1_DOD.md',                                 0],
    ['docs/P14_RELEASE_GATE.md',                       0],
    ['docs/P14_RELEASE_MANIFEST_AND_TAG_PLAN.md',      0],
    ['docs/SESSION_RESTORE.md',                        1],
    ['lib/GobanFTP.pm',                                0],
);

my %text;
for my $case (@release_files) {
    my ($rel, $optional) = @$case;
    my $path = File::Spec->catfile($repo_root, split '/', $rel);
    if (!-f $path) {
        ok $optional, "$rel is optional outside the source checkout";
        next;
    }
    $text{$rel} = _read_text($path);
    ok length($text{$rel}) > 0, "$rel is readable";
}

subtest 'release-state guardrails are explicit' => sub {
    _like('Changes', qr/^1[.]000  2026-05-19$/m,
        'Changes keeps the final-candidate package version and date');
    _like('lib/GobanFTP.pm', qr/^our \$VERSION = '1[.]000';$/m,
        'module declares the final-candidate package version');
    _like('README.md', qr/^Current line: `v1[.]0\/P14` final candidate[.]$/m,
        'README names the current line as final candidate');
    _like('README.md', qr/read-only inspection output, not hosted Web UI or interactive TUI[.]/,
        'README keeps static surfaces below hosted Web UI and interactive TUI');
    _like('README.md', qr/DNS\s+admission does not query live DNS, run AXFR, trust DNSSEC, call provider APIs,\s+or publish records,/,
        'README keeps DNS admission read-only and non-live');
    _like('README.md', qr/it does not claim live FTP, `RETR`, `SIZE`, `MDTM`, FTP auth, FTP integrity, or\nFTP publish behavior[.]/,
        'README keeps FTP listing-shadow evidence fixture-bound');
    _like('docs/P14_RELEASE_GATE.md',
        qr/Status: dry-run, development-freeze, and final-candidate preparation evidence\nonly[.] This is not a v1[.]0 tag, not P14 completion, and not a release-ready\ndeclaration[.]/,
        'P14 gate report is preparation evidence, not a release declaration');
    _like('docs/P14_RELEASE_MANIFEST_AND_TAG_PLAN.md',
        qr/Do not tag before the final stable matrix and external artifact record are\ncomplete[.]/,
        'tag plan blocks tagging before the final matrix and artifact record');
    _like('docs/V1_DOD.md',
        qr/v1[.]0 may not be tagged until these gates pass from a clean checkout:/,
        'V1 DoD keeps tagging behind the clean checkout gate');
    _like('docs/ROADMAP.md',
        qr/This is not Git publish, Git remote fetch, live FTP, FTP auth, FTP integrity,\nFTP publish behavior, live DNS, DNS publish, hosted Web UI, interactive TUI, or\na v1[.]0\/P14 completion claim[.]/,
        'roadmap keeps the current proof below forbidden release claims');
    _like_optional('docs/SESSION_RESTORE.md',
        qr/do not tag or publish it as\n  v1[.]0/,
        'restore memory blocks publishing the development matrix as v1.0');
};

subtest 'claim-audit gate is part of the release matrix' => sub {
    _like('docs/P14_RELEASE_MANIFEST_AND_TAG_PLAN.md',
        qr/^prove -lr t\/p14-claim-audit[.]t$/m,
        'release matrix runs the claim audit gate');
    _like('docs/V1_DOD.md',
        qr/^prove -lr t\/p14-claim-audit[.]t$/m,
        'normative v1.0 release gate runs the claim audit gate');
};

subtest 'allowed and forbidden claim registries are complete' => sub {
    my $plan = $text{'docs/P14_RELEASE_MANIFEST_AND_TAG_PLAN.md'};

    for my $allowed (
        'GOFTP/1 descriptor and direct events/ basenames remain authoritative',
        'event ids remain filename-context derived',
        'event_set_root is stable across accepted event basenames',
        'local, FTP, Git-tree, DNS-record, and WebDAV runtime read paths are implemented',
        'FTP listing-shadow public poison-vector evidence is fixture/listing evidence',
        'signed-hmac-goftp1 has an explicit per-event HMAC acceptance gate',
        'public key and trust fixture reports are advisory outside signed profiles',
        'text, static HTML, and static terminal witness surfaces are read-only displays',
        'source art is runnable and non-consensus',
        'the arch-gate motif is comment-only source art, not witness output or protocol input',
        'P14/v1.0 final candidate is active',
        'v1.0 remains unreleased until the final release-freeze matrix passes',
    ) {
        like $plan, qr/^\Q$allowed\E/m, "allowed claim recorded: $allowed";
    }

    for my $forbidden (
        'v1.0 is complete',
        'P14 is complete',
        'hosted Web UI is complete',
        'interactive mouse/keyboard TUI is complete',
        'Git publish support is implemented',
        'live DNS / AXFR / DNSSEC trust / provider API support is implemented',
        'DNS dynamic update or DNS record publishing is implemented',
        'production key lifecycle is complete',
        'publish authentication policy is complete',
        'final scoring/result events are part of GOFTP/1',
        'source art, Web, TUI, C, or asm-like surfaces own replay truth',
        'the arch-gate motif claims Arch Linux affiliation, endorsement, package',
    ) {
        like $plan, qr/^\Q$forbidden\E/m, "forbidden claim recorded: $forbidden";
    }
};

subtest 'forbidden claims appear only in guarded contexts' => sub {
    my @patterns = (
        [qr/\bv1[.]0\s+(?:is\s+)?(?:complete|ready|released|tagged)\b/i,
            'v1.0 final state'],
        [qr/\bP14\s+(?:is\s+)?(?:complete|ready)\b/i,
            'P14 final state'],
        [qr/\brelease-ready declaration\b/i,
            'release-ready declaration'],
        [qr/\bhosted Web UI\s+(?:is\s+)?(?:complete|implemented|ready|shipped)\b/i,
            'hosted Web UI completion'],
        [qr/\binteractive(?: mouse\/keyboard)? TUI\s+(?:is\s+)?(?:complete|implemented|ready|shipped)\b/i,
            'interactive TUI completion'],
        [qr/\bGit publish(?: support)?\s+(?:is\s+)?(?:implemented|complete|ready)\b/i,
            'Git publish support'],
        [qr/\blive DNS\b.*\b(?:implemented|complete|ready|supported|admitted)\b/i,
            'live DNS support'],
        [qr/\bAXFR\b.*\b(?:implemented|complete|ready|supported)\b/i,
            'AXFR support'],
        [qr/\bDNSSEC\b.*\b(?:trust|support|supported|implemented|complete|ready)\b/i,
            'DNSSEC trust support'],
        [qr/\bprovider API(?:s)?\b.*\b(?:support|supported|implemented|complete|ready)\b/i,
            'provider API support'],
        [qr/\bDNS(?: dynamic update| record publishing| publish(?:ing)?)\b.*\b(?:implemented|complete|ready|supported)\b/i,
            'DNS publish support'],
        [qr/\bFTP auth\b.*\b(?:implemented|complete|ready|supported)\b/i,
            'FTP auth support'],
        [qr/\bFTP integrity\b.*\b(?:implemented|complete|ready|supported)\b/i,
            'FTP integrity support'],
        [qr/\bFTP publish behavior\b.*\b(?:implemented|complete|ready|supported)\b/i,
            'FTP publish support'],
        [qr/\bproduction key lifecycle\s+(?:is\s+)?(?:complete|implemented|ready)\b/i,
            'production key lifecycle completion'],
        [qr/\bpublish authentication policy\s+(?:is\s+)?(?:complete|implemented|ready)\b/i,
            'publish authentication policy completion'],
        [qr/\b(?:source art|Web|TUI|Inline::C|asm-like)\b.*\bown(?:s)? (?:replay )?truth\b/i,
            'display or accelerator owns truth'],
    );

    my @unguarded;
    for my $rel (sort keys %text) {
        my @lines = split /\n/, $text{$rel};
        LINE:
        for my $i (0 .. $#lines) {
            my $candidate = $lines[$i];
            $candidate .= " $lines[$i + 1]" if $i < $#lines;
            for my $case (@patterns) {
                my ($pattern, $label) = @$case;
                next if $candidate !~ /$pattern/;
                next LINE if _guarded_context(\@lines, $i, $candidate);
                push @unguarded, sprintf '%s:%d: %s: %s', $rel, $i + 1, $label, $candidate;
            }
        }
    }

    is_deeply \@unguarded, [], 'no unguarded forbidden release claims';
};

subtest 'claim guard helper distinguishes forbidden lists from positive claims' => sub {
    my @unguarded = ('GobanFTP v1.0 is ready.');
    ok !_guarded_context(\@unguarded, 0), 'unguarded positive claim would fail';

    my @negated = ('GobanFTP v1.0 is not ready.');
    ok _guarded_context(\@negated, 0, $negated[0]), 'nearby negation guards a forbidden phrase';

    my @registry = (
        'Forbidden final-release claims unless additional code and gates land first:',
        '',
        'v1.0 is complete',
    );
    ok _guarded_context(\@registry, 2, $registry[2]), 'forbidden-claim registry may name the claim';

    my @wrapped = ('GobanFTP v1.0 is', 'ready.');
    my $wrapped_candidate = "$wrapped[0] $wrapped[1]";
    like $wrapped_candidate, qr/\bv1[.]0\s+(?:is\s+)?(?:complete|ready|released|tagged)\b/i,
        'wrapped positive claim is still matched';
    ok !_guarded_context(\@wrapped, 0, $wrapped_candidate), 'wrapped positive claim is not guarded';
};

done_testing;

sub _like {
    my ($rel, $pattern, $label) = @_;

    ok exists $text{$rel}, "$rel is available for $label";
    like $text{$rel} // '', $pattern, $label;
}

sub _like_optional {
    my ($rel, $pattern, $label) = @_;

    if (!exists $text{$rel}) {
        pass "$rel omitted outside source checkout; $label";
        return;
    }

    like $text{$rel}, $pattern, $label;
}

sub _guarded_context {
    my ($lines, $index, $candidate) = @_;

    my $start = $index - 2;
    $start = 0 if $start < 0;
    my $end = $index + 1;
    $end = $#$lines if $end > $#$lines;

    my $window = join "\n", @{$lines}[$start .. $end];
    $candidate = $window if !defined $candidate;
    return 1 if ($candidate =~ /
        \b(?:
            not|no|none|without|outside|deferred|unless|forbidden|blocked|
            must\s+not|do\s+not|does\s+not|cannot|only\s+when|until|
            future|skipped|unreleased|avoid(?:ing)?|denied|not\s+yet
        )\b
    /ix);
    return 1 if $window =~ /\b(?:not\s+a|not\s+an|without\s+claiming|without\s+adding|without\s+declaring|does\s+not|do\s+not|must\s+not|may\s+not|cannot|excluding|avoiding\s+any\s+claim)\b/i;

    my $section_start = $index - 24;
    $section_start = 0 if $section_start < 0;
    my $section = join "\n", @{$lines}[$section_start .. $index];
    return $section =~ /^Forbidden final-release claims\b/m;

    return 0;
}

sub _read_text {
    my ($path) = @_;

    open my $fh, '<:encoding(UTF-8)', $path or die "open $path: $!";
    my $text = do { local $/; <$fh> };
    close $fh or die "close $path: $!";

    return $text // '';
}
