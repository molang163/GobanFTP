# Cross-Substrate Witness Fixtures

These fixtures prove that different enumerable surfaces can expose the same
GOFTP/1 truth. Each case has one `game.name` and one `listing.names` file per
profile.

The current first slice compares:

```text
local-goftp1
ftp-goftp1
git-tree-goftp1
dns-record-goftp1
webdav-goftp1
```

`local-goftp1` uses direct event basenames as if they were direct children under
`events/`. `ftp-goftp1` uses FTP-shaped listing names such as
`events/<event-basename>` and includes ignored shadows under `sidecar/`, `tmp/`,
and `projections/`. `git-tree-goftp1` uses Git-like tree entries with mode,
object id, type, and path metadata; only the path component may expose direct
`events/<event-basename>` children. `dns-record-goftp1` uses one synthetic DNS
record row per line. The harness extracts event basenames from the declared TXT
`event=` value and ignores TTL, owner names, answer order, and non-TXT records.
`webdav-goftp1` uses one synthetic PROPFIND resource row per line. The harness
extracts direct event basenames from `href` path segments and ignores ETag,
Last-Modified, Content-Length, Content-Type, sidecar resources, collection rows,
and recursive descendants.

The harness must reduce every surface to the same accepted event basenames,
`event_set_root`, replay status, canonical ids, board hash, SGF hash, and
diagnostic classes.

Current cases:

```text
minimal       clean three-event line
fork          two legal children of genesis
fork-with-ack two legal children of genesis plus a visible ACK
bad-event-id  hash-mismatched event excluded from the root
```
