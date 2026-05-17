# Roadmap

This roadmap exists so the project advances in a stable order.

## Current Status

P0 through P8 are implemented for the v0.1 release. The v0.1 boundary freezes
`GOFTP/1` consensus around the existing descriptor-name and direct-events
filename protocol, while result events, scoring, and signed consensus remain
future work unless a later phase or decision records them first.

The v1.0 direction is to let GobanFTP become visibly multi-system protocol
abuse without making the v0.1 replay contract ambiguous. Other systems may be
added as explicit profiles, adapters, or projection surfaces only after their
replay inputs and ignored metadata are written down.

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

## P9: v1.0 Multi-System Rites

Goal: let the project abuse more than FTP while preserving the inspectable
listing-first lesson that made v0.1 coherent.

Tasks:

- define what "other systems" means for v1.0 before adding code
- keep FTP as the baseline `GOFTP/1` specimen
- introduce new systems through explicit profiles or adapters, not hidden
  conditionals inside replay
- require each system to declare authoritative inputs, ignored metadata,
  publish semantics, and failure diagnostics
- add at least one fixture and one runnable smoke path for every new system
- keep cross-system projections rebuildable from the declared authoritative
  inputs
- keep source art decorative and non-consensus even when more systems appear

Acceptance:

- `GOFTP/1` replay remains unchanged for v0.1 fixtures
- every v1.0 system has docs that say what counts as truth and what remains
  shadow
- no system uses timestamps, server order, object size, file bytes, or transport
  metadata as consensus unless a new protocol version or explicit profile says so
- a reader can inspect the new system specimen and see how the abuse works
- tests prove that deleting projections and sidecars does not change replay
