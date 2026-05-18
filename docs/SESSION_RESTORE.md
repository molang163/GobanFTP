# Session Restore

One-line resume command:

```text
恢复 GobanFTP 工作：读取 docs/SESSION_RESTORE.md，按 Next Step 继续。
```

## Current State

Repository: `/run/media/molang/linux-dev/GobanFTP`

Current HEAD:

```text
c763103 test: add bad mtime attack fixture
```

Working tree was clean when this file was written.

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
- Ruleset seal, v1 witness CLI, and v1 compare CLI are already implemented.

## Last Verified

After `c763103`, these passed:

```text
prove -lr t/attack-fixtures.t t/v1-attack-fixtures.t
prove -lr t/attack-fixtures.t t/v1-attack-fixtures.t t/listing.t t/replay-input-boundary.t t/store-ftp-mock.t t/store-webdav-mock.t t/e2e-ftp-mock.t
prove -lr t
```

Full test result:

```text
Files=61, Tests=803, all successful.
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

Do not continue signed-HMAC negative fixture expansion unless a concrete bug is
found. That matrix is currently strong enough for v1 proof work.

Recommended next discussion target:

```text
Choose between:
1. expand v1 cross-substrate golden vectors in small batches
2. add the next core/profile attack fixture
3. harden the three-minute demo shrine into a reproducible showcase path
```

Best immediate implementation candidate:

```text
solidify docs/SHOWCASE.md and/or add a small demo verification test that locks
the shrine, race, oracle smoke, and v1 witness commands as the public viewing
path.
```

Alternative proof-hardening candidate:

```text
add the next small attack fixture before the large golden-vector matrix, likely
an FTP/local profile noise specimen or another core poison case with real
harness behavior.
```

## Restore Procedure

When resuming:

1. Read `AGENTS.md`.
2. Read this file.
3. Run `git status --short`.
4. Confirm HEAD is at or after `c763103`.
5. If the user asks to continue, open multi-agent discussion first, then choose
   one small executable step.

