# Roadmap

This roadmap exists so the project advances in a stable order.

## Current Status

P0 through P8 are implemented for the v0.1 release. The v0.1 boundary freezes
`GOFTP/1` consensus around the existing descriptor-name and direct-events
filename protocol, while result events, scoring, and signed consensus remain
future work unless a later phase or decision records them first.

The v1.0 route is to turn that boundary into a proof machine: explicit
profiles, adapter contracts, hostile fixtures, cross-system witnesses, optional
signed/auth profiles, and reader-facing surfaces. WebDAV is the first admitted
non-FTP write-capable runtime store on that route, and Git tree is admitted as a
read-only runtime store. DNS record admission is read-only over local or
otherwise declared record files, with no live DNS, AXFR, DNSSEC trust, provider
API, dynamic update, or publish path. `GOFTP/1` remains unchanged.

The current route work is P17 TUI hardening, P14 claim audit, and final
clean-gate preparation for the admitted read boundaries now present at HEAD,
especially `git-tree-goftp1` and `dns-record-goftp1`. The witness vectors now
carry self-contained input names, diagnostics, and rendered projection text,
and replay-invariant vectors now cover ordinary rule, DAG, ACK, terminal,
malformed, and ack-assisted fork behavior. Event-id collision is now covered as
a synthetic DAG-boundary vector, not as an ordinary basename collision claim.
Public non-consensus poison vectors now bind baseline/poison witness pairs to
core/local bad-mtime, bad-payload, bad-list-order, bad-signature,
poisoned-sidecar, projection-poison, tmp-poison, WebDAV metadata-poison, WebDAV
href-traversal, DNS owner-poison, and Git-tree path/metadata-poison fixtures,
plus the FTP listing-shadow cross-substrate fixture, including real fixture
`input_names`, embedded evidence artifacts when poison lives outside the
listing, and unchanged event-set preimage, root, replay, board, projection, and
SGF truth. The signed-HMAC public-trust bridge is now represented in public
signed/auth golden vectors as rejected `k1.` selector evidence and accepted
explicit HMAC selector evidence. The FTP listing-shadow vector is
fixture/listing evidence only. Local `play --tui` is a non-consensus
input/display surface over the existing play publish path.
This is not Git publish, Git remote fetch, live FTP, FTP auth, FTP integrity,
FTP publish behavior, live DNS, DNS publish, hosted Web UI, production key
lifecycle completion, publish auth completion, or a v1.0/P14 completion claim.

## Cross-Cutting Acceptance: Elegance Without Obscurity

At every phase, an implementation is not complete merely because it works. It
must also keep the protocol boundary visible:

- replay works from listing names alone
- clever algorithms have focused tests
- failure diagnostics identify the pipeline stage that rejected input
- source-art changes cannot alter event ids or replay behavior
- projections remain rebuildable from authoritative listings

## P0: Protocol Lockdown

Goal: make filename grammar and event ids unambiguous before runtime code exists.

Tasks:

- finalize game descriptor grammar
- finalize move and ack event filename grammar
- define event id hash input and encoding
- define listing normalization rules
- define invalid-name diagnostics

Acceptance:

- `docs/PROTOCOL.md` has no "choose later" language for event names
- `t/fixtures/` contains valid names, invalid names, and expected event ids
- parser diagnostics are stable enough for tests

## P1: Local Listing Replay

Goal: replay a small game from a local directory without FTP.

Tasks:

- implement `GobanFTP::GameSpec`
- implement `GobanFTP::Filename::Grammar`
- implement `GobanFTP::EventID`
- implement `GobanFTP::Event::Move`
- implement `GobanFTP::Store::Local`

Acceptance:

- parse game descriptor directory names
- list event names from local `events/`
- reject malformed names
- reproduce fixture event ids
- replay does not read event file contents

## P2: Rules and DAG

Goal: validate legal play and preserve forks.

Tasks:

- implement board coordinates
- implement flood-fill capture and suicide checks
- implement canonical board-position hashes
- implement positional superko by ancestor hash comparison
- implement DAG construction
- implement canonical line selection

Acceptance:

