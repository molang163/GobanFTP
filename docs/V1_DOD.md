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

For `signed-hmac-goftp1`, signature verification is the profile's event
acceptance gate. The gate is:

```text
base substrate normalization
GOFTP/1 event parse
filename event-id verification
per-event HMAC verification against the declared trust set
event_set_root over signed-accepted basenames
```

The required per-event HMAC payload binds:

```text
profile id
algorithm id
public key id or HMAC key selector
game descriptor basename
exact event basename
visible event id
```

It does not bind `event_set_root` at the event-acceptance layer, because
`event_set_root` is computed after the signed-accepted set is known. A
root-level HMAC, if a later profile requires one, is a post-acceptance set
attestation and must bind the game descriptor, root version, accepted count, and
computed `event_set_root`.

A signed profile must reject:

```text
missing required signature
wrong signature
signature over different payload
signature made by an untrusted key
signature bound to a different game descriptor
signature bound to a different event basename
signature bound to a different event id
signature bound to a different event_set_root when the profile declares a root attestation
```

Wrong signatures must fail closed. A signed profile that falls back to unsigned
truth after signature failure is not v1.0 complete.

Unsigned profiles must continue to treat sidecar signatures as ignored input.
Adding, deleting, or corrupting a sidecar signature must not change unsigned
`GOFTP/1` replay, `event_set_root`, DAG, board projection, SGF, or diagnostics
class.

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

Public poison vectors must bind baseline and hostile rows back to real fixture
`input_names`, declare the ignored evidence per row, and optionally record the
hostile listing order when order itself is the poison. A vector must not require
metadata categories that do not exist for that substrate.

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
The public witness fields are `ruleset_id`, `ruleset_semver`,
`ruleset_seal_version`, `ruleset_fixture_digest`, and `ruleset_seal`. These
fields are compared by `v1 compare-replay`, but they are not inputs to
`event_set_root`.

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
event id collision (DAG-level synthetic vector unless backed by a real GOFTP/1 hash collision)
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
profile consensus version
adapter id
raw input count
normalized event count
normalized event names
accepted event count
rejected input count
event_set_root
diagnostic count
diagnostics class
canonical ids
legal ids
fork report when applicable
board hash
board projection
SGF
ruleset seal
```

The P14b witness-vector refresh made the public witness rows self-contained with
raw input names, rejected diagnostics, replay diagnostics, and rendered
board/verdict/listing/SGF projection text. The P14c replay-invariant refresh
covers the missing ordinary replay behavior cases above except event-id
collision, which is not safely representable as an ordinary public replay
basename without a real hash collision. Event-id collision is instead frozen by
a synthetic DAG-boundary vector with no `event_set_root`, board, SGF, or replay
status claim. The new non-consensus-poison vector starts the public
baseline/poison evidence set with the WebDAV metadata-poison fixture, proving
sidecar, projection, tmp, resource-body row fields, metadata, recursive hrefs,
wrong-game hrefs, duplicate hrefs, percent-encoding hazards, and listing order
stay outside event-set and replay truth. The next vector slice must expand that
public poison set across the remaining core and profile specimens while keeping
`git-tree-goftp1` and `dns-record-goftp1` read-only and avoiding any claim of
Git publish, live DNS, AXFR, DNSSEC trust, provider APIs, dynamic update, or DNS
record publishing.

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
prove -lr t/v1-signed-hmac.t
prove -lr t/v1-signed-hmac-golden-vectors.t
prove -lr t/profile-registry.t t/profile-adapter.t t/witness-api.t
prove -lr t/diagnostics-contract.t
prove -lr t/rules-flow.t t/rules-superko.t

make manifest
make dist
GOBANFTP_RULES_DISABLE_C=1 GOBANFTP_RULES_ENGINE=perl make disttest
make distcheck
```

Dry-run executions of this matrix are recorded separately in
`docs/P14_RELEASE_GATE.md`. This file remains the normative v1.0 requirement;
the dry-run report is evidence for a point in time, not a replacement for the
final clean-checkout gate.

Any final P14 run after Git-tree or DNS-record runtime admission must audit the
release text against the current HEAD. A stale dry-run claim that Git-like or
DNS-like support is only fixture/read-normalizer evidence is not enough once
runtime read paths are admitted, but runtime read admission still does not imply
publish support, live DNS, AXFR, DNSSEC trust, provider API support, dynamic
update, DNS record publishing, hosted Web UI, interactive TUI, or v1.0
completion.

The final release identity, artifact hash, and tag preconditions are planned in
`docs/P14_RELEASE_MANIFEST_AND_TAG_PLAN.md`. A v1.0 tag is blocked until the
chosen version, `Changes` heading, tarball name, final matrix, and artifact
record agree.

Current v1 proof commands:

```sh
script/gobanftp v1 witness --profile local-goftp1 --fixture t/fixtures/v1/cross-substrate/minimal
script/gobanftp v1 compare-roots --fixture t/fixtures/v1/cross-substrate/minimal
script/gobanftp v1 compare-replay --fixture t/fixtures/v1/cross-substrate/minimal
prove -lr t/v1-attack-fixtures.t
prove -lr t/v1-signed-hmac.t t/v1-signed-hmac-golden-vectors.t
prove -lr t/ruleset-seal.t
```

The release requirement is that one reproducible command set proves the full
matrix; future dedicated verifier subcommands may replace these test commands.

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
