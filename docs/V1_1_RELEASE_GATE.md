# GobanFTP v1.1.0-beta.1 Release Gate

Status: v1.1.0-beta.1 / package 1.100_001 beta source gate.
Date: 2026-05-25 Asia/Shanghai

This document records the source-tree gate intended for manual review of the
v1.1.0-beta.1 hardening and showcase beta. It is not a tag plan, not a publish plan, and not a
distribution build record. This beta review must not tag, push, upload,
deploy, call real FTP/WebDAV/DNS/Git writers, run `make dist`, run
`make disttest`, or run `make distcheck`.

## Scope

The v1.1.0-beta.1 beta keeps `GOFTP/1` consensus unchanged: the game descriptor
basename and accepted direct child event basenames remain the replay truth. The
beta hardens admission, storage confirmation, diagnostics, bounded input
handling, and release-facing claims around that existing boundary.

The only P2 runtime addition accepted into this beta is the local
loopback-only showcase preview helper on supported local platforms. The P2.1
static showcase navigation polish is generated-bundle/static HTML only: it adds
local file links and same-document fragment navigation without adding runtime,
hosted UI, deploy, provider, or network behavior. Remaining P2 stretch work is
deferred and has no hosted UI, provider, production auth, Git/DNS publishing,
scoring/result, or release/deploy claim.

This beta source gate covers the public source line for
`v1.1.0-beta.1/package 1.100_001`. Distribution creation, upload, and tag
publication remain separate maintainer actions.

## Beta Evidence Matrix

The beta source gate uses local, fixture-only commands. Every source-gate
evidence command must run through `gate_env` so live-provider and writer
environment cannot leak into source evidence:

```sh
gate_env() {
  env \
    -u GOBANFTP_FTP_TEST \
    -u GOBANFTP_FTP_HOST \
    -u GOBANFTP_FTP_USER \
    -u GOBANFTP_FTP_PASSWORD \
    -u GOBANFTP_FTP_ROOT \
    -u GOBANFTP_WEBDAV_URL \
    -u GOBANFTP_WEBDAV_USER \
    -u GOBANFTP_WEBDAV_PASSWORD \
    -u GOBANFTP_WEBDAV_TOKEN \
    -u GOBANFTP_DNS_RECORD_FILE \
    -u GOBANFTP_GIT_REPO \
    -u GOBANFTP_STORE \
    "$@"
}
```

The forbidden source/archive residue set is: `Makefile`, `Makefile.old`,
`META.json`, `META.yml`, `MYMETA.*`, `pm_to_blib`, `blib/`, `_Inline/`,
`docs/V1_1_UPDATE_CHECKLIST.md`, `docs/references/`, `docs/SESSION_RESTORE.md`,
nested `GobanFTP-*` distributions, and non-fixture `.bak`, `.tmp`, and `.part`
scratch files.

### Uncommitted Worktree Candidate

Use this phase while the reviewed candidate still includes uncommitted worktree
changes. Before those changes are committed, `git archive HEAD` describes the
previous committed tree, not the current candidate, so it must not be used as
current-candidate evidence.

```sh
gate_env perl -c oracle/goban.pl
gate_env perl oracle/goban.pl --smoke

gate_env prove -lr t
gate_env env GOBANFTP_REQUIRE_SYMLINK_TESTS=1 prove -l t/store-webdav-mock.t t/store-ftp-mock.t t/store-dns-record.t t/profile-adapter.t t/store-local.t t/create-game.t t/projection-rebuild.t t/cli-auth-hmac.t t/witness-api.t t/store-config.t t/cli-auth-publish-token.t
gate_env prove -l t/store-webdav-mock.t t/store-dns-record.t t/store-ftp-mock.t t/cli-auth-hmac.t t/cli-auth-publish-token.t t/store-config.t
gate_env prove -l t/v1-conformance-boundary.t t/v1-cross-substrate.t t/v1-cli-compare.t t/v1-golden-vectors.t t/v1-attack-fixtures.t t/v1-profile-attack-fixtures.t
gate_env prove -l t/json-helper.t t/cli-config-doctor.t t/publish-result-json.t t/auth-boundary.t t/showcase-v1_1.t t/showcase-preview.t
gate_env prove -l t/v1-claim-audit.t t/ci-source-release-gate.t t/readme-localization.t t/dist-manifest-hygiene.t

gate_env git diff --check
gate_env perl -MExtUtils::Manifest=fullcheck -e 'my ($missing, $extra) = fullcheck(); exit(@$missing || @$extra ? 1 : 0)'
gate_env perl -MExtUtils::Manifest=maniread -E 'say for sort keys %{ maniread() }' | gate_env perl -ne 'chomp; next if m{^t/fixtures/}; die "forbidden source entry $_\n" if m{^(?:Makefile(?:[.]old)?$|META[.](?:json|yml)$|MYMETA[.](?:json|yml)$|pm_to_blib$|(?:blib|_Inline)(?:/|$)|docs/references(?:/|$)|docs/V1_1_UPDATE_CHECKLIST[.]md$|docs/SESSION_RESTORE[.]md$|GobanFTP-[0-9][^/]*/|GobanFTP-[0-9][^/]*[.]tar[.]gz$)} || m{[.](?:bak|tmp|part)$}'
```

