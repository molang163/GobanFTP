# Algorithmic Elegance

GobanFTP values elegant algorithms, but only in the engineering sense.

An elegant algorithm in this project is one whose invariants are easier to see
after the cleverness, not harder.

Elegance means:

- fewer hidden states
- clearer inputs and outputs
- deterministic replay from listing names
- focused tests and fixtures
- fewer protocol exceptions
- projections that can be rebuilt instead of repaired by hand

It does not mean short, obscure, tricky, or hard to diagnose.

## Core Pipeline

Core replay should stay shaped like this:

```text
normalized listing names
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

## Algorithm Stack

### Filename Grammar

The filename parser is the protocol front door.

Use a strict grammar. Do not guess, repair, or accept near-misses. Invalid names
should produce diagnostics and stay out of replay.

### Event IDs as a Merkle DAG

Each move event references its parent event id. A single line is a hash chain;
the full event set is a DAG.

This is the right structure for FTP because concurrent listing and delayed
visibility naturally create forks. Forks are preserved and exported; they are not
silently overwritten.

### Topological Replay

Listings are unordered. Replay must build parent-child links, detect missing
parents and collisions, then evaluate legal branches from genesis.

Do not use FTP listing order, `mtime`, entry type, file size, or server metadata
for replay decisions.

### Rule Algorithms

Follow `docs/RULES.md`.

For v1, prefer:

- complete flood-fill for liberties and captures
- board-copy replay for branches
- canonical board-byte SHA-256 for repeated positions
- ancestor hash sets for positional superko

Avoid early:

- incremental liberty caches
- union-find group maintenance
- authoritative Zobrist hashing
- CRDT-style branch merging
- FTP locks or timestamps in legality checks

### SGF Variations

Forks should map naturally to SGF variations. This makes the strange FTP event
DAG interoperable with normal Go tooling.

The main line is a policy choice. Variation export should preserve competing
legal branches where possible.

### Persistent Board Later

Persistent board snapshots and checkpoints are useful later, but they are
optimizations. They must remain rebuildable from listing names and must not
become replay inputs.

## Elegance Gate

Before introducing a clever algorithm, answer these questions:

- What invariant becomes clearer?
- What hidden state or special case disappears?
- What fixture or test proves it?
- Does core replay still work from listing names alone?
- Can a future maintainer explain it in one short paragraph?

If the answer is weak, use the simpler readable algorithm.

## Rejected Cleverness

Do not introduce algorithms that:

- require reading event file contents for replay
- hide filename grammar in C
- depend on source-art layout, whitespace, or comments
- use FTP `mtime`, listing order, locks, file size, or entry type as truth
- merge forks automatically without an explicit documented mode
- replace validation with regex tricks that produce poor diagnostics