- replay a legal fixture
- reject suicide, capture, and superko fixtures deterministically
- detect a fork fixture
- keep illegal events out of canonical replay
- rule algorithms follow `docs/RULES.md` before any optimization

## P3: Projections

Goal: rebuild human-readable artifacts.

Tasks:

- export `projections/sgf/main.sgf`
- export `projections/sgf/variations.sgf`
- render `projections/oracle/board.txt`
- render `projections/board/`
- render `projections/graveyard/`

Acceptance:

- deleting `projections/` and rebuilding produces the same outputs

## P4: CLI

Goal: make local workflows usable.

Tasks:

- implement `gobanftp verify`
- implement `gobanftp replay`
- implement `gobanftp project`
- implement `gobanftp sgf`

Acceptance:

- CLI commands have stable exit codes
- `t/cli.t` covers success and failure cases

## P5: FTP Backend

Goal: publish and sync through FTP.

Tasks:

- implement `GobanFTP::Store::FTP`
- use `TYPE I`
- publish zero-byte events through `tmp/` then `RNTO`
- support optional `MKD events/<event_name>` pure mode
- treat existing identical event names as success
- ignore temporary and malformed files during replay

Acceptance:

- local store contract tests also pass against FTP when
  `GOBANFTP_FTP_TEST=1`

## P6: Source-Art Oracle

Goal: make `oracle/goban.pl` visually interesting without taking over core
logic.

Tasks:

- keep verifier logic in modules
- shape the wrapper as a Go-board-like source file
- run `perl -c oracle/goban.pl`
- add `t/source-art.t`

Acceptance:

- source art executes
- changing comments/spacing does not affect event ids or replay behavior
- source art remains a wrapper and does not own protocol semantics

## P7: Playable Terminal

Goal: make the project playable from a plain terminal while preserving the
listing-first protocol boundary.

Tasks:

- implement `gobanftp play --once` for one-shot board snapshots
- implement `gobanftp play --move` and interactive `gobanftp play`
- implement `gobanftp watch` for bounded or continuous listing polls
- expose turn and worldline status in stable stdout fields
- keep terminal rendering derived from replay/projection state only

Acceptance:

- `play` and `watch` do not write projections
- candidate move validation does not publish bad events
- fork snapshots exit `3` and show fork parent/children
- tests cover one-shot play, publish-and-render, watch polling, and fork output

## P8: v0.1 Hardening And Showcase

Goal: ship a coherent playable protocol artwork without expanding `GOFTP/1`
consensus.

Tasks:

- freeze the v0.1 `GOFTP/1` consensus boundary around game descriptor names,
  direct `events/` basenames, filename-derived event ids, DAG replay, rules, and
  explicit ack-assisted recovery
- document `projections/oracle/listing.txt` as a replay-derived listing
  transcript projection, not a replay input
- keep the local filesystem prototype and mock-tested FTP backend listing-first
- keep the terminal create, publish, play, watch, replay, project, and SGF flows
  usable for the showcase fixture
- keep source art decorative and runnable
- run the release hygiene gates before packaging or publication

Acceptance:

- v0.1 release notes say `GOFTP/1` consensus is frozen for the release
- replay still works from descriptor and `events/` basenames alone
- deleting `projections/oracle/listing.txt` cannot change event ids, DAG replay,
  fork resolution, rules validation, SGF output, or board state
- the showcase is playable as protocol artwork from local listings and from the
  FTP backend path already covered by mocks or gated live smoke tests
- scoring, final result events, and signed consensus remain explicitly deferred
  to a future phase, protocol version, or profile

## v1.0 Definition Of Done

v1.0 is complete only when these gates are all true:

- `GOFTP/1` descriptor-name and direct-`events/` replay remains byte-for-behavior
  unchanged for every v0.1 fixture, including event ids, fork diagnostics, board
  state, SGF output, and projection rebuilds
- the v1.0 substrate set is explicitly named before implementation; the release
  target is local, FTP, Git-like, DNS-like, and WebDAV-like profiles unless
  `docs/V1_DOD.md` is deliberately revised before code depends on the matrix
