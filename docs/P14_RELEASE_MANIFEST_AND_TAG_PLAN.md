# P14 Release Manifest And Tag Plan

Status: active v1.0/P14 final-candidate release plan. The old local `v0.2` /
package `0.002` candidate is superseded and was skipped as a public release.
Do not publish, push, or reuse the old `v0.2` tag or
`GobanFTP-0.002.tar.gz` artifact. This is not a v1.0 completion claim, a P14
completion claim, or permission to tag before the final stable matrix and
external artifact record are complete.

This document records the current final-candidate identity, the reserved
annotated tag identity, and the artifact checks that must be resolved after the
P14 release-gate dry run in `docs/P14_RELEASE_GATE.md`.

## Current Identity State

The latest public release record has three names that must not be confused:

```text
public Git tag:      v0.1
Perl package version: 0.001
project milestone:   v0.1 hardening/showcase
```

The skipped local v0.2 release candidate proposed:

```text
proposed local tag:    v0.2 (not public; do not reuse)
Changes heading:       0.002  2026-05-18
lib/GobanFTP.pm:       $VERSION = 0.002
expected tarball name: GobanFTP-0.002.tar.gz
project target:        v1.0/P14 proof machine
```

That state was a local release-candidate identity only. It was not pushed or
published, and it must not be treated as the public release record.

The active final-candidate identity is now:

```text
Git tag:          none
Perl version:     1.000
Changes heading:  1.000  2026-05-19
expected tarball: GobanFTP-1.000.tar.gz
release claim:    v1.0/P14 final candidate, not v1.0 complete or released
```

## Superseded v0.2 Candidate

The skipped candidate was:

```text
proposed local tag: v0.2 (not public; do not reuse)
Perl version:       0.002
Changes heading:    0.002  YYYY-MM-DD
tarball name:       GobanFTP-0.002.tar.gz
release claim:      pre-v1.0/P14 release-route checkpoint, not v1.0
```

Rationale:

```text
The skipped candidate carried the v0.2 package-version entry.
lib/GobanFTP.pm declared the package version used by MakeMaker.
The dry-run tarball was GobanFTP-0.001.tar.gz and belongs to the dry run only.
docs/P14_RELEASE_GATE.md remains explicit that v1.0 was not ready or tagged.
```

This route remains a historical local candidate only.

## Reserved v1.0 Tag Identity

Use the annotated tag identity only after the final P14 claim audit, final
stable clean-checkout matrix, and external artifact record agree:

```text
Git tag:          v1.0
Perl version:     1.000
Changes heading:  1.000  YYYY-MM-DD
tarball name:     GobanFTP-1.000.tar.gz
release claim:    v1.0/P14 proof machine release record
```

The `v1.0` route must still satisfy `docs/V1_DOD.md`; the current final
candidate is not the final release record.

Do not create a tag if `Changes`, `$VERSION`, the expected tarball name, and the
chosen Git tag drift apart. Do not call an artifact final if its tarball name
disagrees with the tag or the `Changes` heading.

## Final Candidate Inputs

Before tagging, record these values in the release record below:

```text
candidate commit
chosen git tag
chosen Perl version
Changes heading date
MANIFEST status
tarball name
tarball sha256
tarball size
final matrix result
skipped gates
deferred claims
```

The final artifact hash record must live outside the release tarball, for
example in the annotated tag message or GitHub release notes. This document is
included in the tarball, so writing the final tarball hash into this file would
change the tarball and invalidate the hash.

`MANIFEST` must include the final release-plan documents and all intentional
fixture specimens. It must not include local build products, temporary publish
residue, `.git`, `docs/SESSION_RESTORE.md`, or stale distribution artifacts.

## Version And Changelog Check

Before any development freeze or final stable matrix, the candidate commit must
make the relevant identity fields agree:

```text
lib/GobanFTP.pm $VERSION
Changes top heading and date
expected tarball name
chosen Git tag or explicit no-tag final-candidate identity
README current-line wording
release record template below
```

For the active v1.0 final candidate, `Changes` must say
`1.000  2026-05-19`, `lib/GobanFTP.pm` must declare `1.000`, the expected
tarball is `GobanFTP-1.000.tar.gz`, and `Git tag` remains `none` until the
final stable matrix and external artifact record are complete.

## MANIFEST Audit

Required included paths:

