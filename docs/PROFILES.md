# Substrate Profiles

GobanFTP v1.0 profiles define how an enumerable substrate exposes the same
GOFTP/1 event names without changing replay truth.

A profile is not a backend nickname. It is a written contract:

```text
what is read
what is ignored
what is accepted
what is rejected
how names are published
how failures are diagnosed
how the event set root is framed
```

No profile may silently expand `GOFTP/1`. If a substrate needs different
consensus inputs, it needs a new explicit profile or protocol version.

## Required Fields

Every profile document or record must declare:

```text
profile_id
profile_status
consensus_version
substrate
authoritative_inputs
ignored_inputs
read_algorithm
publish_algorithm
normalization
event_acceptance
event_set_root
failure_diagnostics
auth_stance
fixtures
smoke_command
```

Field meanings:

```text
profile_id           stable lowercase profile name
profile_status       implemented, planned, experimental, or retired
consensus_version    profile contract version, not an event id input
substrate            local filesystem, FTP, Git-like tree, DNS-like records, etc.
authoritative_inputs exactly which names or records can affect replay truth
ignored_inputs       metadata and surfaces that must not affect replay truth
read_algorithm       how raw substrate state becomes candidate names
publish_algorithm    how one event basename becomes visible
normalization        how raw names become direct event basenames
event_acceptance     parser/hash gate before event_set_root
event_set_root       root version and preimage framing
failure_diagnostics  stable error classes the profile must expose
auth_stance          unsigned, advisory signatures, publish auth, or signed consensus
fixtures             required test/specimen paths
smoke_command        reproducible command proving the profile boundary
```

The profile `consensus_version` identifies the profile contract. It is not part
of `GOFTP/1` event id calculation and is not part of the default
`GOFTP-EVENT-SET/1` preimage. Cross-substrate equality requires the same game
descriptor basename and the same accepted GOFTP/1 event basenames.

Baseline profile ids use the `*-goftp1` suffix to make the consensus mapping
explicit:

```text
local-goftp1
ftp-goftp1
git-tree-goftp1
dns-record-goftp1
webdav-goftp1
```

The matching contract version uses:

```text
GOFTP-PROFILE/<profile_id>/1
```

## Common Event Acceptance

Unless a later profile explicitly says otherwise, profiles use the same
acceptance gate:

1. Read candidate names from the substrate.
2. Keep only direct event basenames or names that normalize to direct event
   basenames.
3. Parse as a GOFTP/1 `m1` or `a1` event.
4. Verify the filename event id against the game descriptor basename.
5. Deduplicate accepted basenames by exact byte string.
6. Sort accepted basenames lexicographically by byte value.

Accepted here does not mean legal play. DAG-invalid or rule-illegal events with
valid filename grammar and event ids still enter `event_set_root`; replay later
reports the DAG or rules diagnostic.

Malformed names, unknown versions, bad event ids, recursive descendants, and
ignored surfaces are excluded from the root and reported through diagnostics
where the profile can observe them.

## Common Event Set Root

Baseline v1 profiles use:

```text
event_set_root_version = GOFTP-EVENT-SET/1
encoding               = lowercase SHA-256 hex
```

Preimage:

```text
"GOFTP-EVENT-SET/1\0" ||
game_descriptor_basename || "\0" ||
event_count_decimal || "\0" ||
event_basename_1 || "\0" ||
event_basename_2 || "\0" ||
...
event_basename_N || "\0"
```

The event count has no leading zero except `0`. Every basename is the accepted
direct event basename, not a path, URL, object key, DNS owner name, WebDAV
resource path, or display label.

## Baseline Profiles

### `local-goftp1`

Status:

```text
implemented
```

Consensus version:

```text
GOFTP-PROFILE/local-goftp1/1
```

Substrate:

```text
local filesystem directory tree
```

Authoritative inputs:

```text
game descriptor directory basename
direct child basenames under events/
```

Ignored inputs:

```text
file bytes
file size
entry type beyond discoverability
mtime
directory traversal paths
sidecar/**
projections/**
tmp/**
recursive descendants under events/
local absolute paths
```

Read algorithm:

```text
list events/ through the store abstraction
normalize direct event-looking basenames
parse and verify GOFTP/1 event ids
```

Publish algorithm:

```text
create a zero-byte event entry through Store::Local
treat an existing identical event basename as success
never read or truncate existing event bytes for replay
```

Failure diagnostics:

```text
parse_event
parse_game_descriptor
missing_parent
parent_not_move
wrong_player
wrong_color
wrong_ply
illegal_move
fork
storage
```

Auth stance:

```text
unsigned GOFTP/1
sidecar signatures advisory only
```

Fixtures and smoke:

```text
t/fixtures/**
examples/fixtures/minimal-game/
examples/fixtures/ftp-shrine/
prove -l t/store-local.t t/event-set-root.t t/replay.t
```

### `ftp-goftp1`

Status:

```text
implemented
```

Consensus version:

```text
GOFTP-PROFILE/ftp-goftp1/1
```

Substrate:

```text
FTP directory tree
```

Authoritative inputs:

```text
game descriptor directory basename
direct names visible under events/
```

Ignored inputs:

```text
LIST order
MLSD facts
mtime
file bytes
file size
entry type beyond discoverability
RETR
SIZE
MDTM
sidecar/**
projections/**
tmp/**
recursive descendants under events/
```

Read algorithm:

