# GobanFTP v1.1 Update Checklist

This document is the working checklist for the v1.1 release line. It collects
the planned hardening, usability, showcase, and release-gate work discussed after
the v1.0.1/package 1.001 line.

v1.1 is intended to be a larger update, but it must stay within the existing
`GOFTP/1` boundary: the game descriptor basename plus direct `events/`
basenames are the only replay truth. Display, helper files, sidecars,
projections, SGF, terminal output, Web surfaces, debug bundles, and release
assets must remain derived or diagnostic material.

Priority key:

```text
P0    required before v1.1 can be called a hardening/showcase release
P0.5  required for a trustworthy release unless intentionally deferred
P1    should ship in v1.1 if schedule allows
P2    useful stretch work; can move to v1.2 without weakening the core release
```

Status note for this beta line: P0, the implemented P1 subset, and
the P2 local showcase preview helper are recorded in
`docs/V1_1_RELEASE_GATE.md`. Unmarked boxes below
remain planning granularity and do not by themselves claim that every stretch
detail is shipped.

## Release Positioning

- [ ] Present v1.1 as hardening plus showcase, not as a hosted product.
- [ ] Keep the short external story:
  - Filename is the event.
  - The same accepted names can produce the same witness across local, FTP,
    WebDAV, read-only Git tree, and DNS record-file presentations.
  - v1.1 repairs post-v1.0 trust-boundary issues.
  - v1.1 can generate a browsable proof gallery.
- [ ] Avoid claiming production auth, hosted Web UI, live DNS, DNSSEC trust,
  provider APIs, Git/DNS publishing, production FTP/WebDAV safety, or complete
  scoring/result support.

## P0: Trust Boundary Hardening

- [ ] WebDAV PROPFIND parsing is response-aware.
  - [ ] Only direct response hrefs may contribute names.
  - [ ] Per-response status must be successful before a href is admitted.
  - [ ] Property-value hrefs, recursive hrefs, wrong-game hrefs, duplicate hrefs,
    bad percent encodings, and non-success statuses cannot inject phantom events.
  - [ ] `list_names`, `exists_name`, idempotent publish checks, and publish
    confirmation share the hardened path.
- [ ] DNS record-file parsing is line-aware.
  - [ ] Strip or ignore comments before key/value extraction.
  - [ ] Reject duplicate critical fields such as `type`, `owner`, and `event`.
  - [ ] Align store and profile-adapter owner scoping, including
    `owner_suffix` behavior.
  - [ ] Record order, TTL, answer order, cache state, DNSSEC status, and provider
    metadata remain outside consensus.
- [ ] Local writes stay confined to the game root.
  - [ ] `publish-move` and `publish-ack` reject or safely handle symlinked
    `events/` paths.
  - [ ] `project` and `sgf --write` reject or safely handle symlinked
    `projections/` paths.
  - [ ] Fixed projection paths cannot escape through preexisting symlinks.
- [ ] FTP listing spoofing is reduced.
  - [ ] Exact event basename confirmation is separated from compatibility parsing
    for Unix long-listing, DOS listing, and trimmed rows.
  - [ ] Publish idempotency and post-publish confirmation do not trust
    ambiguous listing rows.
- [ ] Malformed public auth input is validation, not internal failure.
  - [ ] Bad signed-HMAC JSONL exits with validation diagnostics, not exit 5.
  - [ ] Structurally invalid attestation or publish-token rows are public input
    errors.
- [ ] CLI machine-readable lines are single-line safe.
  - [ ] Reject control characters in path-like values or encode emitted values.
  - [ ] `v1 keygen`, `v1 attest`, `v1 publish-token`, storage errors, and any new
    JSON/key-value outputs cannot inject extra stdout or diagnostic records.
- [ ] Temporary publish names avoid avoidable collisions.
  - [ ] FTP and WebDAV temporary names include enough event-specific material to
    avoid same-`by`/same-`n` confusion.
  - [ ] Concurrent publish collision behavior is covered by tests.
