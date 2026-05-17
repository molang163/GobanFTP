# Cross-Substrate Witness Fixtures

These fixtures prove that different enumerable surfaces can expose the same
GOFTP/1 truth. Each case has one `game.name` and one `listing.names` file per
profile.

The current first slice compares:

```text
local-goftp1
ftp-goftp1
```

`local-goftp1` uses direct event basenames as if they were direct children under
`events/`. `ftp-goftp1` uses FTP-shaped listing names such as
`events/<event-basename>` and includes ignored shadows under `sidecar/`, `tmp/`,
and `projections/`.

The harness must reduce both surfaces to the same accepted event basenames,
`event_set_root`, replay status, board hash, SGF hash, and diagnostic classes.

Current cases:

```text
minimal       clean three-event line
fork          two legal children of genesis
bad-event-id  hash-mismatched event excluded from the root
```
