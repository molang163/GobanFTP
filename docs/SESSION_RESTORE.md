# Session Restore

One-line resume command:

```text
恢复 GobanFTP 工作：读取 docs/SESSION_RESTORE.md，按 Next Step 继续。
```

## Current State

Repository: `/run/media/molang/linux-dev/GobanFTP`

Current HEAD expectation:

```text
at or after the showcase gate commit: test: add showcase demo smoke gate
```

Confirm the latest commit with `git log --oneline -5` when resuming.

## Recent Completed Work

```text
c763103 test: add bad mtime attack fixture
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

- `signed-hmac-goftp1` now has golden-vector fixtures for valid, missing,
  wrong, payload-mismatched, game-descriptor-mismatched, untrusted, and
  malformed attestations.
- CLI witness covers signed-HMAC failure status, stable signature diagnostics,
  and HMAC secret redaction.
- WebDAV profile attack fixtures cover metadata poison and href traversal.
- `bad-mtime` is now a core attack fixture. The harness applies real event-file
  mtimes with `utime`, confirms they were applied, runs CLI verification, and
  confirms the mtimes remain unchanged.
- A showcase smoke gate now locks the public clean shrine, race shrine,
  source-art oracle smoke, and unsigned `local-goftp1` v1 witness path.
- Ruleset seal, v1 witness CLI, and v1 compare CLI are already implemented.

## Last Verified

After the showcase gate commit, these passed:

```text
prove -lr t/showcase-demo.t
prove -lr t/showcase-demo.t t/example-ftp-shrine.t t/example-ftp-race-shrine.t t/source-art.t t/v1-cli-witness.t t/witness-api.t t/v1-cross-substrate.t
prove -lr t
```

Full test result:

```text
Files=62, Tests=808, all successful.
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
expand v1 cross-substrate golden vectors in a small batch:
- future-version
- missing-parent
- wrong-player
```

Likely files:

```text
t/fixtures/v1/cross-substrate/
t/v1-cross-substrate.t
t/v1-golden-vectors.t
t/fixtures/vectors/v1-witness.jsonl
docs/V1_DOD.md or docs/ROADMAP.md only if the acceptance language changes
```

## Restore Procedure

When resuming:

1. Read `AGENTS.md`.
2. Read this file.
3. Run `git status --short`.
4. Confirm HEAD includes `test: add showcase demo smoke gate`.
5. If the user asks to continue, open multi-agent discussion first, then choose
   one small executable step.