- [ ] Invalid game descriptors cannot produce misleading usable roots.
  - [ ] Consumers must see validation status before any root-like field is used.
  - [ ] Witness output makes invalid descriptor status explicit.

## P0: Protocol Conformance Fixtures

- [ ] Establish a v1.1 conformance fixture set.
  - [ ] Body bytes do not affect consensus.
  - [ ] File size does not affect consensus.
  - [ ] Mtime does not affect consensus.
  - [ ] Listing order does not affect consensus.
  - [ ] Sidecars do not affect consensus.
  - [ ] Existing projections do not affect consensus.
  - [ ] `tmp/` residue does not affect consensus.
- [ ] Prove the truth boundary.
  - [ ] Only the game descriptor basename and direct child event basenames under
    `events/` enter the event set.
  - [ ] Descendants under `events/<event>/...` do not become events.
  - [ ] Wrong-game entries and recursive/shadow entries stay outside witness
    truth.
- [ ] Cross-substrate equality is a release gate.
  - [ ] Local, FTP fixture, WebDAV fixture, read-only Git tree fixture, and DNS
    record-file fixture normalize the same logical fixture to the same
    `event_set_root`.
  - [ ] `v1 compare-roots` and `v1 compare-replay` evidence is included in the
    gate.
- [ ] Golden vector updates are explicit.
  - [ ] Existing `GOFTP/1` filename grammar, event id preimages,
    `event_set_root`, DAG replay, and rule legality are unchanged unless a
    separate protocol decision is made.

## P0.5: Input Scale And Timeout Limits

- [ ] Add bounded input behavior for WebDAV.
  - [ ] XML response body size limit.
  - [ ] Maximum admitted href count.
  - [ ] Timeout behavior covered by mock tests.
  - [ ] Oversized or timed-out responses produce stable storage diagnostics.
- [ ] Add bounded input behavior for DNS record files.
  - [ ] File size limit.
  - [ ] Line count limit.
  - [ ] Line length limit.
  - [ ] Oversized TXT-like rows produce validation or storage diagnostics instead
    of unbounded parsing.
- [ ] Add bounded input behavior for FTP listings.
  - [ ] Entry count limit.
  - [ ] Line length limit.
  - [ ] Network timeout behavior covered by mock or live-smoke-safe tests.
- [ ] Add bounded input behavior for signed-HMAC JSONL.
  - [ ] Attestation and publish-token file size limit.
  - [ ] Line length limit.
  - [ ] Record count limit.
  - [ ] Oversized input remains a public validation/storage error, not exit 5.

## P0: JSON Contract

- [ ] New JSON outputs are opt-in and versioned.
  - [ ] Every new JSON document has `schema`.
  - [ ] Every new JSON document has `version`.
  - [ ] Use schema names such as `gobanftp.doctor.v1`,
    `gobanftp.config.v1`, `gobanftp.publish-result.v1`,
    `gobanftp.compare-replay.v1`, and `gobanftp.showcase.v1`.
  - [ ] v1.1 JSON documents set `version` to `1.1`.
- [ ] Default key/value output remains compatible unless a release note says
  otherwise.
- [ ] JSON rendering uses structured data, not stdout re-parsing.
- [ ] Secrets are never present in JSON, key/value stdout, diagnostics, or debug
  bundles.

## P0: Release Claim Audit

- [ ] Add a v1.1 claim audit table to the release gate.
- [ ] Each release-facing claim has:
  - [ ] Claim.
  - [ ] Evidence command.
  - [ ] Test file.
  - [ ] Non-goal.
- [ ] Required claim examples:
  - [ ] WebDAV listing confirmation is hardened.
  - [ ] DNS record-file parsing rejects poisoning cases.
  - [ ] Local write paths do not follow symlink escapes.
  - [ ] FTP publish confirmation uses exact basename checks.
  - [ ] Auth preflight can block an explicitly enabled publish.
  - [ ] Auth is not production writer authorization.
  - [ ] Static HTML/Web projection is not hosted Web UI.
  - [ ] Git and DNS remain read-only runtime substrates.
  - [ ] Scoring/result events remain outside `GOFTP/1`.

