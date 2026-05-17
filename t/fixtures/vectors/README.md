# Vector Fixtures

This directory contains public golden vectors for protocol calculations that
other implementations should be able to reproduce without importing Perl code.

`event-set-root.jsonl` covers the draft `GOFTP-EVENT-SET/1` witness root. The
root accepts only direct GOFTP/1 `m1` and `a1` event basenames that parse and
verify their filename event ids for the given game descriptor. DAG-invalid and
rule-invalid packets are still accepted into the root when their filename
grammar and event id are valid. Malformed names, unknown versions, bad event
ids, recursive children, and ignored surfaces stay outside the root.