- every v1.0 profile declares authoritative inputs, ignored metadata, publish
  semantics, read normalization, failure diagnostics, and auth stance before code
  depends on it
- attack fixtures prove that timestamps, listing order, object size, file bytes,
  entry type, sidecars, projections, caches, and temporary publish residue cannot
  become accidental consensus
- cross-system witnesses prove that the same event set observed through FTP and
  each named v1.0 substrate produces the same `event_set_root`, DAG, replay
  status, board, SGF, and diagnostics where applicable
- signed/auth behavior is explicit profile behavior; unsigned `GOFTP/1` remains
  valid and signatures never silently become `GOFTP/1` consensus
- source-art, TUI, and Web surfaces can display profiles, witnesses, signatures,
  forks, and projections, but none of them can feed replay or change consensus
- release notes, fixture manifests, smoke commands, and artifact checks leave no
  "choose later" language for v1.0 profile, adapter, witness, or auth behavior

Detailed gates live in `docs/V1_DOD.md`. Substrate profile contracts live in
`docs/PROFILES.md`. Filename grammar vectors are planned in `docs/GRAMMAR.md`;
attack fixture admission and verdicts are planned in `docs/ATTACKS.md`.

## v1.0 Proof Machine

The v1.0 proof machine is the repeatable chain that makes every supported system
auditable:

```text
profile declaration
  -> adapter reads declared authoritative inputs
  -> normalized event basenames
  -> GOFTP/1 event id verification
  -> event_set_root
  -> DAG and rule replay
  -> witness outputs and projections
```

`event_set_root` is a witness commitment, not a new `GOFTP/1` event id input. It
is derived from the game descriptor basename and the sorted set of direct event
basenames that parse as GOFTP/1 events and pass event-id verification after
profile normalization. DAG-invalid or rule-illegal events still belong to that
accepted event set; malformed names, unknown versions, bad event ids, and ignored
metadata are recorded in diagnostics, not hidden inside the root.

The proof machine must be able to say, for every supported system:

- what was read
- what was ignored
- what was rejected
- what event set was accepted
- what root commits to that event set
- what replay and projection outputs follow from that root

## P9: v1.0 Profile And Adapter Contract

Goal: make "other systems" exact before adding system-specific behavior.

Tasks:

- define the v1.0 profile template: profile id, version, system type,
  authoritative inputs, ignored metadata, publish semantics, read normalization,
  diagnostics, auth stance, fixtures, and smoke command
- record the baseline and planned v1.0 profiles in `docs/PROFILES.md`
- define the adapter contract around listing-like reads, event-name publishing,
  metadata normalization, capability reporting, and stable diagnostics
- keep the existing FTP path as the `GOFTP/1` baseline profile without changing
  descriptor grammar, event filename grammar, event id preimages, DAG replay,
  rule legality, SGF export, or projection rebuilding
- use WebDAV as the first non-FTP write-capable runtime store, admit Git tree
  as read-only runtime evidence, and admit DNS only as read-only local/declared
  record-file evidence behind the same adapter contract
- require any profile that needs different consensus inputs to declare a new
  profile or protocol version instead of changing `GOFTP/1`

Acceptance:

- each named v1.0 substrate has a written profile before adapter code for that
  substrate lands
- adapter conformance tests can run the same replay fixture through FTP and each
  implemented v1.0 substrate
- `GOFTP/1` v0.1 fixtures pass unchanged under the baseline profile
- no adapter can pass payload bytes, timestamps, order, entry type, object size,
  cache contents, sidecar contents, or projection contents into core replay

## P10: Attack Fixtures

Goal: prove the profile and adapter boundaries under hostile or misleading
storage states.

Tasks:

- add fixtures for malformed names, unknown event versions, bad event ids,
  missing parents, illegal moves, duplicate names, nested entries, stale tmp
  entries, and fork races
- add metadata-spoof fixtures for reordered listings, forged timestamps, changed
  sizes, changed file bytes, changed entry types, stale caches, stale sidecars,
  stale sidecar signatures, and stale projections
- add profile-level witness attack fixtures for implemented substrates, starting
  with WebDAV metadata, body, locks, shadow collections, recursive hrefs,
  duplicates, and percent-decoding hazards
