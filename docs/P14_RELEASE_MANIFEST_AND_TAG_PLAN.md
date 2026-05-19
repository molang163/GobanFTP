# P14 Release Manifest And Tag Plan

Status: final v1.0/package 1.000 release-source plan.

The local `v0.2` / package `0.002` release candidate was skipped as a public
release. Do not publish, push, or reuse the old `v0.2` tag or
`GobanFTP-0.002.tar.gz` artifact.

## Release Identity

The source identity is:

```text
project milestone: v1.0/P14 proof machine
Perl version:      1.000
Changes heading:   1.000  2026-05-19
expected tarball:  GobanFTP-1.000.tar.gz
Git tag:           v1.0
```

The source files intentionally do not contain the final tarball hash. The hash
belongs in the annotated tag message or release notes created from the final
artifact.

The latest previous public release record remains:

```text
public Git tag:       v0.1
Perl package version: 0.001
project milestone:    v0.1 hardening/showcase
```

## Manifest Requirements

`MANIFEST` must include the release-plan documents, protocol documents, runtime
library, CLI entry point, source-art smoke wrapper, examples, fixtures, tests,
public vectors, and intentional fixture specimens.

Required release-source paths include:

```text
Changes
README.md
Makefile.PL
MANIFEST
MANIFEST.SKIP
cpanfile
docs/P14_RELEASE_GATE.md
docs/P14_RELEASE_MANIFEST_AND_TAG_PLAN.md
docs/V1_DOD.md
docs/GRAMMAR.md
docs/ROADMAP.md
lib/**
script/**
oracle/goban.pl
examples/fixtures/**
t/**
t/fixtures/attacks/tmp-poison/tmp/pending.part
```

Required excluded paths include:

```text
.git
_Inline/
blib/
Makefile
Makefile.old
META.json
META.yml
MYMETA.json
MYMETA.yml
pm_to_blib
GobanFTP-*.tar.gz
GobanFTP-*/
docs/SESSION_RESTORE.md
non-fixture *.part
non-fixture *.tmp
non-fixture *.bak
.gobanftp-tmp-*
```

`META.json` and `META.yml` are local generated residue in the source checkout.
`make dist` may generate fresh CPAN metadata inside the distribution archive.
`MYMETA.*` remains local configure residue and must not appear in the archive.

## Release Matrix

Run the final matrix from a clean checkout:

```sh
perl -c oracle/goban.pl
perl oracle/goban.pl --smoke

perl Makefile.PL
GOBANFTP_RULES_DISABLE_C=1 GOBANFTP_RULES_ENGINE=perl make test
GOBANFTP_RULES_ENGINE=shadow make test

prove -lr t
prove -lr t/v1-cross-substrate.t
prove -lr t/v1-attack-fixtures.t
prove -lr t/v1-profile-attack-fixtures.t
prove -lr t/v1-profile-publish-fixtures.t
prove -lr t/v1-publish-auth-golden-vectors.t
prove -lr t/v1-golden-vectors.t
prove -lr t/v1-signed-hmac.t
prove -lr t/v1-signed-hmac-overlay.t
prove -lr t/v1-signed-hmac-golden-vectors.t
prove -lr t/auth-hmac-key.t t/cli-auth-hmac.t
prove -lr t/auth-publish-token.t t/cli-auth-publish-token.t
prove -lr t/publish-auth-preflight.t t/tui-play.t t/store-git-tree.t t/dns-cli-parity.t t/ftp-cli-parity.t t/webdav-cli-parity.t
prove -lr t/profile-registry.t t/profile-adapter.t t/witness-api.t
prove -lr t/diagnostics-contract.t
prove -lr t/rules-flow.t t/rules-superko.t
prove -lr t/p14-claim-audit.t

script/gobanftp v1 witness --profile local-goftp1 --fixture t/fixtures/v1/cross-substrate/minimal
script/gobanftp v1 compare-roots --fixture t/fixtures/v1/cross-substrate/minimal
script/gobanftp v1 compare-replay --fixture t/fixtures/v1/cross-substrate/minimal

make manifest
git diff --exit-code MANIFEST MANIFEST.SKIP

make dist
dist=GobanFTP-1.000.tar.gz
test -f "$dist"
test "$(find . -maxdepth 1 -name 'GobanFTP-*.tar.gz' -print | wc -l)" -eq 1
tar -tzf "$dist" | rg 'docs/P14_RELEASE_MANIFEST_AND_TAG_PLAN\.md'
tar -tzf "$dist" | rg 'docs/P14_RELEASE_GATE\.md'
tar -tzf "$dist" | rg 't/p14-claim-audit\.t'
tar -tzf "$dist" | rg 't/fixtures/vectors/v1-non-consensus-poison\.jsonl'
tar -tzf "$dist" | rg 't/fixtures/vectors/v1-publish-auth\.jsonl'
! tar -tzf "$dist" | rg '^[^/]+/docs/SESSION_RESTORE\.md$'
! tar -tzf "$dist" | rg '^[^/]+/(?:blib|_Inline)(?:/|$)'
! tar -tzf "$dist" | rg '^[^/]+/MYMETA\.(?:json|yml)$'
! tar -tzf "$dist" | rg '^[^/]+/pm_to_blib$'
! tar -tzf "$dist" | rg '^[^/]+/GobanFTP-[0-9][^/]*\.tar\.gz$'
! tar -tzf "$dist" | rg '^[^/]+/GobanFTP-[0-9][^/]*/'

GOBANFTP_RULES_DISABLE_C=1 GOBANFTP_RULES_ENGINE=perl make disttest
make distcheck
```

