# FTP Race Shrine Fixture

This fixture is a small GOFTP/1 race exhibit. It is not a new protocol.

The game has one agreed move, then two legal white replies with the same parent.
Default replay must stop at the fork. The ack event is present so explicit
ack-assisted replay can show which branch was acknowledged, but default replay
does not silently choose it.

Open:

```text
g1.id-ftp-race-shrine.s9.r-chinese-area-v1.k7500.pb-daemon.pw-pilgrim/
```

Read:

```text
events/                         authoritative move and ack names
projections/oracle/verdict.txt  conservative fork verdict
projections/sgf/variations.sgf  both race branches
projections/oracle/listing.txt  transcript projection of NLST events/
sidecar/                        marginalia, not consensus
tmp/                            publish staging residue
```

Rebuild the conservative projections with:

```sh
GOBANFTP_ROOT=examples/fixtures/ftp-race-shrine \
perl -Ilib script/gobanftp project g1.id-ftp-race-shrine.s9.r-chinese-area-v1.k7500.pb-daemon.pw-pilgrim
```

The command exits `3` because the default policy reports the fork.