```text
docs/P14_RELEASE_MANIFEST_AND_TAG_PLAN.md
docs/P14_RELEASE_GATE.md
docs/V1_DOD.md
docs/PROTOCOL.md
docs/PROFILES.md
docs/GRAMMAR.md
docs/ATTACKS.md
docs/DIAGNOSTICS.md
docs/RULES.md
docs/SOURCE_ART.md
docs/BUILD.md
docs/ROADMAP.md
README.md
Changes
Makefile.PL
MANIFEST.SKIP
cpanfile
lib/**
script/**
oracle/goban.pl
examples/fixtures/**
t/**
t/fixtures/attacks/tmp-poison/tmp/pending.part
```

`MANIFEST` itself must be stable in the source commit, but it is not required to
be a member of the generated tarball.

Required excluded paths:

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

`META.json` and `META.yml` are excluded from the source `MANIFEST` and source
commit when they are local generated residue. `make dist` may generate fresh
CPAN metadata inside the distribution archive from `Makefile.PL`; that generated
archive metadata is allowed. `MYMETA.*` remains local configure residue and
must not appear in the archive.

## Development Freeze Matrix

This command set was run from fresh clean checkouts of `1.000_001` development
candidate commits. It produced development tarballs and must not be treated as
the final stable v1.0 release matrix. The final-candidate route uses the same
gates with `dist=GobanFTP-1.000.tar.gz` from the `1.000` identity.

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
prove -lr t/v1-golden-vectors.t
prove -lr t/v1-signed-hmac.t
prove -lr t/v1-signed-hmac-golden-vectors.t
prove -lr t/auth-hmac-key.t t/cli-auth-hmac.t
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
dist=GobanFTP-1.000_001.tar.gz
test -f "$dist"
test "$(find . -maxdepth 1 -name 'GobanFTP-*.tar.gz' -print | wc -l)" -eq 1
sha256sum "$dist"
ls -lh "$dist"
tar -tzf "$dist" | rg 'docs/P14_RELEASE_MANIFEST_AND_TAG_PLAN\.md'
tar -tzf "$dist" | rg 'docs/P14_RELEASE_GATE\.md'
tar -tzf "$dist" | rg 't/fixtures/vectors/v1-non-consensus-poison\.jsonl'
tar -tzf "$dist" | rg 't/fixtures/v1/cross-substrate/minimal/ftp-goftp1/listing\.names'
tar -tzf "$dist" | rg 't/fixtures/attacks/tmp-poison/tmp/pending\.part'
tar -xOzf "$dist" --wildcards '*/t/fixtures/vectors/v1-non-consensus-poison.jsonl' | rg 'ftp-listing-shadow-poison-public-vector'
tar -xOzf "$dist" --wildcards '*/t/fixtures/vectors/v1-non-consensus-poison.jsonl' | rg 'core-bad-signature-public-vector'
! tar -tzf "$dist" | rg '^[^/]+/docs/SESSION_RESTORE\.md$'
! tar -tzf "$dist" | rg '^[^/]+/(?:blib|_Inline)(?:/|$)'
! tar -tzf "$dist" | rg '^[^/]+/MYMETA\.(?:json|yml)$'
! tar -tzf "$dist" | rg '^[^/]+/pm_to_blib$'
! tar -tzf "$dist" | rg '^[^/]+/GobanFTP-[0-9][^/]*\.tar\.gz$'
! tar -tzf "$dist" | rg '^[^/]+/GobanFTP-[0-9][^/]*/'

