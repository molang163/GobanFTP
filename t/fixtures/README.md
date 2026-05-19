# Test Fixtures

This directory is for golden protocol fixtures used by tests.

Fixtures should include canonical names, expected event ids, and stable error
codes. Prefer JSON Lines for machine-readable cases. Plain `.names` files may
exist as human-readable mirrors.

Fixture groups:

```text
attacks/
auth/
cli/
dag/
e2e/
event-id/
filename-grammar/
gamespec/
listing-normalization/
play-flow/
projection/
projection-contract/
projection-visual/
replay/
rules/
sgf/
v1/
vectors/
```

Each fixture should state:

```text
input files
expected event id
expected parser fields or error code
expected replay result
expected SGF or board output when applicable
```

`attacks/` and `v1/attacks/` contain hostile, hand-curated specimens with an
`expected.verdict` judgment. These fixtures check that file bytes, sidecars,
projections, temporary files, listing order, duplicates, substrate metadata,
and malformed or conflicting event names do not blur the `GOFTP/1` consensus
boundary.
