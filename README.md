# GobanFTP

A Go game can live in hostile listings.

GobanFTP is a listing-first Go protocol artwork: public names are packets,
replay is proof, and projections are shadows. A server may lie about time, size,
order, type, locks, bodies, and presentation. The game still emerges from the
names it is allowed to trust.

Current line: `v1.0/P14` development.

The local `v0.2` / package `0.002` release candidate was skipped as a public
release. The `v1.0/P14` target is the release-freeze proof machine: the same
logical event basenames must produce the same `event_set_root`, DAG, canonical
prefix, board projection, SGF, and diagnostics class across declared
substrates.

```text
Names are packets.
The listing is the read.
The board is projection.
SGF is witness.
FTP is the altar, not the authority.
```

The strange surface is deliberate. The replay contract is not negotiable.

## The Contract

`GOFTP/1` has two authoritative inputs:

```text
game descriptor directory basename
direct child basenames under events/
```

Core replay ignores:

```text
entry type
file bytes
file size
listing order
server order
FTP mtime
WebDAV ETag
WebDAV Last-Modified
WebDAV locks
sidecar/**
projections/**
tmp/**
```

`RETR`, `SIZE`, `MDTM`, HTTP resource bodies, cache validators, and server
metadata are not part of replay. The game survives deletion of every projection.

An event id is derived from canonical filename context, not from file contents.
The hash input binds the game descriptor basename and the event basename without
its final `.h-<event_id>` field. The visible event id is the first 16 characters
of lowercase base32hex SHA-256.

A line of play is a hash chain. All known play is a DAG. A network race is not
hidden by FTP ordering; it becomes a visible fork. Conservative replay stops at
the fork unless an explicit ack-assisted path is requested.

Protocol names stay boring:

```text
[a-z0-9._-]
```

No secret belongs in a filename. Filenames are public.

## Three-Minute Proof

Run the local showcase gate:

```sh
prove -lr t/showcase-demo.t
```

It checks the clean shrine, the race shrine, the source-art oracle smoke, the
unsigned `local-goftp1` v1 witness, and the text, static HTML, and static
terminal witness surfaces that expose the same root. Those surfaces are
read-only inspection output, not hosted Web UI or interactive TUI.

Open the shrine:

```text
examples/fixtures/ftp-shrine/
```

Then run:

```sh
GOBANFTP_ROOT=examples/fixtures/ftp-shrine \
perl -Ilib script/gobanftp play --once g1.id-ftp-shrine.s9.r-chinese-area-v1.k7500.pb-daemon.pw-pilgrim
```

Expected shape:

```text
gobanftp.play=ok
events=7
canonical_moves=6
worldline.status=main
  a b c d e f g h i
9 . . . . . . . . .
8 . . . . . . . . .
7 . . . . . . . . .
6 . . . B . . . . .
5 . . . B . W . . .
4 . . . B W W . . .
3 . . . . . . . . .
2 . . . . . . . . .
1 . . . . . . . . .
```

Now open the race:

```text
examples/fixtures/ftp-race-shrine/
```

Run:

```sh
GOBANFTP_ROOT=examples/fixtures/ftp-race-shrine \
perl -Ilib script/gobanftp replay g1.id-ftp-race-shrine.s9.r-chinese-area-v1.k7500.pb-daemon.pw-pilgrim
```

The process exits `3`. Output includes:

```text
diagnostic ... code=fork parent_id=hihat4p8r6gaeuts
gobanftp.replay=fork
canonical_moves=1
legal_moves=3
```

That is the point: the race remains visible.

## The Shrine

The browsable specimen is not a screenshot. It is a protocol object:

```text
g1.id-ftp-shrine.s9.r-chinese-area-v1.k7500.pb-daemon.pw-pilgrim/
  events/
    m1.p000001.b.play-dd.pa-genesis.by-daemon.n-altar1.h-0agr68rv1sp5qi21
    ...
  sidecar/
  projections/
    board/current.txt
    oracle/listing.txt
    sgf/main.sgf
  tmp/
```

Read the tree like this:

```text
g1.../         names the game
events/       names the moves and acknowledgements
sidecar/      may explain, but cannot decide
projections/  may display, but cannot testify
tmp/          is publishing residue
```

Useful first files:

```text
examples/fixtures/ftp-shrine/README.md
examples/fixtures/ftp-shrine/g1.id-ftp-shrine.s9.r-chinese-area-v1.k7500.pb-daemon.pw-pilgrim/events/
examples/fixtures/ftp-shrine/g1.id-ftp-shrine.s9.r-chinese-area-v1.k7500.pb-daemon.pw-pilgrim/projections/oracle/listing.txt
examples/fixtures/ftp-shrine/g1.id-ftp-shrine.s9.r-chinese-area-v1.k7500.pb-daemon.pw-pilgrim/projections/board/current.txt
examples/fixtures/ftp-shrine/g1.id-ftp-shrine.s9.r-chinese-area-v1.k7500.pb-daemon.pw-pilgrim/projections/sgf/main.sgf
oracle/goban.pl
```

`projections/oracle/listing.txt` is a reader-facing transcript. It demonstrates
that `NLST events/` exposes event basenames while `RETR`, `SIZE`, and `MDTM`
remain outside GOFTP/1 replay.

SGF is a witness, not the source of truth.

## What Runs Now

Implemented in this release line:

- strict game descriptor and event filename parsing
- filename-derived event ids
- deterministic event-set roots
- DAG construction and conservative replay
- Go rules for `chinese-area-v1`
- optional `Inline::C` board-mechanics backend
- SGF rendering
- rebuildable board, graveyard, SGF, and oracle projections
- local filesystem store
- FTP store with mock coverage and gated live tests
- WebDAV store with mock and CLI parity coverage
- CLI create, verify, replay, project, SGF, publish-move, publish-ack, play,
  and watch flows
- explicit ack-assisted fork recovery
- v1 profile registry and witness output
- `local-goftp1`, `ftp-goftp1`, and `webdav-goftp1` substrate profiles
- `signed-hmac-goftp1` per-event HMAC witness acceptance gate
- core, v1, and profile attack fixture galleries
- executable source-art oracle smoke

Implemented does not mean every future ritual is complete. `git-tree-goftp1` and
`dns-record-goftp1` are planned profile contracts with read-normalizer fixtures.
Production key lifecycle, publish authentication policy, final scoring/result
events, and the full `v1.0/P14` freeze remain release-route work.

Unsigned `GOFTP/1` remains valid and unchanged. A signed/auth profile can reject
events only when that explicit profile is selected; sidecar signatures do not
alter unsigned replay.

## Source Art Boundary

`oracle/goban.pl` may look like a Go board. It must still run.

```sh
perl -c oracle/goban.pl
perl oracle/goban.pl --smoke
```

Expected output includes:

```text
oracle/goban.pl syntax OK
gobanftp.oracle=ok
rules.move=ok
```

The source art may dispatch to tested modules. It must not own filename grammar,
event id calculation, DAG replay, rule legality, storage behavior, SGF output,
or projection rebuilding. Whitespace, comments, POD, C hooks, and asm-like
surface are ritual surface, never consensus input.

## Run It

Runtime requirements:

```text
Perl 5.34+
Digest::SHA
HTTP::Tiny
MIME::Base64
Net::FTP
```

Build and test requirements:

```text
make
```

Optional:

```text
Inline
Inline::C
```

Normal gate:

```sh
perl Makefile.PL
make
make test
```

Full local prove run:

```sh
prove -lr t
```

Create a disposable game:

```sh
tmp="$(mktemp -d)"
export GOBANFTP_ROOT="$tmp"

perl -Ilib script/gobanftp create-game --id demo --size 9 --black alice --white bob
perl -Ilib script/gobanftp publish-move g1.id-demo.s9.r-chinese-area-v1.k7500.pb-alice.pw-bob aa
perl -Ilib script/gobanftp publish-move g1.id-demo.s9.r-chinese-area-v1.k7500.pb-alice.pw-bob play-bb
perl -Ilib script/gobanftp play --once g1.id-demo.s9.r-chinese-area-v1.k7500.pb-alice.pw-bob
```

Inspect the authoritative packets:

```sh
find "$GOBANFTP_ROOT" -path '*/events/*' -exec basename {} \; | sort
```

Those names are the game. The file contents are not.

## Stores

Local is the default store. FTP and WebDAV run the same listing-first command
surface without reading event file contents or resource bodies.

FTP mode:

```text
GOBANFTP_STORE=ftp
GOBANFTP_FTP_HOST
GOBANFTP_FTP_USER
GOBANFTP_FTP_PASSWORD
GOBANFTP_FTP_ROOT
GOBANFTP_FTP_PORT
GOBANFTP_FTP_PASSIVE
GOBANFTP_FTP_TIMEOUT
GOBANFTP_FTP_PUBLISH_MODE
```

WebDAV mode:

```text
GOBANFTP_STORE=webdav
GOBANFTP_WEBDAV_URL
GOBANFTP_WEBDAV_USER
GOBANFTP_WEBDAV_PASSWORD
GOBANFTP_WEBDAV_TOKEN
GOBANFTP_WEBDAV_TIMEOUT
GOBANFTP_WEBDAV_CLASS
GOBANFTP_WEBDAV_PUBLISH_MODE
```

WebDAV replay reads `events/` with `PROPFIND Depth: 1` and uses only direct href
basenames. Publishing writes a zero-byte temporary resource under `tmp/`, moves
it to `events/<event-name>`, then confirms visibility with a fresh `PROPFIND`.

Projection writes are local-only for now. Remote `project` and `sgf --write`
are rejected; plain `sgf`, `verify`, `replay`, `play`, and `watch` can read
remote listings.

## Proof Gates

Showcase:

```sh
prove -lr t/showcase-demo.t
```

Local runtime flow:

```sh
prove -lr t/store-local.t t/create-game.t t/e2e-local.t t/play-flow-store.t
```

FTP store and CLI parity, without a live server:

```sh
prove -lr t/store-ftp-mock.t t/ftp-cli-parity.t
```

Optional disposable live FTP smoke:

```sh
script/live-ftp-smoke
```

WebDAV store and CLI parity, mock-backed:

```sh
prove -lr t/store-webdav-mock.t t/webdav-cli-parity.t
```

v1 profiles, witnesses, and compare commands:

```sh
prove -lr t/profile-registry.t t/profile-adapter.t t/witness-api.t \
  t/v1-cli-witness.t t/v1-cli-compare.t t/v1-cross-substrate.t
```

Signed-HMAC witness gate:

```sh
prove -lr t/hmac-auth.t t/profile-signed-hmac.t \
  t/v1-signed-hmac.t t/v1-signed-hmac-golden-vectors.t
```

Attack galleries:

```sh
prove -lr t/attack-fixtures.t t/v1-attack-fixtures.t t/v1-profile-attack-fixtures.t
```

The current P14 release-gate dry run is recorded in
`docs/P14_RELEASE_GATE.md`. It is a command matrix and artifact check, not a
v1.0 tag or release-ready declaration.

The final artifact identity, version decision, and tag preconditions are tracked
in `docs/P14_RELEASE_MANIFEST_AND_TAG_PLAN.md`.

## v1.0/P14 Shape

GobanFTP v1.0 is not a game server. It is a protocol-abuse proof machine for
making a Go game emerge from untrusted enumerable substrates.

The release freeze is not tagged until the profile, adapter, attack, witness,
auth, and display gates agree:

```text
same event basenames
same event_set_root
same DAG
same canonical prefix
same board projection
same SGF
same diagnostic class
```

Required invariants:

```text
modify mtime       -> unchanged
modify file bytes  -> unchanged
modify LIST order  -> unchanged
add sidecar        -> unchanged
change basename    -> changed
bad signed profile -> rejected by that signed profile
source art / C / asm / Web UI / TUI -> cannot change truth
```

`v0.1` freezes the GOFTP/1 consensus boundary. `v1.0/P14` turns that boundary
into a cross-substrate proof.

## Documentation

Fast paths:

```text
Showcase:     docs/SHOWCASE.md
Protocol:     docs/PROTOCOL.md
Profiles:     docs/PROFILES.md
Grammar:      docs/GRAMMAR.md
Attacks:      docs/ATTACKS.md
v1.0 DoD:     docs/V1_DOD.md
P14 dry run:  docs/P14_RELEASE_GATE.md
P14 tag plan: docs/P14_RELEASE_MANIFEST_AND_TAG_PLAN.md
Algorithms:   docs/ALGORITHMS.md
Rules:        docs/RULES.md
Diagnostics:  docs/DIAGNOSTICS.md
Source art:   docs/SOURCE_ART.md
Build:        docs/BUILD.md
CLI:          docs/CLI.md
Roadmap:      docs/ROADMAP.md
Decisions:    docs/DECISIONS.md
```

Repository map:

```text
.
|-- README.md              this text
|-- docs/                  protocol, roadmap, decisions, gates
|-- oracle/goban.pl        executable source-art smoke wrapper
|-- lib/GobanFTP/          Perl implementation modules
|-- script/gobanftp        CLI entry point
|-- examples/fixtures/     browsable mirrored games
`-- t/                     tests and attack galleries
```

Before changing protocol behavior, read:

1. `docs/PROTOCOL.md`
2. `docs/ARCHITECTURE.md`
3. `docs/ALGORITHMS.md`
4. `docs/RULES.md`
5. `docs/ROADMAP.md`
6. `docs/DECISIONS.md`

Tighten the existing protocol before inventing another one.
