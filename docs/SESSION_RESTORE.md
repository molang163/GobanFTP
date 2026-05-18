# Session Restore

One-line resume command:

```text
恢复 GobanFTP 工作：读取 docs/SESSION_RESTORE.md，按 Next Step 继续。
```

## Current State

Repository: `/run/media/molang/linux-dev/GobanFTP`

Current HEAD expectation:

```text
at or after:
- feat: add fixture keyid command
```

Confirm the latest commit with `git log --oneline -5` when resuming.

## Recent Completed Work

```text
HEAD feat: add fixture keyid command
HEAD test: add WebDAV publish failure fixture
HEAD test: add git tree metadata poison fixture
HEAD test: add signed HMAC injected event fixture
HEAD docs: rewrite README as P14 showcase entrypoint
81e0fee test: add dns owner poison profile attack
c763103 test: add bad mtime attack fixture
cab85ad test: add v1 cross-substrate validation vectors
0bdbf42 test: add showcase demo smoke gate
ba17df8 test: add signed HMAC game descriptor mismatch fixture
60bc2c7 test: add signed HMAC payload mismatch fixture
fc7f6a2 test: add WebDAV href traversal attack fixture
04dd306 test: add WebDAV profile attack fixture
0faf00e feat: add WebDAV store backend
7884b6c feat: add ruleset seal witness
54d902c feat: add v1 compare CLI
958e47a feat: add v1 witness CLI
```

Key completed boundaries:

- P12a fixture public key identity is implemented through
  `gobanftp v1 keyid --fixture`. It parses public fixture key records, derives
  documented `GOFTP-KEY/1` `k1.` ids, rejects malformed/private-looking records
  with `parse_public_key`, and keeps public key metadata separate from HMAC
  secrets, signatures, trust, and unsigned replay truth.
- WebDAV publish failure now has a fixture and CLI parity gate proving
  existing-final idempotence, delayed `MOVE` visibility, hard `HTTP 423 Locked`
  failure, bounded retries, zero-byte temporary resources, tmp debris exclusion,
  listing-first confirmation, and bearer-token redaction.
- `git-tree-goftp1` now has a profile attack fixture proving commit metadata,
  refs, tags, remotes, mode, object id, object type, object size, `tmp/`,
  sidecar, projection, recursive path, wrong-game path, duplicate entry, and
  checkout-style path surfaces do not change the accepted witness.
- `signed-hmac-goftp1` now has an injected-event fixture: an event basename with
  a valid filename event id reaches the signed profile gate, is rejected for
  `missing_signature`, and the accepted signed chain keeps the same root,
  replay, board, and SGF as the valid baseline.
- README is now a release-shaped showcase entrypoint: it opens with the hard
  GOFTP/1 contract, three-minute proof path, shrine/race demonstration, current
  implemented surfaces, proof gates, and the `v1.0/P14` release-freeze shape
  without claiming P14 is already tagged.
- `signed-hmac-goftp1` now has golden-vector fixtures for valid,
  injected-event, missing, wrong, payload-mismatched, game-descriptor-mismatched,
  untrusted, and malformed attestations.
- CLI witness covers signed-HMAC failure status, stable signature diagnostics,
  and HMAC secret redaction.
- WebDAV profile attack fixtures cover metadata poison and href traversal.
- `bad-mtime` is now a core attack fixture. The harness applies real event-file
  mtimes with `utime`, confirms they were applied, runs CLI verification, and
  confirms the mtimes remain unchanged.
- A showcase smoke gate now locks the public clean shrine, race shrine,
  source-art oracle smoke, and unsigned `local-goftp1` v1 witness path.
- v1 cross-substrate witness vectors now cover minimal, fork, fork-with-ack,
  bad-event-id, future-version, missing-parent, and wrong-player across local,
  FTP, Git-like, DNS-like, and WebDAV-like profiles.
- Unsigned v1 witness golden vectors now freeze profile consensus version,
  adapter id, raw and normalized counts, normalized events, accepted and
  rejected counts, and diagnostic count.
- The DNS profile adapter requires the TXT owner to belong to the current game
  descriptor, and `dns-owner-poison` proves wrong-owner or ownerless TXT records
  cannot smuggle events into the witness.
- Ruleset seal, v1 witness CLI, and v1 compare CLI are already implemented.

## Last Verified

After the fixture keyid command, these passed:

```text
git diff --check
prove -lr t/auth-keyid.t t/cli-auth-keyid.t t/diagnostics-contract.t t/dependency-sync.t t/v1-cli-witness.t t/v1-signed-hmac.t
prove -lr t/v1-profile-publish-fixtures.t t/webdav-cli-parity.t t/store-webdav-mock.t
prove -lr t/profile-adapter.t t/v1-profile-attack-fixtures.t t/v1-cross-substrate.t t/v1-golden-vectors.t
prove -lr t
```

Full test result:

```text
Files=65, Tests=869, all successful.
Live FTP tests were skipped unless GOBANFTP_FTP_TEST=1 is set.
```

## Important Invariants

- Descriptor directory basename and direct `events/` basenames are authoritative.
- Event ids come from canonical filename context, not file bytes.
- `mtime`, file bytes, listing order, entry type, size, sidecar, projections,
  and tmp entries are not replay inputs.
- `event_set_root` is a witness commitment over accepted direct event basenames.
- Signed/auth behavior is explicit profile behavior and must not change unsigned
  `GOFTP/1`.
- Source art, TUI, Web, Inline::C, and asm-like surfaces cannot own truth.

## Next Step

Immediate next implementation:

```text
after showing the README, continue the v1.0 route:
- pick the next small proof gate by multi-agent discussion
- likely candidate is P12b: `gobanftp v1 trust-report --fixture`
- define trust TSV parsing, trusted/rotated/revoked/expired output fields, and
  advisory-vs-signed exit semantics without changing unsigned GOFTP/1 truth
- keep every change behavior-tested and update Changes plus this restore file
```

Likely files:

```text
lib/GobanFTP/Auth/KeyID.pm
lib/GobanFTP/Auth/TrustReport.pm
lib/GobanFTP/CLI.pm
lib/GobanFTP/Diagnostics.pm
t/fixtures/auth/
t/cli-auth-keyid.t
t/diagnostics-contract.t
docs/PROFILES.md
docs/CLI.md
docs/DIAGNOSTICS.md
Changes
docs/SESSION_RESTORE.md
```

## Restore Procedure

When resuming:

1. Read `AGENTS.md`.
2. Read this file.
3. Run `git status --short`.
4. Confirm HEAD includes `feat: add fixture keyid command`.
5. If the user asks to continue, open multi-agent discussion first, then choose
   one small executable step.
