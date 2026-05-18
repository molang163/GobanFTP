# Attack Fixtures

Each child directory is one small, inspectable attack specimen. Every specimen
must contain `game.name`, `listing.names`, and `expected.verdict`.

The v1 gallery gate in `t/v1-attack-fixtures.t` checks specimen coverage and the
verdict field contract. The behavior harness in `t/attack-fixtures.t` reads the
same files, then copies any local poison material into a temporary game root
before running the command under test.

`listing.names` records the hostile observed names. It may include ignored
surfaces such as `sidecar/`, `projections/`, or `tmp/`; only direct event
basenames are replay candidates.

`mtimes.tsv`, when present, assigns explicit epoch-second modification times to
materialized local event files before the command under test runs. Those times
are attack input, not consensus input.

`expected.verdict` is the public judgment for the specimen. It must include at
least these fields:

```text
attack
mode
command
status
exit
game
events
event_set_count
event_set_root
canonical_moves
legal_moves
diagnostic.class
consensus_inputs
ignored_inputs
note
```

It names the expected exit, event-set witness, replay shape, diagnostic,
consensus inputs, ignored inputs, and the short human note that explains the
specimen. `GOFTP/1` attack fixtures remain unsigned; sidecar signatures, if a
fixture ever carries one, are ignored shadow input unless a separate signed
profile says otherwise.

The v1 gate requires the gallery to contain at least:

```text
bad-mtime
bad-payload
bad-list-order
duplicate-event
bad-event-id
future-version
missing-parent
fake-player
fork-race
poisoned-sidecar
projection-poison
tmp-poison
dangling-ack
```