## P0: Changelog And Upgrade Notes

- [ ] Add or update release notes for v1.1.
- [ ] Document fixed security boundaries.
- [ ] Document output compatibility.
  - [ ] Existing default key/value output remains compatible where intended.
  - [ ] New JSON output is opt-in and schema-versioned.
- [ ] Document changed failure classes.
  - [ ] Malformed auth JSONL now reports validation diagnostics.
  - [ ] Oversized or timed-out inputs report stable diagnostics.
- [ ] Document new non-goals and deferred features.
- [ ] Document migration notes for scripts that consume CLI output.

## P1: Publish State And Store Capability Model

- [ ] Add a structured publish attempt/result model.
  - [ ] Candidate event built.
  - [ ] Existing replay checked.
  - [ ] Candidate replay validated.
  - [ ] Optional auth preflight authorized or denied.
  - [ ] Store write attempted.
  - [ ] Visibility confirmed or left unconfirmed.
  - [ ] Post-publish replay status reported.
- [ ] Preserve compatibility wrappers for existing publish commands.
- [ ] CLI, TUI, JSON, and showcase surfaces consume the same publish result
  object.
- [ ] Add store capability reporting.
  - [ ] `can_read_events`.
  - [ ] `can_publish`.
  - [ ] `can_mkdir`.
  - [ ] `read_only`.
  - [ ] `network_required`.
  - [ ] `projection_write`.
- [ ] Git tree and DNS record-file modes remain read-only.
- [ ] Local projection writes remain local-only.

## P1: Doctor, Config, Version, And Help

- [ ] Add `--version`.
- [ ] Improve subcommand help for v1.1 commands and options.
- [ ] Add `config show`.
  - [ ] Shows selected store and capability summary.
  - [ ] Redacts passwords, bearer tokens, HMAC secrets, and private key material.
  - [ ] Supports JSON output with schema/version.
- [ ] Add `doctor`.
  - [ ] Defaults to dry-run.
  - [ ] Does not connect to FTP/WebDAV unless explicitly requested.
  - [ ] Reports missing required environment variables.
  - [ ] Reports capability summary and safe validation checks.
  - [ ] Supports JSON output with schema/version.

## P1: Scoped JSON Output

- [ ] JSON is added only where it helps automation.
  - [ ] `doctor --json`.
  - [ ] `config show --json`.
  - [ ] Publish result JSON.
  - [ ] Compare/showcase JSON.
  - [ ] Optional debug bundle manifest JSON.
- [ ] Do not convert every command to JSON in v1.1.
- [ ] Tests cover schema, version, redaction, and required fields.

## P1: Auth Formalization

- [ ] State the v1.1 auth boundary consistently.
  - [ ] Verifier-local signed-HMAC witness/preflight evidence.
  - [ ] May deny one proposed local, FTP, or WebDAV publish before the store write
    when explicitly enabled.
  - [ ] Does not authenticate transports.
  - [ ] Does not bind account identity.
  - [ ] Does not authorize real writers.
  - [ ] Does not define production key lifecycle.
  - [ ] Does not change unsigned `GOFTP/1`.
- [ ] Add tests for denial before store publish.
- [ ] Add tests for malformed token/attestation validation diagnostics.
- [ ] Keep HMAC secrets out of filenames, projections, diagnostics, stdout, JSON,
  debug bundles, fixtures, and release assets.

## P1: Live And TUI Improvements

- [ ] Keep `play --tui` as a local input/display surface.
- [ ] Do not let TUI own replay truth, rule legality, roots, diagnostics, or
  publish semantics.