If live FTP is included in an external release claim, also run
`script/live-ftp-smoke` against its disposable localhost server. If it is
skipped, the release record must say that mock FTP plus the local smoke path are
the shipped proof.

## External Artifact Record

Record these values in the annotated tag message or release notes, not in this
source file:

```text
source commit:          <sha>
git tag:                <v1.0>
Perl version:           <1.000>
Changes heading:        <1.000  YYYY-MM-DD>
tarball:                <GobanFTP-1.000.tar.gz>
tarball sha256:         <external-sha256>
tarball size:           <size>
tar entry count:        <count>
top-level prefix:       <GobanFTP-1.000/>
MANIFEST check:         <clean>
matrix result:          <PASS>
live FTP:               <run or skipped, with reason>
Inline::C:              <available, skipped, or optional fallback>
deferred claims:        <explicit list>
```

## Claim Audit Registry

Allowed final v1.0/package 1.000 claims:

```text
v1.0/package 1.000 release source is active
GOFTP/1 descriptor and direct events/ basenames remain authoritative
event ids remain filename-context derived
event_set_root is frozen across accepted event basenames
local, FTP, Git-tree, DNS-record, and WebDAV runtime read paths are implemented
Git-tree and DNS-record runtime paths are read-only
WebDAV publish uses zero-byte tmp resource, MOVE, and fresh PROPFIND confirmation
FTP listing-shadow public poison-vector evidence is fixture/listing evidence only, not live FTP, RETR, SIZE, MDTM, auth, integrity, or publish behavior
diagnostics registry is the v1 source for diagnostic code/class/required/optional/human meaning
storage diagnostic class is active for storage-boundary failures even when current CLI storage failures use exit 4 and storage: stderr
minimal JSON/JSONL evidence covers witness/schema/diagnostic records only, not complete JSON output for every command
signed-hmac-goftp1 has an explicit per-event HMAC acceptance gate
v1 keygen and v1 attest provide verifier-local signed-HMAC operation support without changing unsigned replay
signed-HMAC cross-substrate overlay proves signed acceptance invariance across admitted read profiles with explicit verifier-local HMAC trust input
signed-HMAC overlay is read-only witness evidence and does not authorize publish
fixture key lifecycle semantics cover trusted, rotated, revoked, and expired fixture status without changing unsigned replay
publish auth fixture semantics distinguish verification from new-material publishing without authorizing real writers
signed/auth mismatch diagnostics have named fixture and golden-vector evidence for signature-class witness-gate and publish-auth denials
publish-auth public vector evidence is limited to GOFTP-HMAC-PUBLISH/1 token mismatch denial and unsigned GOFTP/1 invariance
default-off verifier-local publish preflight can block local, FTP, and WebDAV store writes while staying separate from Git-tree and DNS-record read-only storage boundaries without changing default unsigned publish paths
signed-HMAC verifier lifecycle status is explicit verifier input, not GOFTP-TRUST public-key authority
public key and trust fixture reports are advisory outside signed profiles
text, static HTML, and static terminal witness surfaces are read-only displays
local play --tui keyboard/mouse input is implemented as a non-consensus input/display layer over existing publish callbacks
source art is runnable and non-consensus
source art, Web, TUI, C, and asm-like surfaces do not own replay truth or diagnostics truth
the arch-gate motif is comment-only source art, not witness output or protocol input
final tarball hash is external release metadata and not source content
```

Forbidden over-claims:

```text
hosted Web UI is implemented
hosted Web UI is complete
cross-terminal TUI compatibility matrix is complete
Git publish support is implemented
Git remote fetch support is implemented
live DNS / AXFR / DNSSEC trust / provider API support is implemented
live DNS resolver support is implemented
DNS dynamic update or DNS record publishing is implemented
production key lifecycle is complete
production auth is complete
publish authentication policy is complete
publish auth is complete
signed-HMAC overlay is production key lifecycle
signed-HMAC overlay implements publish authentication
HMAC attestations authorize publish or writer access
GOFTP-HMAC-PUBLISH/1 is production auth
public GOFTP-TRUST k1 rows authorize signed-HMAC selectors
fixture key lifecycle is production key lifecycle
publish auth fixture semantics authorize real publish or writer access
rotated, revoked, or expired keys can publish new material
v1 trust-report --fixture enforces signed-HMAC or production publish auth
fixture-ed25519-v1 is a production signing suite
production publish signing or authorization is implemented
complete signed/auth diagnostics coverage is implemented
complete public attack coverage is implemented
final scoring/result events are part of GOFTP/1
source art, Web, TUI, C, or asm-like surfaces own replay truth
JSON output is complete for every command
Web, TUI, source art, C, or asm-like surfaces define diagnostic meaning
the arch-gate motif claims outside distribution affiliation, endorsement, package, identity, project logo, protocol name, profile id, or release artifact identity
```

The `t/p14-claim-audit.t` gate scans release-facing source text for these
over-claims. A forbidden claim is a release blocker even when the implementation
tests pass.

## Tag Procedure

Use an annotated tag after the clean matrix and external artifact record agree:

```sh
git status --short
git rev-parse --verify v1.0 >/dev/null 2>&1 && exit 1 || true
git tag -a v1.0 -m "GobanFTP v1.0 / package 1.000 P14 proof machine; artifact sha256 <external-sha256>"
test "$(git rev-parse v1.0^{commit})" = "$(git rev-parse HEAD)"
git cat-file -t v1.0 | grep '^tag$'
git show --stat --oneline --decorate v1.0
```

Do not tag a dirty worktree. Do not write the final tarball hash into source
files that are included in the distribution archive.
