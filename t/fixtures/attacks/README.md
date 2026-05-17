# Attack Fixtures

Each child directory is one small, inspectable attack specimen. The harness in
`t/attack-fixtures.t` reads `game.name`, `listing.names`, and
`expected.verdict`, then copies any local poison material into a temporary game
root before running the command under test.

`listing.names` records the hostile observed names. It may include ignored
surfaces such as `sidecar/`, `projections/`, or `tmp/`; only direct event
basenames are replay candidates.

`expected.verdict` is the public judgment for the specimen. It names the
expected exit, event-set witness, replay shape, diagnostic, consensus inputs,
and ignored inputs.