- [ ] Add a recordable live observation surface.
  - [ ] `watch --live --compact` or equivalent.
  - [ ] Frame includes poll count, live flag, root, event count, turn/worldline,
    and fork/validation status.
  - [ ] Any observed delta is labeled observer state, not protocol input.
- [ ] Preserve non-TTY refusal for `play --tui`.
- [ ] Optional demo/record helper may use scripted TUI frames without changing the
  production TUI contract.

## P1: Publish Failure And Hardening Fixtures

- [ ] Add or expand fixture coverage for:
  - [ ] WebDAV malformed multi-status responses.
  - [ ] WebDAV href/property/status spoofing.
  - [ ] DNS duplicate key poisoning.
  - [ ] DNS inline comment poisoning.
  - [ ] DNS owner suffix parity.
  - [ ] FTP spoofed listing and publish confirmation.
  - [ ] Local event symlink escape.
  - [ ] Local projection symlink escape.
  - [ ] Git tree read-only denial.
  - [ ] DNS record-file read-only denial.
  - [ ] Malformed signed-HMAC JSONL.
  - [ ] CLI output control-character injection.
  - [ ] Temporary publish collision behavior.

## P1: Showcase Release

- [ ] Add a one-command showcase/export path.
  - [ ] `gobanftp showcase --out <dir>` or `script/showcase-v1.1`.
  - [ ] Offline and deterministic.
  - [ ] Uses fixtures or disposable local copies.
  - [ ] Does not mutate authoritative example fixtures unless explicitly
    requested.
- [ ] Generated showcase output includes:
  - [ ] `index.html`.
  - [ ] Clean witness page.
  - [ ] Fork/race witness page.
  - [ ] Signed failure page.
  - [ ] Terminal transcript.
  - [ ] `roots.json` with schema/version.
  - [ ] SGF, board, and verdict projection material.
  - [ ] Release-evidence text.
- [ ] Showcase pages remain static observatory surfaces.
  - [ ] Direct-open HTML.
  - [ ] No required server.
  - [ ] No network fetch.
  - [ ] No production hosted Web UI claim.
  - [ ] No consensus reads from HTML, SGF, sidecars, projections, or terminal
    output.
- [ ] Add a cross-substrate equality matrix.
  - [ ] Local.
  - [ ] FTP fixture.
  - [ ] WebDAV fixture.
  - [ ] Read-only Git tree fixture.
  - [ ] DNS record-file fixture.
  - [ ] Shows root, replay status, board hash, SGF hash, and match status.
- [ ] Add fork/race visualization.
  - [ ] Shows common parent.
  - [ ] Shows legal competing child ids.
  - [ ] Shows conservative replay stopping at the fork.
  - [ ] Shows ack-assisted recovery only as an explicit comparison.
- [ ] Add truth/shadow gallery.
  - [ ] Body bytes, mtime, listing order, sidecars, projections, and `tmp/`
    remain shadow.
  - [ ] Basename changes alter or reject the event set.

## P1: README And Public Presentation

- [ ] Rework the README first screen.
  - [ ] One strong image.
  - [ ] One command.
  - [ ] One direct-open HTML path.
  - [ ] Short boundary statement.
- [ ] Keep the three-language READMEs synchronized.
- [ ] Keep badges honest.
  - [ ] Prefer real CI badge where available.
  - [ ] Showcase badge must point to an actual release gate.
- [ ] Add or update screenshots/assets for:
  - [ ] Static showcase gallery.
  - [ ] Cross-substrate terminal table.
  - [ ] Fork/race view.
  - [ ] TUI or compact live recording if shipped.
- [ ] Update `docs/SHOWCASE.md` with a recording and screenshot path.

## P1: Release Assets And CI Gate

- [ ] Attach or record v1.1 showcase assets outside the source tree.
  - [ ] `GobanFTP-v1.1-showcase.zip`.
  - [ ] `witness-clean.html`.
  - [ ] `witness-fork.html`.
  - [ ] `demo-transcript.txt`.
  - [ ] `release-evidence.txt`.
  - [ ] Optional GIF/asciinema generation script output.
