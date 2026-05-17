# GobanFTP v1.0 Definition of Done

GobanFTP v1.0 is not a game server.

It is a proof machine.

It proves that a game can be recovered from public names on hostile storage.
The storage may pretend to be a filesystem, an FTP directory, a Git tree, DNS
records, WebDAV resources, or another substrate with different ceremonies. The
truth must remain the same when the logical event basenames are the same.

v1.0 is done only when the project can demonstrate that invariance with
fixtures, release gates, and reproducible commands.

## Core Claim

For one game descriptor and one logical set of direct event basenames, every
supported substrate must produce the same:

```text
event_set_root
DAG
canonical prefix
board projection
SGF
diagnostics class
```

This must hold across at least these substrate profiles:

```text
local
ftp
git-like
dns-like
webdav-like
```

The substrate profile may change how names are discovered, published, cached,
or displayed. It must not change replay truth.

## Event Set Root

v1.0 must freeze an `event_set_root` calculation before release. The root is a
digest of the declared consensus inputs, not of storage metadata.

Minimum required inputs:

```text
domain separator
event set root version
game descriptor basename
sorted accepted GOFTP/1 event basenames
```

Forbidden root inputs:

```text
mtime
file content
object content
record content
entry type
file size
listing order
transport order
sidecar/**
projections/**
tmp/**
presentation text
source-art layout
rule engine implementation choice
client UI state
```

Changing only forbidden inputs must leave `event_set_root`, DAG, canonical
prefix, board projection, SGF, and diagnostics class unchanged.

Changing an authoritative basename must either change `event_set_root` and the
derived truth, or be rejected with the stable diagnostics class required by the
profile. A basename change that silently preserves the old root is a release
blocker.

## Substrate Profiles

Every v1.0 substrate profile must declare:

```text
profile id
profile consensus version
authoritative inputs
ignored metadata
listing/read algorithm
publish algorithm
failure diagnostics classes
event_set_root framing
cross-substrate fixture path
```

The profile must name its lies. If the substrate has timestamps, object ids,
commit order, DNS TTLs, WebDAV properties, MIME types, content bytes, directory
types, cache validators, or server-generated metadata, the profile must say
whether each item is authoritative. The default answer is no.

No profile may smuggle new consensus inputs into GOFTP/1. If a substrate needs
different truth, it needs a new explicit consensus version and fixtures that
show the difference.

## Signed Profiles

Signed profiles are allowed only as explicit profiles. They do not make
unsigned GOFTP/1 mean something else.

A signed profile must reject:

```text
missing required signature
wrong signature
signature over different payload
signature made by an untrusted key
signature bound to a different game descriptor
signature bound to a different event_set_root
```

Wrong signatures must fail closed. A signed profile that falls back to unsigned
truth after signature failure is not v1.0 complete.

## Non-Consensus Poison

The following mutations must be fixture-tested on every substrate where the
concept exists:

```text
mtime changes
content changes
listing order changes
server order changes
entry type changes
size changes
sidecar changes
projection changes
tmp changes
cache metadata changes
presentation changes
```

The result must remain the same:

```text
same event_set_root
same DAG
same canonical prefix
same board projection
same SGF
same diagnostics class
```

The following mutations must not remain the same:

```text
direct event basename changed
game descriptor basename changed
event set root version changed
ruleset seal changed
signed profile signature broken
```

Each must either change the appropriate root/output or be rejected with a stable
diagnostics class.

## Implementation Boundaries

Source art is a ritual surface. C is a mechanics implementation. Assembly, Web
views, and TUI views are skins or accelerators. None of them owns truth.

The following must not change `event_set_root`, replay, rule legality, SGF, or
diagnostics class:

```text
oracle/source-art comments
oracle/source-art whitespace
oracle/source-art glyph layout
C engine availability
C engine absence
shadow C comparison mode
assembly acceleration
Web rendering
TUI rendering
terminal dimensions
color settings
font settings
```

Perl remains the reference protocol interpreter unless a later explicit
decision replaces it. Optimized engines may be faster, stranger, or prettier;
they must be proven equivalent against the sealed vectors.

## Ruleset Sealing

