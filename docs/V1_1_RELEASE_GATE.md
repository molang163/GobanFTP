# GobanFTP v1.1 Release Gate Candidate

Status: v1.1 integration candidate only; not released.
Date: 2026-05-25 Asia/Shanghai

This document records the source-tree gate intended for manual review of the
v1.1 hardening candidate. It is not a tag plan, not a publish plan, and not a
distribution build record. This candidate review must not tag, push, upload,
deploy, call real FTP/WebDAV/DNS/Git writers, run `make dist`, run
`make disttest`, or run `make distcheck`.

## Scope

The v1.1 candidate keeps `GOFTP/1` consensus unchanged: the game descriptor
basename and accepted direct child event basenames remain the replay truth. The
candidate hardens admission, storage confirmation, diagnostics, bounded input
handling, and release-facing claims around that existing boundary.

The only P2 runtime addition accepted into this candidate is the local
loopback-only showcase preview helper. The P2.1 static showcase navigation
polish is generated-bundle/static HTML only: it adds local file links and
same-document fragment navigation without adding runtime, hosted UI, deploy,
provider, or network behavior. Remaining P2 stretch work is deferred and has no
hosted UI, provider, production auth, Git/DNS publishing, scoring/result, or
release/deploy claim.

This candidate is still source for manual review. The current public README
release line remains `v1.0.1/package 1.001` until a maintainer performs a
separate release process outside this candidate review.

## Candidate Evidence Matrix

The candidate review gate uses local, fixture-only commands:

```sh
perl -c oracle/goban.pl
perl oracle/goban.pl --smoke

perl Makefile.PL
GOBANFTP_RULES_DISABLE_C=1 GOBANFTP_RULES_ENGINE=perl make test
GOBANFTP_RULES_ENGINE=shadow make test
prove -lr t

GOBANFTP_REQUIRE_SYMLINK_TESTS=1 prove -l t/store-webdav-mock.t t/store-ftp-mock.t t/store-dns-record.t t/profile-adapter.t t/store-local.t t/create-game.t t/projection-rebuild.t t/cli-auth-hmac.t t/witness-api.t t/store-config.t t/cli-auth-publish-token.t
prove -l t/store-webdav-mock.t t/store-dns-record.t t/store-ftp-mock.t t/cli-auth-hmac.t t/cli-auth-publish-token.t t/store-config.t
prove -l t/v1-conformance-boundary.t t/v1-cross-substrate.t t/v1-cli-compare.t t/v1-golden-vectors.t t/v1-attack-fixtures.t t/v1-profile-attack-fixtures.t
prove -l t/json-helper.t t/cli-config-doctor.t t/publish-result-json.t t/auth-boundary.t t/showcase-v1_1.t t/showcase-preview.t
prove -l t/v1-claim-audit.t t/ci-source-release-gate.t t/readme-localization.t t/dist-manifest-hygiene.t
```

The candidate gate intentionally omits release packaging commands. Distribution
creation and release tagging are follow-up maintainer actions, not candidate
review actions.

## JSON Contract

The v1.1 candidate has only command-scoped opt-in JSON. Existing public JSONL
fixture and signed-HMAC rows keep their existing record contracts. There is no
global JSON mode and no complete JSON mode for every command.

Every opt-in v1.1 JSON document must include both:

```text
schema = gobanftp.<name>.v1
version = 1.1
```

JSON rendering must use structured data, not stdout re-parsing. Secrets must
not appear in JSON, JSONL, key/value stdout, diagnostics, debug bundles, release
notes, or gate evidence.

Default key/value stdout remains the compatibility surface for CLI scripting in
this candidate.

## Claim Audit