A disposable worktree copy is the MakeMaker/shadow evidence path for an
uncommitted candidate. Run it only in a one-time copy made from the reviewed
worktree:

```sh
tmpdir=$(mktemp -d)
gate_env perl -MExtUtils::Manifest=maniread -E 'say for sort keys %{ maniread() }' | gate_env tar -T - -cf - | gate_env tar -x -C "$tmpdir" -f -
(
  cd "$tmpdir"
  gate_env perl Makefile.PL
  gate_env env GOBANFTP_RULES_DISABLE_C=1 GOBANFTP_RULES_ENGINE=perl make test
  gate_env env -u GOBANFTP_RULES_DISABLE_C GOBANFTP_RULES_ENGINE=shadow make test
)
rm -rf "$tmpdir"
```

### Committed HEAD Candidate

Use this phase only after all reviewed changes have been committed and
`git status --short` is clean. At that point `git archive HEAD` is valid
current-candidate evidence.

```sh
gate_env sh -c 'test -z "$(git status --short)"'
gate_env git diff --check
gate_env perl -MExtUtils::Manifest=fullcheck -e 'my ($missing, $extra) = fullcheck(); exit(@$missing || @$extra ? 1 : 0)'
gate_env git archive --format=tar HEAD | gate_env tar -tf - | gate_env perl -ne 'chomp; next if m{^t/fixtures/}; die "forbidden archive entry $_\n" if m{^(?:Makefile(?:[.]old)?$|META[.](?:json|yml)$|MYMETA[.](?:json|yml)$|pm_to_blib$|(?:blib|_Inline)(?:/|$)|docs/references(?:/|$)|docs/V1_1_UPDATE_CHECKLIST[.]md$|docs/SESSION_RESTORE[.]md$|GobanFTP-[0-9][^/]*/|GobanFTP-[0-9][^/]*[.]tar[.]gz$)} || m{[.](?:bak|tmp|part)$}'

tmpdir=$(mktemp -d)
gate_env git archive --format=tar HEAD | gate_env tar -x -C "$tmpdir"
(
  cd "$tmpdir"
  gate_env perl Makefile.PL
  gate_env env GOBANFTP_RULES_DISABLE_C=1 GOBANFTP_RULES_ENGINE=perl make test
  gate_env env -u GOBANFTP_RULES_DISABLE_C GOBANFTP_RULES_ENGINE=shadow make test
)
rm -rf "$tmpdir"
```

Failure conditions: any non-zero evidence command in the applicable candidate
phase fails the gate; any `ExtUtils::Manifest::fullcheck` missing or extra file
fails the gate; any forbidden worktree source entry or committed archive entry
fails the gate; any enabled live-provider or writer environment in a source-gate
command fails the gate; and any tag, push, upload, deploy, distribution build,
or real provider write action fails the gate.

The beta source gate intentionally omits release packaging commands.
Distribution creation and release tagging are follow-up maintainer actions, not
beta source-gate actions.

## JSON Contract

The v1.1.0-beta.1 beta has only command-scoped opt-in JSON. Existing public JSONL
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
this beta.

## Claim Audit