`chinese-area-v1` must have a v1.0 ruleset seal. The seal must bind:

```text
ruleset id
ruleset semantic version
board size domain
coordinate grammar
move actions
capture algorithm
suicide rule
superko rule
terminal move behavior
state hash framing
accepted rules fixtures digest
```

Changing rule semantics without changing the seal is forbidden. Changing the
seal without updating fixtures is forbidden. A replay output must record which
ruleset seal was used, directly or through the profile output contract.

## Diagnostics Contract

Diagnostics are part of the proof. v1.0 diagnostics must be stable enough that
scripts can compare classes across substrates without depending on incidental
message text.

Minimum diagnostics requirements:

```text
machine-readable diagnostics schema
per-code required fields
per-code optional fields
stable class for parse failures
stable class for event id failures
stable class for DAG failures
stable class for rules failures
stable class for substrate failures
stable class for signature failures
stable redaction requirements
golden stdout/stderr fixtures for CLI paths
```

Two substrates may emit different low-level detail, but they must agree on the
diagnostics class for the same logical failure.

## Golden Vectors

v1.0 must ship golden vectors for:

```text
minimal legal game
capture
suicide rejection
occupied rejection
bounds rejection
pass
two-pass terminal
resign terminal
simple ko by positional superko
fork
ack-assisted fork choice
missing parent
parent is not a move
dangling ack target
ack target is not a move
wrong player
wrong color
wrong ply
event id mismatch
event id collision
future event version
malformed basename
sidecar poison ignored
projection poison ignored
tmp poison ignored
content poison ignored
metadata poison ignored
signed profile signature failure
```

Each vector must state the input names and expected:

```text
event_set_root
diagnostics class
canonical ids
legal ids
fork report when applicable
board hash
board projection
SGF
ruleset seal
```

## Release Gates

v1.0 may not be tagged until these gates pass from a clean checkout:

```sh
perl -c oracle/goban.pl
perl oracle/goban.pl --smoke

perl Makefile.PL
GOBANFTP_RULES_DISABLE_C=1 GOBANFTP_RULES_ENGINE=perl make test
GOBANFTP_RULES_ENGINE=shadow make test

prove -lr t
prove -lr t/v1-cross-substrate.t
prove -lr t/v1-attack-fixtures.t
prove -lr t/v1-golden-vectors.t
prove -lr t/v1-diagnostics-schema.t
prove -lr t/v1-ruleset-seal.t

make manifest
make dist
GOBANFTP_RULES_DISABLE_C=1 GOBANFTP_RULES_ENGINE=perl make disttest
make distcheck
```

Draft profile verification commands:

```sh
script/gobanftp v1 root --profile local --fixture t/fixtures/v1/cross-substrate/minimal
script/gobanftp v1 root --profile ftp --fixture t/fixtures/v1/cross-substrate/minimal
script/gobanftp v1 root --profile git-like --fixture t/fixtures/v1/cross-substrate/minimal
script/gobanftp v1 root --profile dns-like --fixture t/fixtures/v1/cross-substrate/minimal
script/gobanftp v1 root --profile webdav-like --fixture t/fixtures/v1/cross-substrate/minimal

script/gobanftp v1 compare-roots --fixture t/fixtures/v1/cross-substrate/minimal
script/gobanftp v1 compare-replay --fixture t/fixtures/v1/cross-substrate/minimal
script/gobanftp v1 verify-attacks --fixture t/fixtures/attacks
script/gobanftp v1 verify-signatures --fixture t/fixtures/v1/signed-profile
script/gobanftp v1 verify-ruleset-seal --rules chinese-area-v1
```

The command names are drafts. The release requirement is not the exact spelling;
the release requirement is that one reproducible command set proves the full
matrix.

## Done Means Demonstrated

Documentation is not enough. A passing local test is not enough. A pretty
substrate demo is not enough.

v1.0 is done when a maintainer can take the same logical event basenames, place
them onto every supported substrate, run the verification matrix, and receive
the same proof:

```text
same event_set_root
same DAG
same canonical prefix
same board projection
same SGF
same diagnostics class
```

Only then is the rite complete.
