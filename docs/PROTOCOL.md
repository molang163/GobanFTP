# GOFTP/1 Protocol

GOFTP/1 is a listing-first storage protocol for GobanFTP games.

The core abuse is deliberate:

```text
directory listing = protocol read
directory entry name = packet payload
file bytes = ignored by core replay
```

An implementation must be able to reconstruct the game from full listings of the
game descriptor directory and its `events/` directory. `RETR` is not part of core
replay.

## Directory Layout

Remote root:

```text
/goftp/
  g1.id-minimal.s9.r-chinese-area-v1.k7500.pb-alice.pw-bob/
    events/
      m1.p000001.b.play-dd.pa-genesis.by-alice.n-k31v.h-f98qai37nace5spg
      m1.p000002.w.play-ee.pa-f98qai37nace5spg.by-bob.n-q9az.h-5ivvsvtid3j6u1pg
      a1.t-f98qai37nace5spg.by-bob.n-s7p2.h-tim1sb5lpmd0d4q5
    sidecar/
      f98qai37nace5spg.json
    projections/
      board/
      graveyard/
      sgf/
      oracle/
    tmp/
```

Authoritative:

```text
game descriptor directory name
direct events/ child basenames
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

`sidecar/` may contain pretty JSON, signatures, comments, snapshots, or debug
data. A GOFTP/1 core replay must produce the same result if `sidecar/` is
deleted.

`projections/oracle/listing.txt`, when present, is a reader-facing transcript
projection of the listing-first read path. It is not a replay input; deleting,
rewriting, or rebuilding it must not change event ids, DAG replay, fork
resolution, rules validation, SGF output, or board state.

## Character Set

Protocol names use lowercase ASCII letters, digits, dot, dash, and underscore:

```text
[a-z0-9._-]
```

Dot is structural. Field values must not contain dot.

Reusable atoms:

```text
atom      = [a-z0-9_-]+
event_id  = [0-9a-v]{16}
nonce     = [a-z0-9_-]{1,16}
player    = atom
rules     = atom
game_id   = atom
```

No spaces, slashes, colons, percent escapes, Unicode, or shell-sensitive
characters are allowed inside protocol basenames.

Keep event basenames under 120 bytes where practical.

## Game Descriptor

The game descriptor is the game root basename. There is no required separate
manifest file in GOFTP/1 core.

Format:

```text
g1.id-<game_id>.s<size>.r-<rules>.k<komi_milli>.pb-<black>.pw-<white>
```

Example:

```text
g1.id-alice-bob-001.s19.r-chinese-area-v1.k7500.pb-alice.pw-bob
```

Fields:

```text
g1              protocol family
id-*            game id atom
s19             board size, integer 2..26, no leading zero
r-*             rules id atom
k7500           komi in milli-points, integer >= 0, no leading zero except 0
pb-*            black player id atom
pw-*            white player id atom
```

The game descriptor basename is included in event hash input, so the same event
name in two games has different identity.

## Event Name Grammar

GOFTP/1 events are names under `events/`. Event entries may be zero-byte files or
directories. Readers ignore the type.

Move event:

```text
m1.p<ply>.<color>.<action>.pa-<parent>.by-<player>.n-<nonce>.h-<event_id>
```

Ack event:

```text
a1.t-<target>.by-<player>.n-<nonce>.h-<event_id>
```

Fields:

```text
m1 / a1      event version
ply          six decimal digits, author-claimed hand number
color        b or w
action       play-<point>, pass, or resign
parent       genesis or a 16-character event id
player       player id from game descriptor
nonce        short lowercase ASCII nonce chosen by publisher
event_id     first 16 chars of the event hash encoding
target       ack target event id
```

Golden examples for `g1.id-minimal.s9.r-chinese-area-v1.k7500.pb-alice.pw-bob`:

```text
m1.p000001.b.play-dd.pa-genesis.by-alice.n-k31v.h-f98qai37nace5spg
m1.p000002.w.play-ee.pa-f98qai37nace5spg.by-bob.n-q9az.h-5ivvsvtid3j6u1pg
a1.t-f98qai37nace5spg.by-bob.n-s7p2.h-tim1sb5lpmd0d4q5
```

Unknown direct move or ack event versions, such as `m2.*` or `a2.*`, are not
replayed as GOFTP/1 events. They remain visible listing inputs and must produce
a stable diagnostic equivalent to:

```text
diagnostic code=parse_event name=<event-basename> error=event.version
```

After the diagnostic, they are excluded from event id maps, DAG construction,
rule replay, and projection input. Recursive descendants such as
`events/<name>/child` are not direct event entries and are ignored by listing
normalization before parsing.

## Coordinates

Wire coordinates use SGF-style points, not human Go coordinates.

For a 19x19 board:

```text
aa = top left
sa = top right
as = bottom left
ss = bottom right
```

The letter `i` is not skipped in wire coordinates. UI code may display human
coordinates such as `Q16`.

Point grammar:

```text
point = [a-z][a-z]
```

Both coordinates must be inside the board size from the game descriptor.

## Event ID

The event id is derived from the canonical event name without the final
`.h-<event_id>` field.

Preimage:

```text
"GOFTP-EVENT/1\0" ||
game_descriptor_basename || "\0" ||
event_name_without_hash
```

`event_name_without_hash` is the direct `events/` child basename with the final
`.h-<event_id>` segment removed, including the preceding dot. It does not include
`events/`, any parent path, or recursive child names.

Hash:

```text
SHA256(preimage)
```

Encoding:

```text
lowercase base32hex without padding
```

The event id stored in the filename is the first 16 encoded characters. Base32hex
uses `0-9a-v`, so it stays lowercase and FTP-safe. Sixteen characters is an
80-bit short id. If two different event names produce the same short id, the
client must report a collision and stop automatic replay at the affected branch.

## Publishing

Default publish uses a zero-byte temporary file and rename:

```text
TYPE I
STOR tmp/<player>-<nonce>.part
RNFR tmp/<player>-<nonce>.part
RNTO events/<event_name>
```

Pure listing mode may use a directory event instead:

```text
MKD events/<event_name>
```

Both forms are equivalent to readers. A reader only sees `events/<event_name>`.

If the final event already exists, publishing is idempotent. If the server
allows overwriting, clients should avoid overwriting by using unique nonces and
should treat a changed event name as a separate event.

Temporary entries under `tmp/` are never replay inputs.

## Synchronization

Core sync:

```text
MLSD events/
```

Fallback:

```text
NLST events/
```

`MLSD` facts may be used for optimization and diagnostics. They must not affect
replay. Listing order must be ignored; clients sort parsed events locally.

Directory mtime may be used to skip polling, but clients must periodically do a
full listing.

## DAG Semantics

Move events form a DAG:

```text
genesis -> event A -> event B
                  \-> event B'
