# GobanFTP

A Go game can live in an FTP listing.

The game is not in file contents.
It is not in timestamps.
It is not in server order.

The record is the game descriptor name and the direct names under `events/`.
Everything else is projection, annotation, cache, or stage machinery.

GobanFTP is a playable `GOFTP/1` runtime: a small protocol rite where FTP
directory entries are move packets, replay is deterministic, and the board is
rebuilt from names alone.

```text
Names are packets.
Listing is reading.
Board is projection.
SGF is witness.
FTP is the altar, not the authority.
```

The strange surface is deliberate. The replay contract is not negotiable.

## Requirements

Runtime:

```text
Perl 5.34+
Digest::SHA
HTTP::Tiny
MIME::Base64
Net::FTP
```

Build and test gates use:

```text
make
```

Optional:

```text
Inline
Inline::C
```

`Inline::C` is a board-mechanics acceleration path. It is not a protocol
requirement and must not own naming, hashing, replay, storage, SGF, or CLI
semantics. See `docs/BUILD.md` for the full build and test gate.

## One-Minute Witness

Run the shrine fixture:

```sh
GOBANFTP_ROOT=examples/fixtures/ftp-shrine \
perl -Ilib script/gobanftp play --once g1.id-ftp-shrine.s9.r-chinese-area-v1.k7500.pb-daemon.pw-pilgrim
```

Expected shape:

```text
gobanftp.play=ok
events=7
canonical_moves=6
worldline.status=main
  a b c d e f g h i
9 . . . . . . . . .
8 . . . . . . . . .
7 . . . . . . . . .
6 . . . B . . . . .
5 . . . B . W . . .
4 . . . B W W . . .
3 . . . . . . . . .
2 . . . . . . . . .
1 . . . . . . . . .
```

Now watch a race stay visible instead of being hidden by FTP ordering:

```sh
GOBANFTP_ROOT=examples/fixtures/ftp-race-shrine \
perl -Ilib script/gobanftp replay g1.id-ftp-race-shrine.s9.r-chinese-area-v1.k7500.pb-daemon.pw-pilgrim
```

The process exits `3`; output includes:

```text
diagnostic ... code=fork parent_id=hihat4p8r6gaeuts
gobanftp.replay=fork
canonical_moves=1
legal_moves=3
```

Fast paths:

```text
Showcase: docs/SHOWCASE.md
Protocol: docs/PROTOCOL.md
Profiles: docs/PROFILES.md
Grammar:  docs/GRAMMAR.md
v1.0 DoD: docs/V1_DOD.md
Attacks:  docs/ATTACKS.md
Art:      docs/SOURCE_ART.md
Build:    docs/BUILD.md
CLI:      docs/CLI.md
```

## Open This First

For a guided three-minute viewing path, read:

```text
docs/SHOWCASE.md
```

The browsable specimen is here:

```text
examples/fixtures/ftp-shrine/
```

The race specimen is here:

```text
examples/fixtures/ftp-race-shrine/
```

Open the game root, then read:

```text
g1.id-ftp-shrine.s9.r-chinese-area-v1.k7500.pb-daemon.pw-pilgrim/
  events/
    m1.p000001.b.play-dd.pa-genesis.by-daemon.n-altar1.h-0agr68rv1sp5qi21
  sidecar/
  projections/
  tmp/
```

The useful first files are:

```text
examples/fixtures/ftp-shrine/README.md
examples/fixtures/ftp-shrine/g1.id-ftp-shrine.s9.r-chinese-area-v1.k7500.pb-daemon.pw-pilgrim/events/
examples/fixtures/ftp-shrine/g1.id-ftp-shrine.s9.r-chinese-area-v1.k7500.pb-daemon.pw-pilgrim/projections/oracle/listing.txt
examples/fixtures/ftp-shrine/g1.id-ftp-shrine.s9.r-chinese-area-v1.k7500.pb-daemon.pw-pilgrim/projections/board/current.txt
examples/fixtures/ftp-shrine/g1.id-ftp-shrine.s9.r-chinese-area-v1.k7500.pb-daemon.pw-pilgrim/projections/sgf/main.sgf
oracle/goban.pl
```

Read the tree like this:

```text
g1.../        names the game
events/      names the moves and acknowledgements
sidecar/     may explain, but cannot decide
projections/ may display, but cannot testify
tmp/         is publishing residue
```

Core replay reads listings. It ignores event file bytes, FTP `mtime`, file
size, entry type, and listing order.

The first public inspection should answer these questions:

```text
Can I see the packets?      yes: events/ entry names
Can I see the board?        yes: projections/board/current.txt
Can I see the FTP abuse?    yes: projections/oracle/listing.txt
Can I see a network race?   yes: examples/fixtures/ftp-race-shrine/
Can I delete the shadows?   yes: projections are rebuildable
```

## Protocol Contract

`GOFTP/1` is listing-first storage.

Authoritative inputs:

```text
game descriptor directory basename
direct child basenames under events/
```

Ignored by core replay:

