# Rules Algorithms

This document records the intended rule-core algorithms for GobanFTP. Future
changes should follow this unless a later design decision explicitly changes it.

The goal is not to build the fastest Go engine. The goal is deterministic replay
from filename events, with small code that is easy to test in Perl and
Inline::C.

## Scope

`chinese-area-v1` uses these assumptions:

- board size comes from the game descriptor
- black moves first
- suicide is illegal
- captures are derived during replay
- positional superko is enforced on `play-<point>` moves
- `pass` does not fail merely because the board position is unchanged
- two consecutive passes end normal play
- `resign` ends the game immediately

Scoring details can be deferred to a later result event. Do not mix scoring,
life-and-death inference, or territory estimation into v1 replay legality.

## Board Model

Use a compact board array:

```text
0 empty
1 black
2 white
```

Index points in row-major order from SGF wire coordinates:

```text
aa, ba, ca, ...
ab, bb, cb, ...
```

C may operate on this array and scratch arrays. Perl owns filename parsing, event
ids, DAG traversal, state hash framing, and diagnostics.

C must not expose platform-dependent structs as protocol or hash input.

## Liberties and Captures

Use a complete flood-fill algorithm for v1.

For a `play-<point>` move:

1. Reject the move if the point is outside the board or occupied.
2. Place the stone tentatively on a board copy.
3. For each adjacent opponent group, flood-fill the group and count liberties.
4. Remove each adjacent opponent group with zero liberties.
5. Flood-fill the placed stone's own group after captures.
6. Reject the move as suicide if that group has zero liberties.
7. Otherwise commit the resulting board and captured-point list.

Deduplicate adjacent opponent groups with a visited/group marker. Captured points
used by projections should be emitted in deterministic row-major order.

This is intentionally simple. A 19x19 board has only 361 points, so full
flood-fill per candidate move is acceptable for v1 and much less fragile than
incremental group bookkeeping.

## Ko and Superko

For `chinese-area-v1`, positional superko is authoritative.

After a legal `play-<point>` move is applied, compute the board-position hash and
compare it with ancestor board-position hashes on the move's parent chain. If it
matches any ancestor position, reject the event as superko-illegal.

`pass` and `resign` do not create captures and do not run the positional superko
repetition check. They still advance or end the line according to protocol
rules.

Simple ko does not need a separate v1 algorithm. It falls out of positional
superko because the immediate recapture repeats an ancestor board position.

## State Hash

Use canonical board bytes as the source of truth for state comparison:

```text
"GOFTP-BOARD/1\0" ||
board_size_decimal || "\0" ||
row_major_point_bytes
```

Where each point is one byte with value `0x00`, `0x01`, or `0x02` as defined
above. Hash this with SHA-256 for in-memory replay comparison. The full digest
may be used in memory; there is no need to shorten board-position hashes for
protocol filenames.

Perl should own the framing and hash call. Inline::C may fill the compact point
bytes, but must not decide the protocol framing.

Do not use randomized Zobrist hashing as the v1 authority. A fixed Zobrist table
may be added later only as an optimization, and only if canonical-byte hashes
remain the tested reference.

## Fork Replay

Move events form a DAG, not a single mutable game.

For v1, replay branches by copying parent state:

1. Parse and validate event names.
2. Build parent-child links from move event ids.
3. Start from the empty genesis state.
4. For each legal child candidate, copy the parent board and ancestor hash set.
5. Apply the move on the copy.
6. Store the child state or mark the event illegal with a reason.

Do not mutate a shared parent board while evaluating children. Board copies are
cheap and make forks easy to reason about.

Canonical-line selection remains the policy in `docs/PROTOCOL.md`: follow the
only legal child, stop at competing legal children, and report the fork unless a
documented mode chooses one.

## Good v1 Algorithms

- Full flood-fill for liberties and captures.
- Board-copy replay per event or branch.
- Canonical board-byte SHA-256 for repeated-position checks.
- Ancestor hash sets for positional superko.
- Deterministic row-major ordering for captured stones and diagnostics.
- Small Inline::C functions tested through Perl fixtures.

## Do Not Do Early

- Incremental liberty caches, union-find groups, or mutable group ids as the
  first implementation.
- Zobrist hashes as authoritative replay state.
- CRDT-style branch merging or automatic fork resolution.
- FTP locks, mtime ordering, or server transaction assumptions for legality.
- Reading sidecar snapshots as replay input.
- Territory scoring, seki detection, handicap setup, undo semantics, or advanced
  ko variants inside v1 move legality.

These may become useful later, but they should follow fixtures and measured
need, not speculation.
