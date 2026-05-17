# Test Fixtures

This directory is for golden protocol fixtures used by tests.

Fixtures should include canonical names, expected event ids, and stable error
codes. Prefer JSON Lines for machine-readable cases. Plain `.names` files may
exist as human-readable mirrors.

Planned fixture groups:

```text
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
