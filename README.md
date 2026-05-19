# GobanFTP

A Go game recovered from hostile directory listings.

![Perl 5.34+](https://img.shields.io/badge/Perl-5.34%2B-39457E)
![Version 1.000](https://img.shields.io/badge/version-1.000-333333)
![License perl_5](https://img.shields.io/badge/license-perl__5-blue)
![Showcase gate](https://img.shields.io/badge/showcase-prove--lr%20t%2Fshowcase--demo.t-success)

Moves are filenames. Replay ignores file contents.

Change the basename, the game changes. Change bytes, mtime, order, sidecars, or
projections, it does not.

Current line: `v1.0/package 1.000` release source.

[Three-minute proof](#three-minute-proof) · [Terminal play](#terminal-play) ·
[Static specimen](#static-witness-specimen) · [The contract](#the-contract)

`v1.0/P14` freezes one rule: the same accepted event names produce the same
replay. Source-art, terminal play, static witness HTML, and fixture evidence are
surfaces. They cannot add truth.

```text
Names are packets.
The listing is the read.
The board is projection.
SGF is witness.
FTP is the altar, not the authority.
```

The strange surface is deliberate. The replay contract is not negotiable.

Try the local proof:

```sh
perl Makefile.PL
make test
prove -lr t/showcase-demo.t
```

## First Look

These are views of the same boundary. Only event basenames decide replay.

### Protocol Object, Not App State

![GobanFTP protocol object: the game descriptor directory, event basenames, sidecar, projections, and tmp residue.](docs/assets/readme-01-protocol-object.png)

The game descriptor basename and direct `events/` basenames are the packets.
`sidecar/`, `projections/`, and `tmp/` cannot decide replay.

### Race Becomes Fork

![GobanFTP race shrine replay output showing a visible fork diagnostic.](docs/assets/readme-04-race-fork.png)

Listing order does not choose a winner. Default conservative replay stops at
the fork unless explicit ack-assisted recovery is requested.

### Terminal Play Locks Before Publish

![GobanFTP terminal play surface with keyboard and optional SGR mouse two-step confirmation.](docs/assets/readme-02-tui.png)

`play --tui` is a local input/display layer over replay and publish callbacks.
Keyboard and SGR mouse, where available, select first; a second Enter/click
confirms; input locks while publishing.

### Static Specimen, Not Hosted UI

![GobanFTP static witness specimen showing a visual 9x9 board and proof panel.](docs/assets/readme-03-witness-specimen.png)

The static witness specimen is a direct-open file: no script, no server, no
hosted Web UI. It displays supplied witness fields and projection text; protocol
truth stays in event basenames.

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
unsigned `local-goftp1` v1 witness, and static inspection surfaces. Those
surfaces are read-only inspection output: static HTML is not hosted Web UI, and
`--surface terminal` is not the local `play --tui` input surface. Local terminal
play is available through `gobanftp play --tui`; it remains an input/display
layer over replay and publish callbacks. Keyboard and SGR mouse input select a
candidate first, require a second Enter/click to publish, and lock input once
publishing starts.

Open the shrine:

```text
examples/fixtures/ftp-shrine/
```

Then run:

```sh
GOBANFTP_ROOT=examples/fixtures/ftp-shrine \
perl -Ilib script/gobanftp play --once g1.id-ftp-shrine.s9.r-chinese-area-v1.k7500.pb-daemon.pw-pilgrim
```

Expected clean shape, selected lines:

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

The process exits `3`. Expected race shape, selected lines:

```text
diagnostic ... code=fork parent_id=hihat4p8r6gaeuts
gobanftp.replay=fork
events=4
event_set_count=4
canonical_moves=1
legal_moves=3
canonical_ids=hihat4p8r6gaeuts
```

That is the point: the race remains visible. No listing order gets to choose a
winner.

## Terminal Play

`gobanftp play --tui` is local play over the same replay and publish callbacks.
It does not own rules, roots, diagnostics, or event acceptance.

```text
select -> confirm -> publishing_locked -> published
```

Keyboard is the fallback path. SGR mouse is used where the terminal supports it.
One successful publish ends the session.

## Static Witness Specimen

`examples/static/witness-specimen.html` is a direct-open specimen. It has no
script, no network fetch, no server process, and no hosted UI behavior.

The visual board is a projection skin beside raw projection text. It cannot
testify; it can only display.

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

Implemented in v1.0/package 1.000:

- Consensus core: filename grammar, event ids, `event_set_root`, DAG replay,
  `chinese-area-v1` rules, SGF, and ack-assisted fork recovery.
- Stores: local, FTP, WebDAV, read-only Git tree, and read-only DNS record-file
  admission.
- Surfaces: `play --tui`, witness text/html/terminal, projections, direct-open
  static specimen, and executable source-art oracle smoke.
- Profiles: unsigned `GOFTP/1`, declared substrate profiles, and explicit
  signed-HMAC witness/preflight gates.
- Evidence: showcase gate, attack fixtures, cross-substrate golden vectors, and
  profile publish fixtures.

Boundary lines in v1.0/package 1.000:

- `git-tree-goftp1` is read-only at runtime; publish commands fail at the
  storage boundary.
- `dns-record-goftp1` is read-only normalization of a local or otherwise
  declared record file. DNS admission does not query live DNS, run AXFR, trust
  DNSSEC, call provider APIs, or publish records.
- TTL, answer order, cache age, DNSSEC status, authoritative server identity,
  and provider metadata stay outside consensus.
- Static HTML witness output is not hosted Web UI, and `--surface terminal` is
  not the local `play --tui` input surface.
- Verifier-local HMAC key files, explicit verifier-supplied lifecycle status,
  and fixture publish-token/preflight semantics are not production key
  lifecycle, production auth, or real writer authorization.
- Final scoring/result events remain outside `GOFTP/1`.

FTP listing-shadow public poison-vector coverage is fixture/listing evidence
only. It does not claim `RETR`, `SIZE`, `MDTM`, live FTP auth, live FTP
integrity, or production FTP deployment safety. The `ftp-goftp1` tmp+rename
publish path is declared separately and covered by mock FTP tests plus optional
`script/live-ftp-smoke`.

Signed/auth material in this release is verifier-local fixture/preflight
evidence. It is not production writer authorization or production key lifecycle.

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

The source art may dispatch to tested modules. It must not own protocol truth:
filenames, event ids, DAG replay, rule legality, storage behavior, SGF, and
diagnostics remain outside the drawing. Whitespace, comments, POD, C hooks, and
asm-like surface are ritual surface, never consensus input.

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

Local is the default store. FTP, read-only Git tree, read-only DNS record-file
admission, and WebDAV run the same listing-first boundary without reading event
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
`tmp/`, renames it to `events/<event-name>` with `RNTO`, and confirms
visibility by listing. `GOBANFTP_FTP_PUBLISH_MODE=mkdir` remains the
directory-shaped alternative.

Projection writes are local-only for now. Nonlocal `project` and `sgf --write`
are rejected; plain `sgf`, `verify`, `replay`, `play`, and `watch` can read
nonlocal listings.

## Proof Gates

Main gates:

```sh
prove -lr t/showcase-demo.t
prove -lr t
```

The current P14 release-gate evidence is recorded in
`docs/P14_RELEASE_GATE.md`. It records final release-source evidence and points
to the external artifact/tag record plan; the final tarball hash belongs outside
the source tree.

The final artifact identity, version decision, and tag preconditions are tracked
in `docs/P14_RELEASE_MANIFEST_AND_TAG_PLAN.md`.

Optional disposable live FTP smoke:

```sh
script/live-ftp-smoke
```

## v1.0/P14 Shape

GobanFTP v1.0 is not a game server. It is a protocol-abuse proof machine for
making a Go game emerge from untrusted enumerable substrates.

The release proof requires the profile, adapter, attack, witness, auth, and
display gates to agree:

```text
same event basenames
same event_set_root
same DAG
same canonical prefix
same board projection
same SGF
same diagnostic class for the same logical failure where observable
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

`v0.1` froze the GOFTP/1 consensus boundary. `v1.0/P14` turns that boundary into
a cross-substrate proof source for package 1.000.

## Documentation

Fast paths:

```text
Showcase:     docs/SHOWCASE.md
Protocol:     docs/PROTOCOL.md
Profiles:     docs/PROFILES.md
Grammar:      docs/GRAMMAR.md
Attacks:      docs/ATTACKS.md
v1.0 DoD:     docs/V1_DOD.md
P14 gate:     docs/P14_RELEASE_GATE.md
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
