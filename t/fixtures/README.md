# Test Fixtures

This directory is for golden protocol fixtures used by tests.

Fixtures should include canonical names, expected event ids, and stable error
codes. Prefer JSON Lines for machine-readable cases. Plain `.names` files may
exist as human-readable mirrors.

Fixture groups:

```text
attacks/
filename-grammar/
gamespec/
event-id/
listing-normalization/
vectors/
single-move/
capture/
ko/
fork/
illegal/
projection/
```

Each fixture should state:

```text
input files
expected event id
expected parser fields or error code
expected replay result
expected SGF or board output when applicable
```

`attacks/` contains hostile, hand-curated specimens with an `expected.verdict`
judgment. These fixtures prove that file bytes, sidecars, projections,
temporary files, listing order, duplicates, and malformed or conflicting event
names do not blur the `GOFTP/1` consensus boundary.
