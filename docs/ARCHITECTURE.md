# Architecture

GobanFTP has three layers:

```text
listing layer     authoritative filename event log
projection layer  board directory, graveyard, SGF, oracle outputs
ritual layer      FTP command vocabulary, source art, human-readable spell files
```

The listing layer must remain boring and deterministic. The ritual layer may be
strange.

## Surface Work Boundary

Surface work is allowed to make the project look like a protocol-abuse object:
README wording, ASCII source art, projection labels, examples, comments, and
human-readable sidecar text may be theatrical.

Surface work must not change the listing layer contract. In particular, it must
not change filename grammar, event id preimages, replay inputs, storage
semantics, or the rule algorithms used to decide legality.

`GobanFTP::Surface::*` modules live after witness and projection assembly. They
may format a `GobanFTP::Witness` hash and already-rendered projection text for
terminal or static inspection, but they must not read storage, parse event
names, compute hashes, replay rules, or decide profile acceptance.

## Algorithm Shape

Core replay should remain a deterministic pipeline:

```text
profile listing read
  -> normalized listing names
  -> typed filename events
  -> event ids
  -> DAG
  -> canonical line or fork report
  -> board state
  -> rebuildable projections
```

Each stage should have a narrow contract and tests. A stage may reject input with
diagnostics, but it must not fetch file contents or inspect projection state to
decide consensus.

`GobanFTP::Witness` is the production read-only assembly point for this proof.
It takes a declared profile id, a game descriptor basename, and raw profile
listing rows; asks the profile adapter for visible listing names; computes
`event_set_root`; replays the normalized event candidates; and reports stable
diagnostic classes. For unsigned profiles, replay intentionally sees normalized
event-looking basenames even when the root gate later rejects them, so parser and
event-id failures remain observable diagnostics instead of disappearing as
filtered input.

See `docs/ALGORITHMS.md` for the algorithmic elegance gate and `docs/RULES.md`
for v1 rule-core algorithms.

## Runtime Components

Current Perl module layout:

```text
lib/GobanFTP/
  GameSpec.pm       game descriptor dirname parsing and formatting
  Filename/Grammar.pm strict event filename parser and formatter
  Event.pm          typed event from filename
  EventID.pm        domain-separated filename event ids
  EventSetRoot.pm   draft accepted event-set witness roots
  Listing.pm        normalize NLST/MLSD/local directory names
  Coord.pm          coordinate parsing and SGF conversion
  Board.pm          board state
  Rules.pm          high-level rule API
  Rules/C.pm        Inline::C board mechanics
  AckPublisher.pm   ack event publication
  MovePublisher.pm  move event publication
  DAG.pm            event graph, forks, canonical line
  Diagnostics.pm    stable diagnostic code/class helpers
  Replay.pm         validate and replay a canonical line
  Redact.pm         diagnostic secret redaction
  Profile.pm        v1 profile registry
  Profile/Adapter.pm read-only profile listing normalizers
  Profile/SignedHMAC.pm signed-HMAC event acceptance gate
  Witness.pm        profile witness assembly and event_set_root reports
  Store.pm          storage interface
  Store/Config.pm   environment-backed store configuration
  Store/Local.pm    local filesystem backend
  Store/FTP.pm      FTP backend
  Store/GitTree.pm  read-only Git tree backend
  Store/WebDAV.pm   WebDAV backend
  Surface/WitnessView.pm witness/projection-only inspection renderer
  SGF.pm            SGF export
  Projection.pm     projections/ output generation
  Oracle/Smoke.pm   source-art smoke scenario
  CLI.pm            command entry points
```

Current script:

```text
oracle/goban.pl          source-art smoke wrapper
script/gobanftp          local/FTP/Git-tree/WebDAV CLI entry point
script/live-ftp-smoke    disposable live FTP smoke helper
```

`goban.pl` is a source-art surface and parameter dispatcher. It should call
modules rather than contain protocol, DAG, rules, or smoke-scenario logic inline.

## Inline::C Boundary

Inline::C should own tight board mechanics only:

```text
count liberties
find connected group
apply captures
produce compact canonical board bytes
```

Perl should own:

```text
FTP operations
filename parsing
event id calculation
DAG traversal
ack policy
SGF export
CLI/TUI
projection writing
```

This keeps the theatrical part maintainable.

Perl owns filename grammar, event ids, and any state byte framing. C must not
emit platform-dependent binary structs into a hash.

Rule algorithms must follow `docs/RULES.md`. In particular, v1 should use full
flood-fill and board-copy replay before considering incremental group caches or
authoritative Zobrist hashing.

## Storage Interface

All higher layers should use a storage abstraction:

```text
list_names(path) -> names
publish_event_name(game_root, event_name)
mkdir(path)
exists_name(path, name)
```

`Store::Local`, `Store::FTP`, `Store::GitTree`, and `Store::WebDAV` are
implemented behind the same interface. Local replay remains the simplest
debugging path; FTP, Git tree, and WebDAV tests should preserve the same
listing-first behavior instead of adding server-metadata dependencies. FTP
publishes through `tmp/` plus `RNTO`; Git tree is read-only and enumerates a
declared tree snapshot; WebDAV publishes through a zero-byte `tmp/` resource
plus `MOVE` and confirms with a fresh `PROPFIND Depth: 1`.

`get(path)` may exist for sidecars and diagnostics, but it must not be required
for core replay.

## Projection Rules

Projection files are rebuilt from replay outputs and authoritative listing
names:

```text
projections/board/
projections/board/current.txt
projections/board/points/<point>.txt
projections/graveyard/
projections/graveyard/captures.txt
projections/sgf/main.sgf
projections/sgf/variations.sgf
projections/oracle/board.txt
projections/oracle/listing.txt
projections/oracle/verdict.txt
```

Projection rebuilds may overwrite projection files. They must not edit
authoritative event names.

`Projection.pm` consumes replay result structures and event names only. It must
not read event file bytes, sidecar files, temporary files, or existing projection
state. `graveyard/captures.txt` is derived from `canonical_steps[*].captures`,
not by diffing rendered board files. `oracle/listing.txt` is a reader-facing
transcript derived from the same replay/listing inputs; its text is not a replay
input.

`main.sgf` is the conservative canonical prefix. `variations.sgf` renders the
legal branch tree from `legal_children_by_parent` and `events_by_id`. Verdict
status priority is:

```text
validation > fork > ok
```

## Testing Strategy

Core test groups:

```text
t/gamespec.t
t/filename-grammar.t
t/event-id.t
t/coord.t
t/dag.t
t/replay.t
t/sgf.t
t/projection-rebuild.t
t/store-local.t
t/store-contract.t
t/cli.t
t/store-ftp.t
t/store-ftp-mock.t
t/ftp-cli-parity.t
t/source-art.t
```

Test fixtures should live under:

```text
t/fixtures/
```

Human-readable examples should live under:

```text
examples/fixtures/
```

FTP integration tests should be skipped unless `GOBANFTP_FTP_TEST=1` is set.
