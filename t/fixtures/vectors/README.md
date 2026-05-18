# Vector Fixtures

This directory contains public golden vectors for protocol calculations that
other implementations should be able to reproduce without importing Perl code.

`event-set-root.jsonl` covers the draft `GOFTP-EVENT-SET/1` witness root. The
root accepts only direct GOFTP/1 `m1` and `a1` event basenames that parse and
verify their filename event ids for the given game descriptor. DAG-invalid and
rule-invalid packets are still accepted into the root when their filename
grammar and event id are valid. Malformed names, unknown versions, bad event
ids, recursive children, and ignored surfaces stay outside the root.

`v1-witness.jsonl` freezes the v1 witness fields computed from
`t/fixtures/v1/cross-substrate/` for `local-goftp1`, `ftp-goftp1`,
`git-tree-goftp1`, `dns-record-goftp1`, and `webdav-goftp1`. Each row names the
input listing fixture and records the accepted events, rejected diagnostic
classes, event set root, replay status, canonical and legal ids, and projection
hashes produced by `GobanFTP::Test::WitnessHarness`.