| Claim | Evidence Command | Test File | Non-Goal | Status |
| --- | --- | --- | --- | --- |
| WebDAV listing confirmation is hardened. | `prove -l t/store-webdav-mock.t t/webdav-cli-parity.t` | `t/store-webdav-mock.t` | Does not claim live WebDAV server behavior, lock semantics, or production transport safety. | BETA |
| DNS record-file parsing rejects poisoning cases. | `prove -l t/store-dns-record.t t/profile-adapter.t` | `t/store-dns-record.t` | Does not claim live DNS resolver, AXFR, DNSSEC, provider API, dynamic update, or DNS publishing. | BETA |
| Local store paths reject static symlink components. | `GOBANFTP_REQUIRE_SYMLINK_TESTS=1 prove -l t/store-local.t t/create-game.t t/projection-rebuild.t` | `t/store-local.t` | Does not claim OS sandboxing, same-permission concurrent rename-race protection, Windows junction coverage, or safety outside declared local store/projection operations. | BETA |
| FTP publish confirmation uses exact basename checks. | `prove -l t/store-ftp-mock.t t/ftp-cli-parity.t` | `t/store-ftp-mock.t` | Does not claim live FTP auth, RETR, SIZE, MDTM, integrity, or production FTP deployment safety. | BETA |
| Auth preflight can block explicitly enabled publish. | `prove -l t/publish-auth-preflight.t t/cli-auth-publish-token.t t/v1-profile-publish-fixtures.t` | `t/publish-auth-preflight.t` | Does not claim production writer authorization or production key lifecycle. | BETA |
| Auth is not production writer authorization. | `prove -l t/cli-auth-hmac.t t/cli-auth-publish-token.t t/readme-localization.t` | `t/cli-auth-hmac.t` | Does not claim production auth, policy completeness, or real credential management. | BETA |
| Store capability and doctor JSON are scoped and dry-run by default. | `prove -l t/store-config.t t/cli-config-doctor.t t/json-helper.t` | `t/cli-config-doctor.t` | Does not claim live remote service health, credential validity, or provider write safety. | BETA |
| Publish result JSON exposes candidate/store/auth state without secrets. | `prove -l t/publish-result-json.t t/publish-auth-preflight.t` | `t/publish-result-json.t` | Does not claim a complete JSON mode for every command or production writer authorization. | BETA |
| Auth boundary metadata keeps fixture preflight separate from production authorization. | `prove -l t/auth-boundary.t t/publish-auth-preflight.t` | `t/auth-boundary.t` | Does not claim production auth, account identity binding, or public-key signer authorization for HMAC publish. | BETA |
| Compact live watch is recordable and still listing-derived. | `prove -l t/play-watch.t` | `t/play-watch.t` | Does not claim live truth, fork winner selection, or replay inputs beyond direct event basenames. | BETA |
| Static showcase generation is local fixture output only. | `prove -l t/showcase-v1_1.t t/static-witness-specimen.t` | `t/showcase-v1_1.t` | Generated bundle is static; optional P2 loopback preview helper is local-only/read-only and not hosted UI/deploy. | BETA |
| Static showcase navigation polish is generated-bundle-only. | `prove -l t/showcase-v1_1.t t/v1-cli-witness-surface-golden.t t/v1-claim-audit.t` | `t/showcase-v1_1.t` | Does not claim hosted Web UI, browser application, server deployment, provider deploy, network fetch, or production network service. | BETA |
| P2 local showcase preview helper is loopback-only and read-only. | `prove -l t/showcase-preview.t t/showcase-v1_1.t t/v1-claim-audit.t` | `t/showcase-preview.t` | Supported local platforms only; does not claim hosted Web UI, browser application, server deployment, provider deploy, production network service, or preview support on platforms missing required local safety/process primitives. | BETA |
| Static HTML/Web projection is not hosted Web UI. | `prove -l t/static-witness-specimen.t t/readme-localization.t` | `t/static-witness-specimen.t` | Does not claim a hosted Web UI, browser application, or production network service. | BETA |
| Git and DNS remain read-only runtime substrates. | `prove -l t/store-git-tree.t t/store-dns-record.t t/profile-adapter.t` | `t/store-git-tree.t` | Does not claim Git publish, Git remote fetch, DNS dynamic update, or provider writes. | BETA |
| Scoring/result events remain outside GOFTP/1. | `prove -l t/readme-localization.t t/v1-claim-audit.t` | `t/v1-claim-audit.t` | Does not claim a complete scoring/result system. | BETA |
| Input size and timeout boundaries produce stable public diagnostics. | `prove -l t/store-webdav-mock.t t/store-dns-record.t t/store-ftp-mock.t t/cli-auth-hmac.t t/cli-auth-publish-token.t t/store-config.t` | `t/store-config.t` | Does not claim streaming transport read caps or real network service SLAs. | BETA |
| Cross-substrate roots and replay stay equal across Local, FTP, Git, DNS, and WebDAV fixtures. | `prove -l t/v1-conformance-boundary.t t/v1-cross-substrate.t t/v1-cli-compare.t t/v1-golden-vectors.t` | `t/v1-conformance-boundary.t` | Does not expand GOFTP/1 consensus inputs or claim real remote service writes. | BETA |

## Deferred And Non-Goals

- The generated showcase bundle is static; optional P2 loopback preview helper
  is local-only/read-only and not hosted UI/deploy.
- Preview helper support is limited to supported local platforms with the
  required local safety/process primitives; unsupported platforms should report
  unsupported/skip and must not be used as release evidence.
- Remaining P2 stretch work is deferred: no GitHub Pages/static hosting, TUI
  GIF/asciinema asset, broader Web observatory work beyond the accepted static
  generated-bundle navigation polish, sanitized debug bundle expansion, and no
  result/scoring profile in this beta.
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
  by this beta gate.
- Local symlink hardening is not an OS sandbox, same-permission concurrent
  rename-race protection, or Windows junction coverage.
