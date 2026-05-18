# GobanFTP Showcase

This is the short viewing path for the hardening/showcase release line.

GobanFTP is already the object:

```text
the listing is the read
the names are the packets
the board is a projection
the race is visible
the source is a ritual surface
```

Do not start by looking for a server, database, or hidden manifest. The game is
the game descriptor basename plus the direct basenames under `events/`.

## 1. Open The Shrine

Start here:

```text
examples/fixtures/ftp-shrine/
```

Then open the game root:

```text
examples/fixtures/ftp-shrine/g1.id-ftp-shrine.s9.r-chinese-area-v1.k7500.pb-daemon.pw-pilgrim/
```

Read the tree as a protocol object:

```text
events/       authoritative move and ack names
sidecar/      marginalia, never consensus
projections/  shadows rebuilt from replay
tmp/          publish staging residue
```

The useful first files are:

```text
events/
projections/oracle/listing.txt
projections/board/current.txt
projections/sgf/main.sgf
```

`projections/oracle/listing.txt` is the transcript-shaped reveal: `NLST events/`
exposes the event basenames; `RETR`, `SIZE`, and `MDTM` remain outside GOFTP/1
replay.

## 2. Verify The Shrine

Run the read-only replay:

```sh
GOBANFTP_ROOT=examples/fixtures/ftp-shrine \
perl -Ilib script/gobanftp replay g1.id-ftp-shrine.s9.r-chinese-area-v1.k7500.pb-daemon.pw-pilgrim
```

Output includes:

```text
gobanftp.replay=ok
canonical_moves=6
legal_moves=6
```

## 3. Open The Race

Now open:

```text
examples/fixtures/ftp-race-shrine/
```

The race fixture has one agreed black move, then two legal white replies with
the same parent. Default replay must stop at the fork. The ack event is visible
in `events/`, but it only affects an explicit ack-assisted replay.

Read:

```text
events/
projections/oracle/verdict.txt
projections/sgf/variations.sgf
projections/oracle/listing.txt
```

Run the conservative replay:

```sh
GOBANFTP_ROOT=examples/fixtures/ftp-race-shrine \
perl -Ilib script/gobanftp replay g1.id-ftp-race-shrine.s9.r-chinese-area-v1.k7500.pb-daemon.pw-pilgrim
```

The process exits `3`. Output includes:

```text
gobanftp.replay=fork
canonical_moves=1
legal_moves=3
```

## 4. Inspect The Oracle

Open:

```text
oracle/goban.pl
```

It may look like a Go board, but it is still only a wrapper around tested
modules. It must not own filename grammar, event ids, DAG replay, rules,
storage, SGF, or projection semantics.

Verify the source-art boundary:

```sh
perl -c oracle/goban.pl
perl oracle/goban.pl --smoke
```

Output includes:

```text
oracle/goban.pl syntax OK
gobanftp.oracle=ok
rules.move=ok
```

## 5. Run The Showcase Gate

The release smoke for this viewing path is:

```sh
prove -lr t/showcase-demo.t
```

It runs the public local command surface: shrine replay, race replay, source-art
oracle smoke, and the unsigned `local-goftp1` v1 witness. The witness smoke
keeps v1 proof machinery visible without moving signed consensus into the
three-minute path.

## Boundaries

Do not read sidecar signatures, event file bytes, FTP metadata, projection
files, or tmp entries as consensus inputs.

Do not add scoring, final result events, signed consensus, or inline assembly
to v0.1. Those belong in a later phase, protocol version, or explicit profile.

Live FTP, WebDAV, signed-HMAC negative matrices, and distribution packaging are
release gates, not part of the three-minute viewing path.
