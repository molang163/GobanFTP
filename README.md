# GobanFTP

[English](README.md) | [简体中文](README.zh-CN.md) | [日本語](README.ja.md)

A record of the board game Go where the filename is the event.

![Perl 5.34+](https://img.shields.io/badge/Perl-5.34%2B-39457E)
![Version 1.100_001](https://img.shields.io/badge/version-1.100_001-333333)
![License Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-blue)
![Showcase test](https://img.shields.io/badge/showcase-prove--lr%20t%2Fshowcase--demo.t-success)

Current beta release: `v1.1.0-beta.1/package 1.100_001`.

[Filename is the event](#the-shape) · [The fork](#the-fork) ·
[Why this exists](#why-this-exists) · [See it first](#see-it-first) · [What this is for](#what-this-is-for) ·
[Not for](#not-for) · [Three-minute check](#three-minute-proof) ·
[Terminal play](#terminal-play) · [Static specimen](#static-witness-specimen) ·
[The contract](#the-contract)

<a id="the-shape"></a>

## The Filename Is the Event

A small game can be only names:

```text
g1.id-replay.s3.r-chinese-area-v1.k0.pb-alice.pw-bob/
  events/
    m1.p000001.b.play-aa.pa-genesis.by-alice.n-chain1.h-khjclcui7pejbv3m
    m1.p000002.w.play-bb.pa-khjclcui7pejbv3m.by-bob.n-chain2.h-bihb3re4k9hlucat
    m1.p000003.b.pass.pa-bihb3re4k9hlucat.by-alice.n-chain3.h-kcvtlonfje163p9q
```

There is no move body to read. The filename is the event.

The game directory basename names the board, rules, komi, and players. The
direct child basenames under `events/` name the accepted events. Replay follows
the parent ids in those names, not file contents, mtimes, or listing order.
Other files may exist, but only accepted event basenames participate in replay.

<a id="the-fork"></a>

## The Fork

If two publish attempts create different legal children of the same parent, the
listing cannot pick a winner:

```text
g1.id-replay.s3.r-chinese-area-v1.k0.pb-alice.pw-bob/
  events/
    m1.p000001.b.play-aa.pa-genesis.by-alice.n-forkleft.h-q65v2mhef9t3em7l
    m1.p000001.b.play-bb.pa-genesis.by-alice.n-forkright.h-o5g8u5cu913nedng
```

Both events claim `pa-genesis`. Default replay reports a visible fork instead
of letting FTP, WebDAV, Git, DNS, filesystem listing order, mtime, file bodies,
or sidecar metadata silently decide the game.

<a id="why-this-exists"></a>

## Why This Exists

GobanFTP is a `GOFTP/1` protocol experiment with a runnable proof specimen. It
checks one narrow claim: if the same game descriptor basename and accepted
event basenames are visible, the same Go game can be replayed.

It started as playful protocol abuse / protocol bending: making FTP-shaped
storage do something outside its usual job. The point is not to build a normal
online Go game server; it is to make a replay boundary visible on untrusted
enumerable storage.

File contents, size, mtime, listing order, sidecars, projections, SGF, HTML,
terminal output, and source art can help humans inspect the game, but they do
not decide it.

It is not a normal online Go game server, a hosted Web UI, or a production
security system.

<a id="see-it-first"></a>

## See It First

![GobanFTP static witness specimen showing a visual 9x9 board and witness fields.](docs/assets/readme-03-witness-specimen.png)

After replay, the same accepted names can be projected into a board and witness page.

Open `examples/static/witness-specimen.html` directly in a browser.

It has no script, no server, and no network fetch. It only displays witness
fields and a board projection generated from replay. The page is not the game
source; replay still comes from the game descriptor and event filenames.

<a id="what-this-is-for"></a>

## What This Is For

GobanFTP is a good candidate if you want to explore:

- deterministic replay from public descriptor and event filenames
- event logs shaped as directory listings
- visible fork diagnostics when writers race
- protocol boundaries over untrusted enumerable storage
- protocol art that still runs

<a id="not-for"></a>

## Not For

GobanFTP is not:

- a normal online Go game server
- a hosted Web UI
- a production auth system
- a production FTP safety proof
- DNS resolver or provider integrations
- a complete scoring/result system

<a id="three-minute-proof"></a>

## Three-Minute Check

Requirements: Perl 5.34+ and `make`. No FTP server is required for this local
check; it uses fixtures in the repository.

```sh
perl Makefile.PL
make
make test
prove -lr t/showcase-demo.t t/showcase-v1_1.t
perl -Ilib script/gobanftp showcase --out showcase-v1.1
```

The showcase test checks this boundary: a clean game replays, a race becomes a
visible fork, and display surfaces, file bodies, and metadata do not silently
decide the game.

`gobanftp showcase --out showcase-v1.1` writes a local direct-open static bundle
from checked-in fixtures. It is display output for local inspection, not a
hosted Web UI and not replay input.

Those views are inspection output: static HTML is not hosted Web UI, and
`--surface terminal` is not the local `play --tui` input surface.

Run the clean fixture directly:

```sh
GOBANFTP_ROOT=examples/fixtures/ftp-shrine \
perl -Ilib script/gobanftp play --once g1.id-ftp-shrine.s9.r-chinese-area-v1.k7500.pb-daemon.pw-pilgrim
```

Selected output:

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

Now open the race fixture:

```sh
GOBANFTP_ROOT=examples/fixtures/ftp-race-shrine \
perl -Ilib script/gobanftp replay g1.id-ftp-race-shrine.s9.r-chinese-area-v1.k7500.pb-daemon.pw-pilgrim
```

Exit code `3` is expected for this fixture. It means the race was kept visible:

```text
diagnostic ... code=fork parent_id=hihat4p8r6gaeuts
gobanftp.replay=fork
events=4
event_set_count=4
canonical_moves=1
legal_moves=3
canonical_ids=hihat4p8r6gaeuts
```

## Five Terms

- `event filename`: a move or acknowledgement named under `events/`.
- `replay`: rebuild the game from accepted names.
- `fork`: a visible race where two valid children claim the same parent.
- `projection`: generated display, such as board text, SGF, or HTML.
- `witness`: proof material for humans or tests; not the game truth itself.

## First Look

These are views of the same object. The static witness specimen is shown above.
The replay input remains the game directory basename plus the direct event
filenames under `events/`.

### Protocol Object

![GobanFTP protocol object: game descriptor directory, event basenames, sidecar, projections, and tmp residue.](docs/assets/readme-01-protocol-object.png)

The game is visible as a tree. `events/` contains the accepted names.
`sidecar/`, `projections/`, and `tmp/` may explain, display, or help publish,
but they do not decide replay.

### Race Becomes Fork

![GobanFTP race fixture replay output showing a visible fork diagnostic.](docs/assets/readme-04-race-fork.png)

If two moves extend the same parent, listing order does not choose one. Default
replay reports the fork and stops unless explicit ack-assisted recovery is
requested.

### Terminal Input Surface

![GobanFTP terminal play surface with keyboard and optional SGR mouse two-step confirmation.](docs/assets/readme-02-tui.png)

`play --tui` is local input and display over the same replay and publish
callbacks. Keyboard and SGR mouse, where available, select a candidate first. A
second Enter or click confirms it. Input is locked while publishing.

<a id="terminal-play"></a>

## Terminal Play

Try local terminal play with a disposable copy:

```sh
tmp="$(mktemp -d)"
src="$(find examples/fixtures/ftp-shrine -maxdepth 1 -type d -name 'g1.id-ftp-shrine*' | head -n 1)"
cp -R -- "$src" "$tmp/"
game="$tmp/$(basename "$src")"
perl -Ilib script/gobanftp play --tui "$game"
```

The publish path is deliberately two-step:

```text
select -> confirm -> publishing_locked -> published
```

Arrow keys or `hjkl` (Vim-style) move the cursor. `Enter` selects a point;
pressing `Enter` again on the selected point confirms publish. SGR mouse clicks
use the same select/confirm flow where the terminal supports them. One
successful publish ends the session.

The TUI does not own rules, roots, diagnostics, or event acceptance. It is only
an input/display layer over replay and publish callbacks.

For read-only live-over-listing observation, use bounded `watch --live` or
`play --live`:

```sh
perl -Ilib script/gobanftp watch --live --max-polls 3 --interval 1 "$game"
perl -Ilib script/gobanftp watch --live --compact --max-polls 3 --interval 1 "$game"
```

Live mode keeps polling after visible forks or validation diagnostics. It does
not choose a winner, and it does not publish moves. It only keeps re-listing
`events/`, replaying the names, and showing the current witness surface.
`--compact` keeps the event-set and worldline fields while omitting the board.

<a id="static-witness-specimen"></a>

## Static Witness Specimen

`examples/static/witness-specimen.html` is a direct-open specimen. It has no
script, no network fetch, no server process, and no hosted UI behavior.

The visual board is a projection view beside raw projection text. It can display
fields that were already generated; it cannot make an event valid.

<a id="the-contract"></a>

## The Contract

`GOFTP/1` has two replay inputs:

| Truth | Meaning |
| --- | --- |
| game descriptor directory basename | names the game, rules, and players |
| direct child basenames under `events/` | names moves and acknowledgements |

Replay ignores everything else:

| Shadow | Examples |
| --- | --- |
| file data | entry type, bytes, size |
| server metadata | mtime, listing order, server order |
| FTP commands | `RETR`, `SIZE`, `MDTM` |
| WebDAV metadata | ETag, Last-Modified, locks, resource bodies |
| display and helper paths | `sidecar/**`, `projections/**`, `tmp/**` |
| generated surfaces | SGF, static HTML, terminal output, source art |

The game can be replayed after deleting every projection. Change file contents,
mtime, or listing order and replay stays the same. Change an event filename and
the game must change, or the event must be rejected.

Event ids are derived from canonical filename context, not from file contents.
All known play forms a DAG. A network race becomes a visible fork; it is not
hidden by FTP or WebDAV ordering.

Protocol names use a small public alphabet:

```text
[a-z0-9._-]
```

Do not put secrets in filenames.

## Fixture Layout

The browsable fixture is a protocol object, not a screenshot:

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
projections/  may display, but cannot decide
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
remain outside `GOFTP/1` replay.

SGF is generated from replay. It is not read back as the source game.

## What Runs Now

Implemented in v1.1.0-beta.1/package 1.100_001:

- Consensus core: filename grammar, event ids, `event_set_root`, DAG replay,
  `chinese-area-v1` rules, SGF, and ack-assisted fork recovery.
- Stores: local, FTP, WebDAV, read-only Git tree, and read-only DNS record-file
  admission.
- Interfaces: `play --tui`, witness text/html/terminal output, projections,
  direct-open static specimen, read-only `watch --live` / `play --live`
  observers, and executable source-art smoke.
- Profiles: unsigned `GOFTP/1`, declared substrate profiles, and explicit
  signed-HMAC witness/preflight checks.
- Checks and fixtures: showcase test, attack fixtures, cross-substrate golden
  vectors, and profile publish fixtures.

Deliberately out of scope in v1.1.0-beta.1/package 1.100_001:

- `git-tree-goftp1` is read-only at runtime; publish commands fail at the
  storage boundary.
- `dns-record-goftp1` is read-only normalization of a local or otherwise
  declared record file. DNS admission does not query live DNS, run AXFR, trust
  DNSSEC, call provider APIs,
  or publish records.
- TTL, answer order, cache age, DNSSEC status, authoritative server identity,
  and provider metadata stay outside consensus.
- Live DNS is not implemented by the DNS record-file profile.
- Static HTML witness output is not hosted Web UI, and `--surface terminal` is
  not the local `play --tui` input surface.
- Verifier-local HMAC key files, explicit verifier-supplied lifecycle status,
  and fixture publish-token/preflight semantics are not production key
  lifecycle, production auth, or real writer authorization.
- Production auth and production key lifecycle are not implemented in this
  release.
- Final scoring/result events remain outside `GOFTP/1`.

FTP listing-shadow public poison-vector coverage is fixture/listing evidence
only. It does not claim `RETR`, `SIZE`, `MDTM`, live FTP auth, live FTP
integrity, or production FTP deployment safety. The `ftp-goftp1` tmp+rename
publish path is declared separately and covered by mock FTP tests. Live
provider smoke remains outside the P1 fixture-local review scope.

Signed/auth material in this release is verifier-local fixture/preflight
coverage. It is not production writer authorization or production key lifecycle.

Unsigned `GOFTP/1` remains valid and unchanged. A signed/auth profile can reject
events only when that explicit profile is selected; sidecar signatures do not
alter unsigned replay.

## Source Art Boundary

`oracle/goban.pl` may look like a Go board. It still has to run:

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

The source art can dispatch to tested modules. It does not define filename
grammar, event ids, DAG replay, rule legality, storage behavior, SGF, or
diagnostics. Whitespace, comments, POD, C hooks, and asm-like text are
presentation, not replay input.

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

Normal test run:

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

Inspect the accepted packets:

```sh
find "$GOBANFTP_ROOT" -path '*/events/*' -exec basename {} \; | sort
```

Those names are the game input. File contents are not.

## Stores

Local is the default store. FTP, read-only Git tree, read-only DNS record-file
admission, and WebDAV use the same listing-first boundary without reading event
file contents, blob bytes, resource bodies, or DNS transport metadata.
When a local argument is a path, only the final path component is used as the
game descriptor basename, and that basename must be a valid GOFTP game
descriptor.

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

Authenticated WebDAV URLs must use `https://`; Basic and Bearer credentials are
rejected on `http://`. Unauthenticated `http://` remains available for
mock/local cleartext fixtures and is not a production transport-safety mode.

Git tree mode:

```text
GOBANFTP_STORE=git-tree
GOBANFTP_GIT_REPO
GOBANFTP_GIT_TREEISH
GOBANFTP_GIT_BINARY
```

DNS record mode:

```text
GOBANFTP_STORE=dns-record
GOBANFTP_DNS_RECORD_FILE
GOBANFTP_DNS_OWNER_SUFFIX
```

Git tree replay reads direct child names from `<treeish>:<game>/events` and
ignores blob bytes, commit metadata, refs, branches, tags, sidecars,
projections, and tmp entries. Git tree mode is read-only for now; publish
commands fail at the storage boundary.

DNS record admission reads only a local or otherwise declared record-file
presentation for `dns-record-goftp1`, supplied at runtime by
`GOBANFTP_DNS_RECORD_FILE`. It is not a live DNS resolver, AXFR client, DNSSEC
validator, provider API client, dynamic update client, or publishing backend.
TTLs, record order, answer order, cache age, DNSSEC status, authoritative
server identity, and provider metadata are ignored before `event_set_root`.

WebDAV replay reads `events/` with `PROPFIND Depth: 1` and uses only direct href
basenames. Publishing writes a zero-byte temporary resource under `tmp/`, moves
it to `events/<event-name>`, then confirms visibility with a fresh `PROPFIND`.

For `ftp-goftp1`, default publishing uploads a zero-byte temporary entry under
`tmp/`, renames it to `events/<event-name>` with `RNTO`, and confirms visibility
by listing. `GOBANFTP_FTP_PUBLISH_MODE=mkdir` remains the directory-shaped
alternative. This path does not claim live FTP auth, live FTP integrity, or
production FTP deployment safety.

Projection writes are local-only for now. Nonlocal `project` and `sgf --write`
are rejected; plain `sgf`, `verify`, `replay`, `play`, and `watch` can read
nonlocal listings.

## Release Checks

Main commands:

```sh
prove -lr t/showcase-demo.t
prove -lr t
```

The current P14 release record is in `docs/P14_RELEASE_GATE.md`. It records the
final release-source checks and points to the external release/tag record plan;
the final tarball hash belongs outside the source tree.

The final distribution identity, version decision, and tag preconditions are tracked
in `docs/P14_RELEASE_MANIFEST_AND_TAG_PLAN.md`.

For the P1 fixture-local review scope, live provider smoke, distribution
packaging, tag, upload, and deploy are outside P1 and require a later separate
maintainer-run gate.

## License

Unless otherwise noted, the code, protocol documentation, examples, fixtures,
test vectors, projections, and static specimens in this repository are licensed
under the Apache License, Version 2.0.

Copyright 2026 GobanFTP contributors.

This license covers the repository contents. It does not grant permission to
access, test, or publish to third-party FTP, WebDAV, DNS, Git, or other systems
without authorization, and it is not a production security certification.

## Release Invariants

GobanFTP v1.0 is not a game server. It is a Perl implementation of a small
filename protocol for replaying Go from accepted event basenames across several
enumerable stores.

The release checks compare event names, `event_set_root`, DAG replay, canonical
prefix, board projection, SGF, and the diagnostic class for the same observable
logical failure. The expected behavior is:

```text
modify mtime       -> unchanged
modify file bytes  -> unchanged
modify LIST order  -> unchanged
add sidecar        -> unchanged
change basename    -> changed
bad signed profile -> rejected by that signed profile
source art / C / asm / Web UI / TUI -> cannot change truth
```

`v0.1` froze the `GOFTP/1` consensus boundary. The original `v1.0/P14` package
1.000 release source applied that boundary across local files, FTP, WebDAV,
read-only Git tree replay, read-only DNS record-file admission, terminal play,
static witness output, and source art smoke. The current beta release line is
`v1.1.0-beta.1/package 1.100_001`.

## Documentation

Quick links:

```text
Showcase:     docs/SHOWCASE.md
Protocol:     docs/PROTOCOL.md
Profiles:     docs/PROFILES.md
Grammar:      docs/GRAMMAR.md
Attacks:      docs/ATTACKS.md
v1.0 DoD:     docs/V1_DOD.md
P14 checks:   docs/P14_RELEASE_GATE.md
P14 tag plan: docs/P14_RELEASE_MANIFEST_AND_TAG_PLAN.md
Algorithms:   docs/ALGORITHMS.md
Rules:        docs/RULES.md
Diagnostics:  docs/DIAGNOSTICS.md
Source art:   docs/SOURCE_ART.md
Build:        docs/BUILD.md
CLI:          docs/CLI.md
Roadmap:      docs/ROADMAP.md
Decisions:    docs/DECISIONS.md
README refs:  docs/references/README.md
```

Repository map:

```text
.
|-- README.md              this text
|-- README.zh-CN.md        Simplified Chinese README
|-- README.ja.md           Japanese README
|-- docs/                  protocol, roadmap, decisions, references, release records
|-- oracle/goban.pl        executable source-art smoke wrapper
|-- lib/GobanFTP/          Perl implementation modules
|-- script/gobanftp        CLI entry point
|-- examples/fixtures/     browsable mirrored games
`-- t/                     tests and attack fixtures
```

Before changing protocol behavior, read:

1. `docs/PROTOCOL.md`
2. `docs/ARCHITECTURE.md`
3. `docs/ALGORITHMS.md`
4. `docs/RULES.md`
5. `docs/ROADMAP.md`
6. `docs/DECISIONS.md`

Start with the existing protocol docs before adding a new profile or rule.