```text
entry type
file bytes
file size
FTP listing order
FTP mtime
sidecar/**
projections/**
tmp/**
```

`RETR`, `SIZE`, `MDTM`, and server ordering are not part of replay.

The shrine also includes a calm FTP transcript at:

```text
examples/fixtures/ftp-shrine/g1.id-ftp-shrine.s9.r-chinese-area-v1.k7500.pb-daemon.pw-pilgrim/projections/oracle/listing.txt
```

That transcript is a projection for readers. It demonstrates that `NLST events/`
is the read that exposes event basenames, while `RETR`, `SIZE`, and `MDTM` stay
outside GOFTP/1 replay.

Event ids are derived from canonical filename context, not from file contents.
The event hash input includes the game descriptor basename and the event name
without its final `.h-<event_id>` field. The visible event id is the first 16
characters of the lowercase base32hex SHA-256 output.

A normal line of play is a hash chain. All known play is a DAG. Forks are
visible states; they are not silently resolved by write order, timestamps, or
metadata. Ack-assisted recovery is explicit and optional.

Protocol names stay boring:

```text
[a-z0-9._-]
```

No secret belongs in a filename. Filenames are public.

## Form Of The Rite

Clients list `events/`, parse event basenames, verify filename-derived event
ids, rebuild a move DAG, validate a canonical prefix, then render projections.

The intended stack is:

```text
listing names
  -> filename grammar
  -> event ids
  -> DAG
  -> replay
  -> board state
  -> SGF and projections
```

The protocol should feel like a network ritual. The data formats should remain
plain enough for maintainers to inspect.

## Projections Are Shadows

These paths are outputs, not truth:

```text
projections/board/
projections/graveyard/
projections/sgf/
projections/oracle/
```

They are rebuilt from replay results and event names. Delete them and the game
must still replay. Rewrite them and the game must not change.

`sidecar/` may contain comments, pretty JSON, stale notes, signatures, or debug
material. It is marginalia. If sidecar content disagrees with an event filename,
the filename wins.

## Source Art Boundary

`oracle/goban.pl` may look like a Go board.

It must still run. It must pass `perl -c`. It may dispatch to smoke tests and
modules. It must not own filename grammar, event id calculation, DAG replay,
rule legality, storage behavior, SGF output, or projection rebuilding.

Whitespace, comments, POD, and ASCII glyphs are ritual surface. They are not
consensus inputs.

## Runtime State

This is a runtime prototype, not only a concept document.

Package release `0.001` corresponds to the `v0.1` hardening/showcase milestone:
the consensus boundary is frozen for this release, and the release work is
packaging, docs, examples, gates, and playability.

Implemented surfaces include:

- strict game descriptor and event filename parsing
- filename-derived event ids
- DAG construction and conservative replay
- Go rules in Perl for `chinese-area-v1`
- optional `Inline::C` board-mechanics backend
- SGF rendering
- rebuildable board, graveyard, SGF, and oracle projections
- local filesystem store
- FTP store with mock tests and gated live tests
- WebDAV store with mock and CLI parity tests
- CLI commands for create, publish, verify, replay, project, SGF, play, watch
- explicit ack-assisted fork recovery
- browsable `ftp-shrine` fixture
- browsable `ftp-race-shrine` fork fixture

Deferred surfaces include final scoring/result events and any signed consensus
profile. Sidecar signatures may be shown as external attestations, but they are
not `GOFTP/1` replay inputs.

## Create A Disposable Game

Keep the first run in a scratch root:

```sh
tmp="$(mktemp -d)"
export GOBANFTP_ROOT="$tmp"

perl -Ilib script/gobanftp create-game --id demo --size 9 --black alice --white bob
```

Publish moves:

```sh
perl -Ilib script/gobanftp publish-move g1.id-demo.s9.r-chinese-area-v1.k7500.pb-alice.pw-bob aa
perl -Ilib script/gobanftp publish-move g1.id-demo.s9.r-chinese-area-v1.k7500.pb-alice.pw-bob play-bb
perl -Ilib script/gobanftp publish-move g1.id-demo.s9.r-chinese-area-v1.k7500.pb-alice.pw-bob pass
perl -Ilib script/gobanftp publish-move g1.id-demo.s9.r-chinese-area-v1.k7500.pb-alice.pw-bob resign
```

Render or play from the terminal:

```sh
perl -Ilib script/gobanftp play --once g1.id-demo.s9.r-chinese-area-v1.k7500.pb-alice.pw-bob
perl -Ilib script/gobanftp play --move aa g1.id-demo.s9.r-chinese-area-v1.k7500.pb-alice.pw-bob
perl -Ilib script/gobanftp play --ack <event-id> g1.id-demo.s9.r-chinese-area-v1.k7500.pb-alice.pw-bob
perl -Ilib script/gobanftp play g1.id-demo.s9.r-chinese-area-v1.k7500.pb-alice.pw-bob
perl -Ilib script/gobanftp watch --once g1.id-demo.s9.r-chinese-area-v1.k7500.pb-alice.pw-bob
```

