# P14 Release Manifest And Tag Plan

Status: planning gate only. This is not a tag, not a release artifact, not a
release-ready declaration, and not a v1.0 completion claim.

This document fixes the final release identity and artifact checks that must be
resolved after the P14 release-gate dry run in `docs/P14_RELEASE_GATE.md`.

## Current Identity State

The current public release line has three names that must not be confused:

```text
public Git tag:      v0.1
Perl package version: 0.001
project milestone:   v0.1 hardening/showcase
```

The v0.2 release identity candidate has:

```text
Changes heading:       0.002  2026-05-18
lib/GobanFTP.pm:       $VERSION = 0.002
expected tarball name: GobanFTP-0.002.tar.gz
project target:        v1.0/P14 proof machine
```

That state is a release-candidate identity. It is still not a tag, and it is not
the final artifact record.

## Recommended Next Identity

The recommended next publishable identity is:

```text
Git tag:          v0.2
Perl version:     0.002
Changes heading:  0.002  YYYY-MM-DD
tarball name:     GobanFTP-0.002.tar.gz
release claim:    pre-v1.0/P14 release-route checkpoint, not v1.0
```

Rationale:

```text
Changes carries the v0.2 package-version entry.
lib/GobanFTP.pm declares the package version used by MakeMaker.
The dry-run tarball is GobanFTP-0.001.tar.gz and belongs to the dry run only.
docs/P14_RELEASE_GATE.md is explicit that v1.0 is not ready or tagged.
```

Publishing `v0.2 / package 0.002` lets the project ship the current proof-route
work without pretending the P14/v1.0 release freeze is complete.

## Reserved v1.0 Identity

Use this identity only if a later final P14 claim audit decides the project is
ready to claim v1.0:

```text
Git tag:          v1.0
Perl version:     1.000
Changes heading:  1.000  YYYY-MM-DD
tarball name:     GobanFTP-1.000.tar.gz
release claim:    v1.0/P14 proof machine
```

The `v1.0` route must still satisfy `docs/V1_DOD.md`; the current P14 dry run is
evidence, not the final release record.

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

Before the final matrix, the release identity commit must make these agree:

```text
lib/GobanFTP.pm $VERSION
Changes top heading and date
expected tarball name
chosen Git tag
README current-line wording
release record template below
```

For the recommended `v0.2` release, `Changes` must say
`0.002  2026-05-18`, and `lib/GobanFTP.pm` must declare `0.002`.

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

## Final Matrix

Run from a fresh clean checkout of the candidate commit:

```sh
perl -c oracle/goban.pl
perl oracle/goban.pl --smoke

perl Makefile.PL
GOBANFTP_RULES_DISABLE_C=1 GOBANFTP_RULES_ENGINE=perl make test
GOBANFTP_RULES_ENGINE=shadow make test

prove -lr t
prove -lr t/v1-cross-substrate.t
prove -lr t/v1-attack-fixtures.t
prove -lr t/v1-golden-vectors.t
prove -lr t/v1-signed-hmac.t
prove -lr t/v1-signed-hmac-golden-vectors.t
prove -lr t/profile-registry.t t/profile-adapter.t t/witness-api.t
prove -lr t/diagnostics-contract.t
prove -lr t/rules-flow.t t/rules-superko.t

script/gobanftp v1 witness --profile local-goftp1 --fixture t/fixtures/v1/cross-substrate/minimal
script/gobanftp v1 compare-roots --fixture t/fixtures/v1/cross-substrate/minimal
script/gobanftp v1 compare-replay --fixture t/fixtures/v1/cross-substrate/minimal

make manifest
git diff --exit-code MANIFEST MANIFEST.SKIP

make dist
dist=GobanFTP-0.002.tar.gz
test -f "$dist"
test "$(find . -maxdepth 1 -name 'GobanFTP-*.tar.gz' -print | wc -l)" -eq 1
sha256sum "$dist"
ls -lh "$dist"
tar -tzf "$dist" | rg 'docs/P14_RELEASE_MANIFEST_AND_TAG_PLAN\.md'
tar -tzf "$dist" | rg 'docs/P14_RELEASE_GATE\.md'
tar -tzf "$dist" | rg 't/fixtures/attacks/tmp-poison/tmp/pending\.part'

GOBANFTP_RULES_DISABLE_C=1 GOBANFTP_RULES_ENGINE=perl make disttest
make distcheck
```

If the reserved v1.0 identity is deliberately chosen later, use
`dist=GobanFTP-1.000.tar.gz` instead. Do not use `GobanFTP-*.tar.gz` as the
artifact identity in the final release record.

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

Allowed v0.2 checkpoint claims after the final matrix passes:

```text
GOFTP/1 descriptor and direct events/ basenames remain authoritative
event ids remain filename-context derived
event_set_root is stable across accepted event basenames
local, FTP, and WebDAV runtime stores are implemented
Git-like and DNS-like fixture/read-normalizer proofs are present
signed-hmac-goftp1 has an explicit per-event HMAC acceptance gate
public key and trust fixture reports are advisory outside signed profiles
text, static HTML, and static terminal witness surfaces are read-only displays
source art is runnable and non-consensus
P14/v1.0 has a dry-run gate and remains the next release-freeze target
```

Forbidden final-release claims unless additional code and gates land first:

```text
v1.0 is complete
P14 is complete
hosted Web UI is complete
interactive mouse/keyboard TUI is complete
Git runtime store is implemented
DNS runtime store is implemented
production key lifecycle is complete
publish authentication policy is complete
final scoring/result events are part of GOFTP/1
source art, Web, TUI, C, or asm-like surfaces own replay truth
```

Before tagging, scan README, Changes, tag text, and the external artifact record
for these forbidden claims. A forbidden claim is a release blocker even if the
tests pass.

## Tag Procedure

Use an annotated tag after the final matrix and artifact record are complete:

For the recommended next identity:

```sh
git status --short
git rev-parse --verify v0.2 >/dev/null 2>&1 && exit 1 || true
git tag -a v0.2 -m "GobanFTP v0.2 / package 0.002 pre-v1.0 P14 checkpoint; artifact sha256 <sha256>"
test "$(git rev-parse v0.2^{commit})" = "$(git rev-parse HEAD)"
git cat-file -t v0.2 | grep '^tag$'
```

For the reserved v1.0 identity:

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
git show --stat --oneline --decorate v0.2
```

Use `v1.0` in those commands only if the reserved v1.0 route is deliberately
chosen later.

## External Release Record Template

Copy this into the annotated tag message or release notes. Do not fill it inside
this source file, because this file is included in the tarball.

```text
candidate commit:      <sha>
git tag:               <v0.2 or v1.0>
Perl version:          <0.002 or 1.000>
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