GOBANFTP_RULES_DISABLE_C=1 GOBANFTP_RULES_ENGINE=perl make disttest
make distcheck
```

For the final stable v1.0 route, run the same matrix from the current
final-candidate identity with `dist=GobanFTP-1.000.tar.gz`. Do not use
`GobanFTP-*.tar.gz` as the artifact identity in the final release record.

The latest `1.000_001` development freeze result for candidate commit
`1f5f646921f675c93e25819cb3cf3652f5d6bebe` is recorded in
`docs/P14_RELEASE_GATE.md`. A passing development freeze matrix is not the
final stable v1.0 release record; the final route still requires a fresh final
matrix and an external artifact record before any `v1.0` tag.

## Artifact Manifest

The external release record must include:

```text
exact tarball filename
sha256
byte size
tar entry count
top-level archive prefix
source commit
tag target commit
MANIFEST sha256
build command
Perl version
matrix gate summary with pass/skip counts
live FTP status
Inline::C status
deferred claims
```

The source commit and tag target commit must be identical. Dry-run tarballs are
never reused as final artifacts.

If live FTP is included in the final release claim, also run
`script/live-ftp-smoke` against its disposable localhost server. If it is not
run, the release record must say that live FTP was skipped and that mock FTP plus
the local smoke path are the shipped proof.

## Claim Audit

Allowed current v1.0 final-candidate claims before the final release-freeze:

```text
GOFTP/1 descriptor and direct events/ basenames remain authoritative
event ids remain filename-context derived
event_set_root is stable across accepted event basenames
local, FTP, Git-tree, DNS-record, and WebDAV runtime read paths are implemented
Git-like and DNS-like fixture/read-normalizer proofs remain present
FTP listing-shadow public poison-vector evidence is fixture/listing evidence
only, not live FTP, RETR, SIZE, MDTM, auth, integrity, or publish behavior
signed-hmac-goftp1 has an explicit per-event HMAC acceptance gate
v1 keygen and v1 attest provide verifier-local signed-HMAC operation support without changing unsigned replay
public key and trust fixture reports are advisory outside signed profiles
text, static HTML, and static terminal witness surfaces are read-only displays
local play --tui keyboard/mouse input is implemented as a non-consensus input/display layer over existing publish callbacks
source art is runnable and non-consensus
the arch-gate motif is comment-only source art, not witness output or protocol input
P14/v1.0 final candidate is active
v1.0 remains unreleased until the final release-freeze matrix passes
```

Forbidden final-release claims unless additional code and gates land first:

```text
v1.0 is complete
P14 is complete
hosted Web UI is complete
cross-terminal TUI compatibility matrix is complete
Git publish support is implemented
live DNS / AXFR / DNSSEC trust / provider API support is implemented
DNS dynamic update or DNS record publishing is implemented
production key lifecycle is complete
publish authentication policy is complete
publish auth is complete
production publish signing or authorization is implemented
final scoring/result events are part of GOFTP/1
source art, Web, TUI, C, or asm-like surfaces own replay truth
the arch-gate motif claims Arch Linux affiliation, endorsement, package
identity, project logo, protocol name, profile id, or release artifact identity
```

Before tagging, scan README, Changes, docs/CLI.md, docs/ROADMAP.md,
docs/V1_DOD.md, docs/P14_RELEASE_GATE.md,
docs/P14_RELEASE_MANIFEST_AND_TAG_PLAN.md, docs/SESSION_RESTORE.md, tag text,
and the external artifact record for these
forbidden claims. A forbidden claim is a release blocker even if the tests pass.
The `t/p14-claim-audit.t` gate guards the current source-tree release text
against accidental over-claims; passing it is not a P14/v1.0 completion claim.

## Tag Procedure

Use an annotated tag after the final matrix and artifact record are complete:

For the final stable v1.0 identity:

```sh
git rev-parse --verify v1.0 >/dev/null 2>&1 && exit 1 || true
git tag -a v1.0 -m "GobanFTP v1.0 / package 1.000 P14 proof machine; artifact sha256 <sha256>"
test "$(git rev-parse v1.0^{commit})" = "$(git rev-parse HEAD)"
git cat-file -t v1.0 | grep '^tag$'
```

Do not tag a dirty worktree. Do not tag before `Changes`, `$VERSION`, and the
artifact record agree.

After tagging locally, verify:

```sh
git status --short
git show --stat --oneline --decorate v1.0
```

Do not tag before the final stable matrix and external artifact record are
complete.

## External Release Record Template

Copy this into the annotated tag message or release notes. Do not fill it inside
this source file, because this file is included in the tarball.

```text
candidate commit:      <sha>
git tag:               <v1.0>
Perl version:          <1.000>
Changes heading:       <version YYYY-MM-DD>
tarball:               <GobanFTP-version.tar.gz>
tarball sha256:        <sha256>
tarball size:          <size>
MANIFEST check:        <clean>
matrix result:         <PASS>
live FTP:              <run or skipped, with reason>
Inline::C:             <available, skipped, or optional fallback>
deferred claims:       <explicit list>
```

Until an external record is filled and attached to the tag or release notes, this
file is a release plan, not a release record.
