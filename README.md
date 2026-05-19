# GobanFTP

[English](README.md) | [简体中文](README.zh-CN.md) | [日本語](README.ja.md)

A Go game reconstructed from enumerable names.

![Perl 5.34+](https://img.shields.io/badge/Perl-5.34%2B-39457E)
![Version 1.000](https://img.shields.io/badge/version-1.000-333333)
![License perl_5](https://img.shields.io/badge/license-perl__5-blue)
![Showcase test](https://img.shields.io/badge/showcase-prove--lr%20t%2Fshowcase--demo.t-success)

GobanFTP stores a Go game as a directory-shaped protocol object. The game
descriptor directory names the game, rules, and players. Moves and
acknowledgements are event filenames under `events/`.

Replay reads those basenames. It ignores file bytes, file size, mtime, listing
order, server order, sidecars, projections, and tmp entries.

Current line: `v1.0/package 1.000` release source.

[Three-minute check](#three-minute-proof) · [Terminal play](#terminal-play) ·
[Static specimen](#static-witness-specimen) · [The contract](#the-contract)

Quick local check:

```sh
perl Makefile.PL
make test
prove -lr t/showcase-demo.t
```

## First Look

These screenshots show the same object from four angles. The replay input is
still the game descriptor basename plus direct event basenames.

### Protocol Object

![GobanFTP protocol object: game descriptor directory, event basenames, sidecar, projections, and tmp residue.](docs/assets/readme-01-protocol-object.png)

The game is visible as a tree. `events/` contains the accepted names.
`sidecar/`, `projections/`, and `tmp/` may help a reader or a publisher, but
they do not decide replay.

### Race Becomes Fork

![GobanFTP race fixture replay output showing a visible fork diagnostic.](docs/assets/readme-04-race-fork.png)

If two moves extend the same parent, listing order does not choose one. Default
replay reports the fork and stops unless explicit ack-assisted recovery is
requested.

### Terminal Play

![GobanFTP terminal play surface with keyboard and optional SGR mouse two-step confirmation.](docs/assets/readme-02-tui.png)

`play --tui` is local input and display over the same replay and publish
callbacks. Keyboard and SGR mouse, where available, select a candidate first. A
second Enter or click confirms it. Input is locked while publishing.

### Static Witness Specimen

![GobanFTP static witness specimen showing a visual 9x9 board and witness fields.](docs/assets/readme-03-witness-specimen.png)

The specimen is a direct-open HTML file. It has no script, no server, and no
hosted Web UI behavior. It displays witness fields and projection text that were
supplied to it.

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
metadata are not replay inputs. The game can be replayed after deleting every
projection.

An event id is derived from canonical filename context, not from file contents.
The hash input binds the game descriptor basename and the event basename without
its final `.h-<event_id>` field. The visible event id is the first 16 characters
of lowercase base32hex SHA-256.

A line of play is a hash chain. All known play is a DAG. A network race becomes
a visible fork; it is not hidden by FTP or WebDAV ordering. Conservative replay
stops at the fork unless an explicit ack-assisted path is requested.

Protocol names use a small public alphabet:

```text
[a-z0-9._-]
```

Do not put secrets in filenames.

<a id="three-minute-proof"></a>

## Three-Minute Check

Run the local showcase test:

```sh
prove -lr t/showcase-demo.t
```

It checks the clean fixture, the race fixture, source-art smoke, the unsigned
`local-goftp1` v1 witness, and static inspection views. Those views are
read-only inspection output: static HTML is not hosted Web UI, and
`--surface terminal` is not the local `play --tui` input surface.

Local terminal play is available through `gobanftp play --tui`; it stays an
input/display layer over replay and publish callbacks. Keyboard and SGR mouse
input select a candidate first, require a second Enter or click to publish, and
lock input once publishing starts.

Open the clean fixture:

```text
examples/fixtures/ftp-shrine/
```

Then run:

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

Open the race fixture:

```text
examples/fixtures/ftp-race-shrine/
```

Run:

```sh
GOBANFTP_ROOT=examples/fixtures/ftp-race-shrine \
perl -Ilib script/gobanftp replay g1.id-ftp-race-shrine.s9.r-chinese-area-v1.k7500.pb-daemon.pw-pilgrim
```

Exit code `3` is expected for this fixture. Selected output:

```text
diagnostic ... code=fork parent_id=hihat4p8r6gaeuts
gobanftp.replay=fork
events=4
event_set_count=4
canonical_moves=1
legal_moves=3
canonical_ids=hihat4p8r6gaeuts
```

The fixture leaves the race visible. Listing order does not select a winner.

## Terminal Play

`gobanftp play --tui` is local play over the same replay and publish callbacks.
It does not own rules, roots, diagnostics, or event acceptance.

```text
select -> confirm -> publishing_locked -> published
```

Keyboard input is the fallback path. SGR mouse input is used where the terminal
supports it. One successful publish ends the session.

## Static Witness Specimen

`examples/static/witness-specimen.html` is a direct-open specimen. It has no
script, no network fetch, no server process, and no hosted UI behavior.

The visual board is a projection view beside raw projection text. It can display
fields that were already generated; it cannot make an event valid.

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

Implemented in v1.0/package 1.000:

- Consensus core: filename grammar, event ids, `event_set_root`, DAG replay,
  `chinese-area-v1` rules, SGF, and ack-assisted fork recovery.
- Stores: local, FTP, WebDAV, read-only Git tree, and read-only DNS record-file
  admission.
- Interfaces: `play --tui`, witness text/html/terminal output, projections,
  direct-open static specimen, and executable source-art smoke.
- Profiles: unsigned `GOFTP/1`, declared substrate profiles, and explicit
  signed-HMAC witness/preflight checks.
- Checks and fixtures: showcase test, attack fixtures, cross-substrate golden
  vectors, and profile publish fixtures.

Deliberately out of scope in v1.0/package 1.000:

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
publish path is declared separately and covered by mock FTP tests plus optional
`script/live-ftp-smoke`.

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
final release-source checks and points to the external artifact/tag record plan;
the final tarball hash belongs outside the source tree.

The final artifact identity, version decision, and tag preconditions are tracked
in `docs/P14_RELEASE_MANIFEST_AND_TAG_PLAN.md`.

Optional disposable live FTP smoke:

```sh
script/live-ftp-smoke
```

## v1.0/P14 Scope

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

`v0.1` froze the `GOFTP/1` consensus boundary. `v1.0/P14` applies that boundary
to package 1.000 across local files, FTP, WebDAV, read-only Git tree replay,
read-only DNS record-file admission, terminal play, static witness output, and
source art smoke.

## Documentation

Fast paths:

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
```

Repository map:

```text
.
|-- README.md              this text
|-- README.zh-CN.md        Simplified Chinese README
|-- README.ja.md           Japanese README
|-- docs/                  protocol, roadmap, decisions, release records
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
