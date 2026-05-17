# FTP Shrine Fixture

This fixture is a standalone GOFTP/1 shrine for browsing, not a new protocol.
Open the directory tree and the central trick should be visible:

```text
names are packets
events are the altar
sidecar is marginalia
projections are shadows
tmp is backstage
```

The game root is:

```text
g1.id-ftp-shrine.s9.r-chinese-area-v1.k7500.pb-daemon.pw-pilgrim/
```

The only replay inputs are that game descriptor basename and the direct child
basenames under `events/`. The event file bytes, `sidecar/`, `projections/`, and
`tmp/` are decorative or rebuildable.

For a transcript-shaped view of the same boundary, read:

```text
g1.id-ftp-shrine.s9.r-chinese-area-v1.k7500.pb-daemon.pw-pilgrim/projections/oracle/listing.txt
```

It is a projection. The transcript shows `NLST events/` returning event
basenames, then shows `RETR`, `SIZE`, and `MDTM` as non-replay FTP operations.

Rebuild the projection files with:

```sh
GOBANFTP_ROOT=examples/fixtures/ftp-shrine \
perl -Ilib script/gobanftp project g1.id-ftp-shrine.s9.r-chinese-area-v1.k7500.pb-daemon.pw-pilgrim
```

Replay the shrine with:

```sh
GOBANFTP_ROOT=examples/fixtures/ftp-shrine \
perl -Ilib script/gobanftp replay g1.id-ftp-shrine.s9.r-chinese-area-v1.k7500.pb-daemon.pw-pilgrim
```