| Claim | Evidence Command | Test File | Non-Goal | Status |
| --- | --- | --- | --- | --- |
| WebDAV listing confirmation is hardened. | `prove -l t/store-webdav-mock.t t/webdav-cli-parity.t` | `t/store-webdav-mock.t` | Does not claim live WebDAV server behavior, lock semantics, or production transport safety. | CANDIDATE |
| DNS record-file parsing rejects poisoning cases. | `prove -l t/store-dns-record.t t/profile-adapter.t` | `t/store-dns-record.t` | Does not claim live DNS resolver, AXFR, DNSSEC, provider API, dynamic update, or DNS publishing. | CANDIDATE |
| Local store paths reject static symlink components. | `GOBANFTP_REQUIRE_SYMLINK_TESTS=1 prove -l t/store-local.t t/create-game.t t/projection-rebuild.t` | `t/store-local.t` | Does not claim OS sandboxing, same-permission concurrent rename-race protection, Windows junction coverage, or safety outside declared local store/projection operations. | CANDIDATE |
| FTP publish confirmation uses exact basename checks. | `prove -l t/store-ftp-mock.t t/ftp-cli-parity.t` | `t/store-ftp-mock.t` | Does not claim live FTP auth, RETR, SIZE, MDTM, integrity, or production FTP deployment safety. | CANDIDATE |
| Auth preflight can block explicitly enabled publish. | `prove -l t/publish-auth-preflight.t t/cli-auth-publish-token.t t/v1-profile-publish-fixtures.t` | `t/publish-auth-preflight.t` | Does not claim production writer authorization or production key lifecycle. | CANDIDATE |
| Auth is not production writer authorization. | `prove -l t/cli-auth-hmac.t t/cli-auth-publish-token.t t/readme-localization.t` | `t/cli-auth-hmac.t` | Does not claim production auth, policy completeness, or real credential management. | CANDIDATE |
| Store capability and doctor JSON are scoped and dry-run by default. | `prove -l t/store-config.t t/cli-config-doctor.t t/json-helper.t` | `t/cli-config-doctor.t` | Does not claim live remote service health, credential validity, or provider write safety. | CANDIDATE |
| Publish result JSON exposes candidate/store/auth state without secrets. | `prove -l t/publish-result-json.t t/publish-auth-preflight.t` | `t/publish-result-json.t` | Does not claim a complete JSON mode for every command or production writer authorization. | CANDIDATE |
| Auth boundary metadata keeps fixture preflight separate from production authorization. | `prove -l t/auth-boundary.t t/publish-auth-preflight.t` | `t/auth-boundary.t` | Does not claim production auth, account identity binding, or public-key signer authorization for HMAC publish. | CANDIDATE |
| Compact live watch is recordable and still listing-derived. | `prove -l t/play-watch.t` | `t/play-watch.t` | Does not claim live truth, fork winner selection, or replay inputs beyond direct event basenames. | CANDIDATE |
| Static showcase generation is local fixture output only. | `prove -l t/showcase-v1_1.t t/static-witness-specimen.t` | `t/showcase-v1_1.t` | Generated bundle is static; optional P2 loopback preview helper is local-only/read-only and not hosted UI/deploy. | CANDIDATE |
| Static showcase navigation polish is generated-bundle-only. | `prove -l t/showcase-v1_1.t t/v1-cli-witness-surface-golden.t t/v1-claim-audit.t` | `t/showcase-v1_1.t` | Does not claim hosted Web UI, browser application, server deployment, provider deploy, network fetch, or production network service. | CANDIDATE |
| P2 local showcase preview helper is loopback-only and read-only. | `prove -l t/showcase-preview.t t/showcase-v1_1.t t/v1-claim-audit.t` | `t/showcase-preview.t` | Does not claim hosted Web UI, browser application, server deployment, provider deploy, or production network service. | CANDIDATE |
| Static HTML/Web projection is not hosted Web UI. | `prove -l t/static-witness-specimen.t t/readme-localization.t` | `t/static-witness-specimen.t` | Does not claim a hosted Web UI, browser application, or production network service. | CANDIDATE |
| Git and DNS remain read-only runtime substrates. | `prove -l t/store-git-tree.t t/store-dns-record.t t/profile-adapter.t` | `t/store-git-tree.t` | Does not claim Git publish, Git remote fetch, DNS dynamic update, or provider writes. | CANDIDATE |
| Scoring/result events remain outside GOFTP/1. | `prove -l t/readme-localization.t t/v1-claim-audit.t` | `t/v1-claim-audit.t` | Does not claim a complete scoring/result system. | CANDIDATE |
| Input size and timeout boundaries produce stable public diagnostics. | `prove -l t/store-webdav-mock.t t/store-dns-record.t t/store-ftp-mock.t t/cli-auth-hmac.t t/cli-auth-publish-token.t t/store-config.t` | `t/store-config.t` | Does not claim streaming transport read caps or real network service SLAs. | CANDIDATE |
| Cross-substrate roots and replay stay equal across Local, FTP, Git, DNS, and WebDAV fixtures. | `prove -l t/v1-conformance-boundary.t t/v1-cross-substrate.t t/v1-cli-compare.t t/v1-golden-vectors.t` | `t/v1-conformance-boundary.t` | Does not expand GOFTP/1 consensus inputs or claim real remote service writes. | CANDIDATE |

## Deferred And Non-Goals

- The generated showcase bundle is static; optional P2 loopback preview helper
  is local-only/read-only and not hosted UI/deploy.
- Remaining P2 stretch work is deferred: no GitHub Pages/static hosting, TUI
  GIF/asciinema asset, broader Web observatory work beyond the accepted static
  generated-bundle navigation polish, sanitized debug bundle expansion, and no
  result/scoring profile in this candidate.
- No hosted Web UI, browser application, server deployment, provider deploy, or
  normal online Go game server claim.
- No production auth, production writer authorization, or production key
  lifecycle claim.
- No live DNS, AXFR, DNSSEC trust, provider API, dynamic update, or DNS record
  publishing claim.
- No Git publishing or Git remote fetch claim.
- No production FTP deployment-safety claim.
- No complete JSON output mode for every command.
- No complete scoring/result system in `GOFTP/1`.
- No release, tag, push, upload, deploy, or distribution artifact is produced
  by this candidate gate.
- Local symlink hardening is not an OS sandbox, same-permission concurrent
  rename-race protection, or Windows junction coverage.