- add profile-specific publish-failure fixtures for partial writes, existing
  final names, conflicting final names, delayed visibility, and retry behavior
- add signed/auth negative fixtures once signed/auth profiles exist
- record expected diagnostics and expected replay outputs for every attack
  fixture

Acceptance:

- attack fixtures run against every implemented adapter where the system can
  represent the attack
- rejected input is visible in diagnostics and excluded from DAG replay
- ignored metadata changes do not change `event_set_root`, replay status, board,
  SGF, or projections
- publish failures are classified without inventing hidden consensus rules

Current implemented proof: `webdav-publish-failure` covers existing-final
idempotence, delayed WebDAV `MOVE` visibility, hard `HTTP 423 Locked` publish
failure, zero-byte temporary payloads, retry bounds, and tmp debris exclusion.
DNS record admission has no publish-failure class yet because it has no publish
path. `t/store-dns-record.t` and `t/dns-cli-parity.t` cover local record-file
read admission and read-only publish rejection; TTL, order, cache, DNSSEC, live
DNS, AXFR, and provider API behavior must stay outside consensus claims.

## P11: Cross-System Witness And `event_set_root`

Goal: prove that different systems expose the same game when their accepted event
sets are the same.

Tasks:

- define the `event_set_root` preimage, encoding, and diagnostic output
- write witness output that includes profile id, profile consensus version,
  adapter id, game descriptor, raw input count, normalized event count,
  normalized event names, accepted event count, rejected input count,
  `event_set_root`, canonical tip, replay status, board hash, SGF hash, and
  relevant diagnostic counts and codes
- create cross-system witness fixtures with the same accepted event set in FTP
  and each implemented v1.0 substrate
- add a forked witness fixture so branch visibility and conservative fork status
  are compared across systems
- make witness output rebuildable from declared authoritative inputs

Acceptance:

- FTP and each implemented v1.0 substrate produce the same `event_set_root` for
  the same accepted event basenames
- equal roots produce equal DAG replay status, board output, SGF output, and fork
  diagnostics
- differing ignored metadata does not affect witness equality
- witness files are projections and can be deleted and rebuilt

## P12: Signed/Auth Profiles

Goal: add explicit trust surfaces without changing unsigned `GOFTP/1`.

Tasks:

- define which profile or profiles require signatures, authentication, or both
- keep publish authentication separate from replay consensus unless a profile
  explicitly declares signed consensus
- define signing preimages for event-name attestations or `event_set_root`
  attestations
- define key identity, key rotation, missing-signature, bad-signature,
  stale-signature, and revoked-key diagnostics
- keep secrets out of filenames and out of projection files
- document how unsigned `GOFTP/1` remains valid and unchanged

Acceptance:

- unsigned v0.1 fixtures replay exactly as before
- signed/auth fixtures pass only under profiles that explicitly require them
- bad signatures and auth failures are visible diagnostics, not silent replay
  changes
- sidecar signatures remain advisory outside a signed/auth profile

Current implemented proof: fixture-only public key identity is available through
`gobanftp v1 keyid --fixture`. It derives `GOFTP-KEY/1` `k1.` ids from public
fixture records and does not create trust, private keys, signatures, or replay
inputs. Fixture-only trust reporting is available through
`gobanftp v1 trust-report --fixture`; it reports public key and trust TSV state
after the normal unsigned witness and does not enforce signed trust.
`signed-hmac-goftp1` now has an explicit verifier lifecycle input for HMAC
selectors: `trusted` and `rotated` verify old signed material, while `revoked`
and `expired` reject inside the signed profile gate without changing unsigned
replay. The signed-HMAC golden vectors now freeze lifecycle status,
accepted/rejected sets, and `key.revoked` / `key.expired` rejected diagnostics.
The `public-trust-bridge-poison` specimen proves public `GOFTP-TRUST/1` rows
cannot authorize `k1.` HMAC selectors or revoke explicit HMAC selectors. It is
also frozen in signed-HMAC public golden vectors that bind the public key and
trust TSV fixture text while keeping the verifier HMAC secret out of public
vector data.