Inspect the authoritative record:

```sh
find "$GOBANFTP_ROOT" -path '*/events/*' -exec basename {} \; | sort
```

Those names are the packets. The file contents are not the game.

## Fixture Commands

Replay the shrine fixture:

```sh
GOBANFTP_ROOT=examples/fixtures/ftp-shrine \
perl -Ilib script/gobanftp replay g1.id-ftp-shrine.s9.r-chinese-area-v1.k7500.pb-daemon.pw-pilgrim
```

Rebuild its projections:

```sh
GOBANFTP_ROOT=examples/fixtures/ftp-shrine \
perl -Ilib script/gobanftp project g1.id-ftp-shrine.s9.r-chinese-area-v1.k7500.pb-daemon.pw-pilgrim
```

Replay the race fixture:

```sh
GOBANFTP_ROOT=examples/fixtures/ftp-race-shrine \
perl -Ilib script/gobanftp replay g1.id-ftp-race-shrine.s9.r-chinese-area-v1.k7500.pb-daemon.pw-pilgrim
```

The process exits `3` when conservative replay reaches the visible fork.

## Source-Art Smoke

Run the source-art oracle smoke:

```sh
perl -c oracle/goban.pl
perl oracle/goban.pl --smoke
```

## FTP Mode

Set `GOBANFTP_STORE=ftp` plus FTP connection variables to run the same
`create-game`, `verify`, `replay`, `sgf`, `publish-move`, `publish-ack`,
`play`, and `watch` flow against FTP listings.

Common variables:

```text
GOBANFTP_STORE=ftp
GOBANFTP_FTP_HOST
GOBANFTP_FTP_USER
GOBANFTP_FTP_PASSWORD
GOBANFTP_FTP_ROOT
GOBANFTP_FTP_PORT
GOBANFTP_FTP_PASSIVE
GOBANFTP_FTP_TIMEOUT
GOBANFTP_FTP_PUBLISH_MODE
```

Projection writes are supported only with the local store for now. In FTP mode,
`project` and `sgf --write` are rejected. Plain `sgf`, `verify`, `replay`,
`play`, and `watch` can read FTP listings without reading event file contents.

Live FTP tests are gated. They do not run by default.

## WebDAV Mode

Set `GOBANFTP_STORE=webdav` plus a root WebDAV collection URL to run the same
listing-first flow against WebDAV collections.

Common variables:

```text
GOBANFTP_STORE=webdav
GOBANFTP_WEBDAV_URL
GOBANFTP_WEBDAV_USER
GOBANFTP_WEBDAV_PASSWORD
GOBANFTP_WEBDAV_TOKEN
GOBANFTP_WEBDAV_TIMEOUT
GOBANFTP_WEBDAV_CLASS
GOBANFTP_WEBDAV_PUBLISH_MODE
```

`GOBANFTP_WEBDAV_URL` is required in WebDAV mode. Replay reads
`events/` with `PROPFIND Depth: 1` and uses only direct href basenames. ETags,
Last-Modified, content length, display names, locks, resource bodies, `tmp/`,
sidecars, and projections are ignored. Publishing writes a zero-byte temporary
resource under `tmp/`, moves it to `events/<event-name>`, then confirms
visibility with a fresh `PROPFIND`.

Projection writes are still local-only. In WebDAV mode, `project` and
`sgf --write` are rejected; plain `sgf`, `verify`, `replay`, `play`, and
`watch` can read WebDAV listings without reading event resource bodies.

## Where The Pieces Live

```text
.
|-- README.md              this text
|-- docs/
|   |-- SHOWCASE.md        short viewing path
|   |-- PROTOCOL.md        GOFTP/1 storage protocol
|   |-- ARCHITECTURE.md    implementation layers and boundaries
|   |-- ALGORITHMS.md      elegance gate and replay shape
|   |-- RULES.md           v1 rule-core algorithms
|   |-- CLI.md             command behavior
|   |-- DIAGNOSTICS.md     stable diagnostics and redaction
|   |-- DECISIONS.md       durable design decisions
|   |-- BUILD.md           local build and test notes
|   |-- ROADMAP.md         staged plan
|   `-- GLOSSARY.md        project terms
|-- oracle/
|   `-- goban.pl           source-art smoke wrapper
|-- lib/GobanFTP/          Perl implementation modules
|-- script/gobanftp        CLI entry point
|-- examples/fixtures/     browsable mirrored games
`-- t/                     tests
```

Generated distribution archives, unpacked distribution directories, `blib/`,
`_Inline/`, `Makefile`, `MYMETA.*`, and `pm_to_blib` are local build artifacts
unless they were regenerated for the exact checkpoint being distributed.

## Maintainer Order

Before changing protocol behavior, read:

1. `docs/PROTOCOL.md`
2. `docs/ARCHITECTURE.md`
3. `docs/ALGORITHMS.md`
4. `docs/RULES.md`
5. `docs/ROADMAP.md`
6. `docs/DECISIONS.md`

Tighten the existing protocol before inventing another one.
