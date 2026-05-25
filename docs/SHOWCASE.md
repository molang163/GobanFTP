# GobanFTP Showcase

This is the short viewing path for the hardening/showcase release line.

Start with the fixture and static bundle boundary:

```text
the listing is the read
the names are the packets
the board is a projection
the race is visible
the source is a ritual surface
```

Do not start by looking for a hosted service, database, or hidden manifest. The
game is the game descriptor basename plus the direct basenames under `events/`.

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

To materialize a direct-open static bundle from checked-in fixtures only:

```sh
perl -Ilib script/gobanftp showcase --out showcase-v1.1
```

The generated directory contains `index.html`, clean and fork witness HTML,
`demo-transcript.txt`, `release-evidence.txt`, and `roots.json`. These files
are local inspection outputs only; they are not replay inputs. Generated bundle is static; optional P2 loopback preview helper is local-only/read-only and not hosted UI/deploy.

The generated index links only to the fixed local artifact set. Witness HTML
pages add same-document fragment navigation between the supplied witness summary
and projection sections. There is no script, form, remote resource, network
client, extra generated file, or hosted application surface.

To inspect the bundle through the optional local helper:

```sh
perl -Ilib script/gobanftp showcase preview --dir showcase-v1.1 --port 0 --once
```

The helper binds only `127.0.0.1`, preloads the fixed generated file set, serves
only exact showcase paths from memory, and has no preview JSON/CORS/remote-host
mode.

Preview support is limited to supported local platforms with the required local
safety/process primitives. Unsupported platforms report unsupported/skip, and
an unsupported or skipped preview run must not be used as release evidence.

The release smoke for this viewing path is:

```sh
prove -lr t/showcase-demo.t t/showcase-v1_1.t t/showcase-preview.t
```

It runs the public local command surface: shrine replay, race replay, source-art
oracle smoke, the unsigned `local-goftp1` v1 witness, and the text, static HTML,
and static terminal witness surfaces. Those surfaces show the same
`event_set_root` through reader-facing output; they are not hosted Web UI,
browser applications, deployments, or production network services, and are
separate from the local `play --tui` input surface. None of these displays adds
a new consensus input.

## Boundaries

Do not read sidecar signatures, event file bytes, FTP metadata, projection
files, or tmp entries as consensus inputs.

Scoring, final result events, signed/auth sidecars, and inline assembly are
outside this showcase path. They belong in a later phase, protocol version, or
explicit profile.

Current beta showcase review coverage is source-only, static, and
fixture-local. Live FTP/WebDAV provider checks, distribution packaging, tag,
upload, and deploy are outside the beta source-gate/review scope and require a
later separate maintainer-run gate. Signed-HMAC negative matrices also remain
outside this showcase path.
