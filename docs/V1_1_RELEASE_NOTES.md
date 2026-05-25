# GobanFTP v1.1.0-beta.1 Release Notes

Status: public beta release notes for v1.1.0-beta.1 / package 1.100_001.

These notes describe the v1.1.0-beta.1 hardening and showcase beta. This is a
research-prototype release line, not a production service certification.

P2 status: this beta includes the local loopback showcase preview helper
and generated static-bundle navigation polish only. Remaining P2 stretch work is
deferred and has no hosted UI, provider, production auth, Git/DNS publishing,
scoring/result, or release/deploy claim.

## Highlights

- WebDAV `PROPFIND` listing admission is response-aware and rejects spoofed or
  unsuccessful response hrefs.
- DNS record-file parsing strips inline comments outside quotes, rejects
  duplicate critical fields, and aligns owner-suffix handling between store and
  profile adapter paths.
- Local store directory, listing, existence, event, and projection paths reject
  static symlink components at the game-root, events, and projection
  boundaries.
- FTP publish confirmation uses exact basename checks for idempotency and final
  visibility.
- Temporary FTP and WebDAV publish names include event-specific material to
  reduce avoidable same-author/same-nonce collision confusion.
- Malformed signed-HMAC JSONL is treated as public validation input, not an
  internal error.
- WebDAV XML, DNS record files, FTP listings, and signed-HMAC JSONL inputs have
  bounded file, line, record, href, or listing limits.
- `config show --json`, `doctor --json`, publish result JSON, compare JSON,
  and showcase JSON provide scoped v1.1 automation documents while leaving
  default key/value stdout unchanged.
- `watch --compact` provides bounded recordable observation without board
  drawing, while still deriving state only from a fresh `events/` listing and
  replay.
- Generated bundle is static; optional P2 loopback preview helper is
  local-only/read-only and not hosted UI/deploy. It binds only `127.0.0.1`,
  serves the fixed generated file set from memory, and exposes no preview JSON,
  CORS, remote-host, or provider-deploy mode.
- Generated showcase pages include only local file links and same-document
  fragment navigation across supplied witness/projection sections; no script,
  forms, remote resources, network client code, or new generated files are
  added.
- Protocol conformance fixtures now pin body bytes, file size, mtime, listing
  order, sidecars, projections, `tmp/` debris, recursive descendants, and
  wrong-game shadows outside `GOFTP/1` truth.

## Compatibility

`GOFTP/1` consensus is unchanged. The game descriptor basename and accepted
direct child event basenames under `events/` remain the replay inputs.

Default CLI output remains key/value stdout plus documented diagnostics. New
JSON is opt-in per command only and uses scoped schemas such as
`gobanftp.config.show.v1`, `gobanftp.doctor.v1`, and
`gobanftp.publish.result.v1`. Existing JSONL fixture and signed-HMAC records
keep their current shape.

Scripts should continue to check exit codes and documented keys instead of
depending on Perl exception suffixes or multi-line path echoing. Path-like CLI
inputs with control characters are now rejected before they can produce
ambiguous machine-readable output.

## Diagnostic Changes

- Malformed attestation and publish-token JSONL now report validation
  diagnostics.
- Oversized WebDAV, DNS record-file, FTP listing, attestation JSONL, and
  publish-token JSONL inputs report stable validation or storage diagnostics.
- Mock timeout coverage is fixture-local. It is not a real network service SLA
  or streaming transport read-cap claim.

## JSON Contract

Opt-in v1.1 JSON documents are narrow and command-scoped. Each document includes
`schema = gobanftp.<name>.v1` and `version = 1.1`, is rendered from structured
data, and must not contain secrets. There is no global JSON mode and no complete
JSON mode for every command.

JSON rendering uses structured data from the command result, not stdout
re-parsing.

## Non-Goals

Generated bundle is static; optional P2 loopback preview helper is
local-only/read-only and not hosted UI/deploy. It binds only `127.0.0.1` and
does not provide a remote-host, CORS, provider-deploy, or preview JSON mode.

Remaining P2 stretch work is deferred: no GitHub Pages/static hosting, TUI
GIF/asciinema asset, broader Web observatory work beyond the accepted static
generated-bundle navigation polish, sanitized debug bundle expansion, and no
  result/scoring profile in this beta.

This beta does not claim hosted Web UI, browser application, server
deployment, provider deploy, production auth, production writer authorization,
production key lifecycle, Git publishing, Git remote fetch, live DNS, AXFR,
DNSSEC trust, provider APIs, DNS dynamic update, DNS record publishing,
production FTP deployment safety, OS sandboxing, same-permission concurrent
rename-race protection, Windows junction coverage, a complete JSON mode for
every command, or a complete scoring/result system.

## Upgrade Notes

- Keep existing scripts on the documented key/value CLI surface unless a future
  command explicitly advertises a versioned JSON output.
- Use `gobanftp config show --json` and `gobanftp doctor --json` for local
  automation checks that need store capabilities and redacted environment
  state without parsing key/value output.
- Do not pass paths containing ASCII control characters to CLI output options.
- Treat new oversized-input and timeout diagnostics as public input/storage
  failures, not internal crashes.
- Treat signed-HMAC publish preflight as an optional verifier-local gate. It can
  deny an explicitly enabled publish attempt, but it is not production writer
  authorization.