- [ ] Add a showcase release gate.
  - [ ] Generate showcase artifact.
  - [ ] Check HTML has no remote resources.
  - [ ] Check HTML has no script/form/network client unless explicitly allowed
    and tested.
  - [ ] Check roots and hashes match fixtures.
  - [ ] Check claim audit references evidence.
- [ ] Add `docs/V1_1_RELEASE_GATE.md` or equivalent when release evidence is
  available.

## P1/P2: Sanitized Debug Bundle

- [ ] Start with safer primitives.
  - [ ] `doctor --json`.
  - [ ] `config show --json`.
- [ ] Consider `doctor --bundle <dir>` only after redaction policy is stable.
- [ ] If shipped, bundle may include:
  - [ ] Version.
  - [ ] Redacted config summary.
  - [ ] Store capabilities.
  - [ ] Safe doctor results.
  - [ ] Test command summary.
  - [ ] JSON manifest with schema/version.
- [ ] Bundle must not include:
  - [ ] Passwords.
  - [ ] Bearer tokens.
  - [ ] HMAC secrets or private keys.
  - [ ] Raw environment dumps.
  - [ ] Unredacted URLs or paths when they may contain secrets.

## P2: Optional Stretch Work

- [x] Local read-only `showcase preview` helper for generated showcase
  directories, limited to loopback static files and not a hosted UI/deploy claim.
- [ ] GitHub Pages static showcase, if clearly labeled as documentation.
  Deferred for this beta because automatic deploy/publish actions are out
  of scope.
- [ ] TUI GIF/asciinema path. Deferred for this beta; no generated cast,
  GIF, binary asset, or external recording-tool dependency is included.
- [x] Static generated showcase navigation polish. Limited to generated-bundle
  file links and same-document fragment anchors; no hosted UI/deploy/runtime
  claim, no script, no forms, no remote resources, and no new generated files.
- [ ] Result/scoring profile design, only if handled as a separate explicit
  profile or protocol decision.

Remaining P2 closure: all P2 work other than the local preview helper and static
generated-bundle navigation polish remains deferred for v1.1. This includes
GitHub Pages/static hosting, TUI assets, broader Web observatory work, sanitized
debug bundle expansion, result/scoring design, production auth, Git/DNS
publishing, live DNS, DNSSEC, provider APIs, and release or deploy operations.

## Explicit Non-Goals For v1.1

- [ ] No hosted Web UI claim.
- [ ] No normal online Go game server claim.
- [ ] No production auth claim.
- [ ] No production key lifecycle.
- [ ] No live DNS resolver, AXFR client, DNSSEC trust, provider API, dynamic
  update, or DNS publish support.
- [ ] No Git publish support.
- [ ] No production FTP/WebDAV deployment safety certification.
- [ ] No complete scoring/result system in `GOFTP/1`.
- [ ] No changes to `GOFTP/1` filename grammar, event id preimages,
  `event_set_root`, DAG replay, or rules unless a separate protocol decision is
  recorded.

## Suggested Implementation Order

1. Finish P15 hardening repairs and tests.
2. Add conformance fixtures and input scale/timeout gates.
3. Add publish result and store capability abstractions.
4. Add `doctor`, `config show`, `--version`, help, and scoped JSON.
5. Formalize auth wording and malformed-input behavior.
6. Add compact live/terminal compare surfaces if still in scope.
7. Add one-command showcase generation and static gallery tests.
8. Update README, `docs/SHOWCASE.md`, release notes, claim audit, and release
   gate evidence.
9. Run targeted tests, then full `prove -lr t`.

## Expected Verification Commands

```sh
prove -lr t
prove -lr t/showcase-demo.t
prove -lr t/v1-cli-compare.t
prove -lr t/v1-cli-witness-surface.t t/static-witness-specimen.t
```

Additional v1.1-specific tests should be added as the checklist items are
implemented.