## P13: Source-Art, TUI, And Web Surfaces

Goal: make the proof machine inspectable without letting display surfaces become
consensus.

Tasks:

- extend source-art smoke paths to display or invoke witness checks while keeping
  source art decorative. The first smoke path now displays `GobanFTP::Witness`
  fields while leaving the executable board glyphs outside replay truth.
- define and apply the source-art motif register in `docs/SOURCE_ART.md`,
  including altar, goban, hash seal, DAG tree, FTP gate, projection mirror,
  witness eye, root monolith, signature seal, observatory surfaces, and a small
  arch-gate easter egg. The first arch-gate is now a comment-only,
  non-consensus threshold in `oracle/goban.pl` with `t/source-art.t` coverage.
- expose profile id, adapter id, `event_set_root`, replay status, fork status,
  and signature status in terminal output. The first static terminal
  observatory view is available through `v1 witness --surface terminal`;
  it is a stdout inspection panel, not an interactive TUI.
- expose local interactive terminal play through `gobanftp play --tui`. It
  accepts keyboard and SGR mouse input, renders a readable board/status view,
  publishes through the existing `play` path, exits after one successful
  publish, and does not own replay truth.
- add a Web-facing inspection surface or static export for witnesses,
  projections, profiles, diagnostics, and attack fixtures. The first reusable
  surface renderer now formats supplied witness fields and projection text
  without reading storage or recomputing truth, and `v1 witness --surface`
  exposes it as a read-only text/static HTML/terminal CLI view. The minimal
  surface smoke freezes text, HTML, and terminal output digests without
  claiming a hosted Web UI. The local `play --tui` path is covered by TUI play
  tests and still cannot own truth.
- keep all TUI and Web output derived from replay results, witness outputs, or
  projections
- preserve the rule that changing source art, terminal formatting, Web assets,
  or projection wording cannot change replay

Acceptance:

- source-art, TUI, and Web surfaces can be deleted or regenerated without
  changing `event_set_root`, DAG replay, board state, SGF, or diagnostics
- the arch-gate easter egg is present only as non-consensus source/display art
  and cannot be confused with protocol branding or official project affiliation
- surfaces display enough witness detail for a reader to inspect the abuse
- display code does not parse storage metadata as consensus input

## P14: v1.0 Release Freeze

Goal: freeze v1.0 only after the profile, adapter, attack, witness, auth, and
surface gates are complete.

Tasks:

- run v0.1 fixture parity and record that `GOFTP/1` behavior is unchanged
- run profile and adapter conformance tests for every supported system
- run attack fixtures and cross-system witness fixtures
- run signed/auth fixtures for signed/auth profiles
- run source-art, TUI, Web, projection rebuild, SGF, and CLI smoke paths
- freeze profile docs, adapter contracts, witness format, diagnostics, and
  release artifact manifest
- document every deferred surface as a future profile, protocol version, or
  later phase

Current proof: `docs/P14_RELEASE_GATE.md` records the first P14a dry-run command
matrix, generated artifact list, skipped gates, and manifest-skip correction.
It is a release-route checkpoint, not a v1.0 tag or P14 completion claim.
The final artifact identity and tag preconditions are tracked in
`docs/P14_RELEASE_MANIFEST_AND_TAG_PLAN.md`.
The `t/p14-claim-audit.t` gate guards current release-facing text against
accidental over-claims. The immediate follow-up is P17b TUI hardening and final
clean-gate preparation, not Git publish, live DNS, AXFR, DNSSEC trust, provider
APIs, dynamic update, DNS publish, hosted Web UI, production key lifecycle
completion, publish auth completion, or a v1.0/P14 completion claim.

Acceptance:

- release notes state that `GOFTP/1` remains unchanged from v0.1
- no v1.0 profile, adapter, witness, auth, or diagnostic behavior has unresolved
  "choose later" wording
- all release artifacts can be rebuilt or verified from the recorded commands
- shipped fixtures demonstrate baseline FTP, the named v1.0 substrates, attacks,
  cross-system witness equality, and signed/auth behavior where enabled
