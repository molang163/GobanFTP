# Example Fixtures

This directory is for human-readable sample games and mirrored FTP layouts.

Unlike `t/fixtures/`, examples may include pretty JSON, notes, and decorative
projection files.

Use examples to explain the ritual. Use `t/fixtures/` to lock protocol bytes.

## Fixtures

- `minimal-game/` is the smallest complete GOFTP/1 mirror.
- `ftp-shrine/` is a browsable shrine: authoritative `events/` names, optional
  `sidecar/` marginalia, and rebuildable `projections/`.
- `ftp-race-shrine/` is a browsable fork shrine: two legal children share one
  parent, default replay reports the fork, and ack-assisted recovery remains
  explicit.
