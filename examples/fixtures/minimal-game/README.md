# Minimal Game Fixture

This is the smallest complete human-readable GOFTP/1 example in the repository.
It uses the golden event names from `docs/PROTOCOL.md`.

Authoritative inputs:

```text
g1.id-minimal.s9.r-chinese-area-v1.k7500.pb-alice.pw-bob/
  events/
```

Everything under `projections/` is generated from the game descriptor basename
and direct `events/` child basenames. It may be deleted and rebuilt with:

```sh
perl -Ilib script/gobanftp project examples/fixtures/minimal-game/g1.id-minimal.s9.r-chinese-area-v1.k7500.pb-alice.pw-bob
```

Event file contents are explanatory only and are ignored by core replay.
