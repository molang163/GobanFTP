# P14 Release Gate Evidence

Status: final v1.0/package 1.000 release-source evidence.

Date: 2026-05-19
Perl package version: `1.000`
Changes heading: `1.000  2026-05-19`
Expected source distribution: `GobanFTP-1.000.tar.gz`

## Scope

This file records the source-tree evidence and gates for the v1.0/P14 proof
machine. The final tarball hash is intentionally not stored in source; it
belongs in the annotated tag message or release notes generated outside the
tarball.

The v1.0/package 1.000 source proves the listing-first boundary across local,
FTP, read-only Git tree, read-only DNS record-file admission, WebDAV, and
explicit verifier-local signed-HMAC witness profiles. `GOFTP/1` remains
descriptor-basename plus direct `events/` basename consensus.

## Final Source Gates

The release source is expected to pass this matrix from a clean checkout:

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

## Evidence Summary

- Package identity is `1.000`; the expected source distribution name is
  `GobanFTP-1.000.tar.gz`.
- Targeted source claim audit run on 2026-05-19:
  `prove -lr t/p14-claim-audit.t` PASS, `Files=1, Tests=17`.
- `t/p14-claim-audit.t` is part of the release-source gate and scans
  release-facing text for forbidden over-claims.
- `MANIFEST` is expected to include release docs, fixtures, test gates, and
  public vectors while excluding local resume notes, build residue, nested
  distributions, and VCS internals.
- FTP publish coverage for v1.0 is mock/CLI coverage of the declared
  `ftp-goftp1` tmp+rename path; `script/live-ftp-smoke` is optional disposable
  live smoke coverage.
- Optional `Inline::C` acceleration may be present or skipped; the Perl rules
  engine remains the release proof path.

## Deferred Claims

v1.0/package 1.000 does not claim Git publish, Git remote fetch, live FTP auth,
live FTP integrity, production FTP deployment safety, live DNS, AXFR, DNSSEC
trust, provider API support, dynamic update, DNS record publishing, hosted Web
UI, production key lifecycle completion, publish auth completion, real writer
authorization, complete JSON output for every command, complete signed/auth
diagnostics coverage, complete public attack coverage, or final scoring/result
events.

Read-only Git tree and DNS record-file admission are implemented runtime read
boundaries. Static HTML and static terminal witness output are read-only
inspection surfaces. Local `play --tui` is a non-consensus input/display layer.