```

Rules:

- `pa-genesis` is valid only for the first black move.
- other parents must refer to an existing move event id.
- parent ids must refer to move events, not ack events.
- `ply` must equal parent depth plus one for a canonical replay candidate.
- color must match the expected turn.
- `by-<player>` must match the color binding in the game descriptor.
- the move must be legal under the game rules.
- illegal events stay visible but are not canonical moves.
- multiple legal children of one parent are forks.

Ack events are not moves. They may influence UI and optional conflict resolution,
but the move DAG is built from `m1.*` events only. Ack targets must refer to move
event ids. Ack `by-<player>` values must be one of the game descriptor players.

Diagnostics should distinguish these categories:

```text
grammar-invalid
event-id-invalid
dag-invalid
rules-invalid
unknown-version
```

## Canonical Line

Default mode is conservative:

1. Start at genesis.
2. At each step, consider legal children of the current tip.
3. If there is exactly one legal child, append it.
4. If there are multiple legal children, stop and report a pending fork.

A reserved demo mode may choose a deterministic child for projection:

```text
lowest event_id lexicographically
```

Demo mode must be labeled as such. Do not pretend it is player consensus.

Ack-assisted mode is explicit and optional. It may choose a fork if exactly one
competing legal child has at least one ack by the opponent of that child move's
color. Same-player acks, acks for non-competing moves, and acks for illegal
moves do not resolve a fork. If no competing child is acked, or if multiple
competing children are acked, stop and report conflict.

## Rules: chinese-area-v1

Initial assumptions:

- board size comes from the game descriptor
- black moves first
- suicide is illegal
- positional superko is enforced on `play-<point>` moves by replaying ancestor
  board positions
- `pass` does not fail merely because the board position is unchanged
- two consecutive passes end normal play
- resign ends the game immediately
- scoring details may be deferred to a future result event

Captures are derived during replay. Captured stones must not be represented by
deleting old event entries.

## Sidecar Files

Sidecar files are optional:

```text
sidecar/<event_id>.json
sidecar/<event_id>.sig
```

Allowed uses:

- pretty explanation
- comments
- external signatures
- diagnostics
- cached board snapshots

Forbidden use:

- any field required for GOFTP/1 core replay

If sidecar content disagrees with the filename event, the filename wins and the
sidecar is reported as stale or misleading.