```text
MLSD events/ when available
NLST events/ fallback
normalize direct event-looking basenames
parse and verify GOFTP/1 event ids
```

Publish algorithm:

```text
TYPE I
STOR tmp/<player>-<nonce>.part
RNFR tmp/<player>-<nonce>.part
RNTO events/<event_name>
NLST or MLSD events/ until the final event basename is visible
```

Pure listing mode may publish directory-shaped events with:

```text
MKD events/<event_name>
```

Both publish forms produce the same reader truth: a visible direct event
basename under `events/`.

Failure diagnostics:

```text
parse_event
parse_game_descriptor
missing_parent
parent_not_move
wrong_player
wrong_color
wrong_ply
illegal_move
fork
storage
transport_stale
publish_pending
```

Auth stance:

```text
FTP credentials protect transport access only
unsigned GOFTP/1 replay remains valid
sidecar signatures advisory only
```

Fixtures and smoke:

```text
t/store-ftp-mock.t
t/ftp-cli-parity.t
script/live-ftp-smoke
GOBANFTP_FTP_TEST=1 prove -l t/store-ftp.t t/ftp-live-flow.t
```

## Planned Profiles

The planned profiles below are v1.0 targets. They are not implemented until an
adapter, fixtures, and smoke command exist.

### `git-tree-goftp1`

Status:

```text
planned
```

Consensus version:

```text
GOFTP-PROFILE/git-tree-goftp1/1
```

Substrate:

```text
Git-like tree object or checkout
```

Authoritative inputs:

```text
tree entry basename representing the game descriptor
direct tree entry basenames under events/
```

Ignored inputs:

```text
commit author
commit committer
commit timestamp
commit order
blob bytes
blob mode beyond discoverability
object size
branch name
tag name
remote URL
working tree mtime
sidecar/**
projections/**
tmp/**
```

Read algorithm:

```text
enumerate a declared tree snapshot
extract direct events/ child names as UTF-8-free byte strings restricted to the
GOFTP/1 public ASCII basename alphabet
normalize and verify GOFTP/1 event basenames
```

Publish algorithm:

```text
planned: create a new tree snapshot containing events/<event_name>
publish visibility is the selected tree or ref update, not commit timestamp
conflicting children remain visible as forks
```

Auth stance:

```text
Git signatures or hosting credentials are advisory unless a signed profile says otherwise
```

Required fixtures:

```text
t/fixtures/profiles/git-tree-goftp1/
t/fixtures/attacks/git-tree-goftp1/
```

### `dns-record-goftp1`

Status:

```text
planned
```

Consensus version:

```text
GOFTP-PROFILE/dns-record-goftp1/1
```

Substrate:

```text
DNS-like enumerable record set
```

Authoritative inputs:

```text
declared game owner name or label carrying the game descriptor basename
record labels or values that explicitly carry direct event basenames
```

Ignored inputs:

```text
TTL
record order
answer order
resolver cache age
authoritative server identity
DNSSEC status unless a signed profile declares it authoritative
record type outside the profile declaration
presentation whitespace
```

Read algorithm:

```text
enumerate the declared record set
extract event basename strings from the declared label/value slot
lowercase DNS presentation names before decoding
reject any label encoding that cannot round-trip to one GOFTP/1 ASCII basename
normalize and verify GOFTP/1 event basenames
```

Publish algorithm:

```text
planned: publish one record carrying the event basename through the zone update mechanism
visibility is the next enumerated record set, not TTL or answer order
```

Auth stance:

```text
zone credentials protect publishing only
DNSSEC is advisory unless a signed profile says otherwise
```

Required fixtures:

```text
t/fixtures/profiles/dns-record-goftp1/
t/fixtures/attacks/dns-record-goftp1/
```

### `webdav-goftp1`

Status:

```text
planned
```

Consensus version:

```text
GOFTP-PROFILE/webdav-goftp1/1
```

Substrate:

```text
WebDAV collection
```

Authoritative inputs:

```text
collection basename representing the game descriptor
direct resource basenames under events/
```

Ignored inputs:

```text
PROPFIND order
ETag
Last-Modified
Content-Length
Content-Type
resource body
lock token
owner property
displayname property
sidecar/**
projections/**
tmp/**
recursive descendants under events/
```

Read algorithm:

```text
PROPFIND events/ at depth 1
extract direct resource basenames from href path segments
percent-decode exactly once
reject decoded names outside the GOFTP/1 public ASCII basename alphabet
normalize and verify GOFTP/1 event basenames
```

Publish algorithm:

```text
planned: write a temporary resource then MOVE it to events/<event_name>
if MOVE is unavailable, the profile must define an alternate visible publish step
verify publication by a fresh PROPFIND of events/
```

Auth stance:

```text
WebDAV credentials protect transport access only
locks are publish coordination hints, not replay consensus
```

Required fixtures:

```text
t/fixtures/profiles/webdav-goftp1/
t/fixtures/attacks/webdav-goftp1/
```

## Profile Admission Gate

A profile cannot move from `planned` to `implemented` until it has:

```text
written profile section
adapter or store boundary
read fixture
publish fixture or explicit read-only decision
attack fixtures for ignored metadata
event_set_root parity fixture against local-goftp1
CLI or smoke command
diagnostics for malformed, rejected, stale, and conflicting inputs
```

The admission gate is intentionally strict. Profiles are how v1.0 prevents
protocol abuse from turning into protocol ambiguity.
