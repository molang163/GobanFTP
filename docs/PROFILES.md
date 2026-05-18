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

The runtime profile registry may expose a compact subset of those fields for
code dispatch and witness output. The full normative profile record remains this
document: authoritative inputs, ignored inputs, publish semantics, diagnostics,
fixtures, and smoke commands are not inferred from a backend nickname.

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

## Signed/Auth Profile Boundary

Unsigned `GOFTP/1` remains unchanged. Baseline profiles do not read signatures,
HMACs, bearer tokens, sidecar claims, or key metadata as replay input. For
`local-goftp1`, `ftp-goftp1`, `webdav-goftp1`, and the planned unsigned Git/DNS
substrate profiles, sidecar signatures are still ignored input and may only be
shown as advisory attestations.

Auth material has three separate meanings:

```text
publish auth       credentials that allow a writer to create visible names
advisory trust     public key, trust, or attestation records ignored by replay
signed consensus   signatures required by an explicit signed profile
```

`keygen`, `keyid`, `attest`, and `trust-report` belong to the advisory or signed
profile layer. They are not GOFTP/1 event grammar. Public key records, trust
files, and attestation fixtures must not change the unsigned `event_set_root`,
DAG replay, board state, SGF, or diagnostics class.

Key ids identify public keys, not people, files, accounts, or trust status.
Baseline auth fixtures use:

```text
key_id_version = GOFTP-KEY/1
encoding       = "k1." plus lowercase base32hex
```

Key id preimage:

```text
"GOFTP-KEY/1\0" ||
suite || "\0" ||
public_key_bytes || "\0"
```

The key id is the first 32 base32hex characters of the SHA-256 digest, prefixed
with `k1.`. Owner, label, comment, creation time, trust status, and revocation
metadata are excluded so that metadata edits do not rotate the key id.

The minimal fixture public key record is:

```text
gobanftp-public-key-v1
suite=fixture-ed25519-v1
public_hex=<64 lowercase hex chars>
```

`fixture-ed25519-v1` is parser fixture data only. It is not a real signing suite
and must not create a production signature or private-key lifecycle.
`gobanftp v1 keyid --fixture <public-key-file>` is implemented for this fixture
record shape. It derives a public `k1.` identity only; it does not create trust,
signatures, private keys, or signed-profile acceptance.

Trust fixtures are line-oriented public data. They may say which key ids are
trusted, rotated, revoked, or expired for a fixture, but they are not GOFTP/1
replay inputs. Suggested TSV shape:

```text
GOFTP-TRUST/1
key_id	suite	principal	role	status	not_before	not_after	revoked_at	reason
k1.example	fixture-ed25519-v1	player:alice	player	trusted	2026-01-01	-	-	fixture
```

Trust lifecycle status is deterministic and does not consult wall-clock time.
For verification, `trusted` keys are accepted, `rotated` keys are accepted for
old material, and `revoked` or `expired` keys fail. For publishing new material,
only `trusted` keys are accepted; `rotated`, `revoked`, and `expired` keys fail.
The date fields are public evidence attached to an explicit row, not replay
clocks.

Attestation fixtures are also public data. Public-key fixture signatures must
be visibly non-cryptographic placeholders, for example `fixture:<hex>`, until a
real suite is selected. HMAC fixture vectors may use public test keys for
deterministic parser and witness tests, but those fixture keys are not
production secrets. `gobanftp v1 trust-report --fixture <fixture-dir>` can
summarize public key records and `GOFTP-TRUST/1` rows, but old unsigned games
remain verified by the unsigned profile. Missing, untrusted, rotated, revoked,
or expired trust material is advisory state, not replay failure.

A signed/auth profile is an explicit profile with its own `profile_id`,
`consensus_version`, trust input, acceptance gate, fixtures, and diagnostics. It
may compose with a substrate profile for name discovery, but it must not change
the unsigned profile's meaning.

Signed/auth acceptance order:

1. Read and normalize candidate names according to the declared base substrate
   profile.
2. Parse direct event basenames as GOFTP/1 events.
3. Verify the filename event id against the game descriptor basename.
4. Verify the signed/auth profile's required signature for that event basename.
5. Deduplicate signed-accepted basenames by exact byte string.
6. Sort signed-accepted basenames lexicographically by byte value.
7. Compute `GOFTP-EVENT-SET/1` over the signed-accepted basenames.

Signature verification is therefore an event acceptance gate for the signed
profile. A basename that parses and has a correct filename event id, but lacks a
valid trusted signature, is excluded from that signed profile's
`event_set_root`. The same basename remains valid input for an unsigned
`GOFTP/1` profile.

Signing only `event_set_root` is not enough for a signed event-acceptance gate:
the root is computed after acceptance. Root-level signatures are set
attestations. They may be added by a later profile, but they cannot rescue,
insert, or reject an individual event before the accepted set is known.

`signed-hmac-goftp1` is implemented as the first production witness gate for
signed/auth acceptance. It is deliberately limited to explicit in-memory
verifier trust sets and deterministic HMAC-SHA256 fixture keys; it does not
define production private-key storage, rotation, revocation, or publish
authentication.

Its `key_id` is an explicit HMAC verifier selector, such as `fixture-key-1`,
not a `GOFTP-KEY/1` public-key id. `k1.` is reserved for public key records and
`GOFTP-TRUST/1`; it must not be accepted as a signed-HMAC key selector. A future
profile may define a public-key signing suite that uses `k1.` identities, but
that suite is not `signed-hmac-goftp1`.

`signed-hmac-goftp1` event attestation payload:

```text
version = GOFTP-HMAC-EVENT/1
algorithm = hmac-sha256
profile = signed-hmac-goftp1
```

Preimage:

```text
"GOFTP-HMAC-EVENT/1\0" ||
"profile=signed-hmac-goftp1\0" ||
"alg=hmac-sha256\0" ||
"key_id=<key_id>\0" ||
"game=<game_descriptor_basename>\0" ||
"event_id=<visible_event_id>\0" ||
"event=<event_basename>\0"
```

The profile id in this payload is the stable profile id, not the
`GOFTP-PROFILE/<profile_id>/1` contract-version label. The event id is the
visible `.h-<event-id>` suffix from the event basename and must match that
basename. Attestation records use the field name `algorithm`; the shorter
`alg=` string is only the canonical preimage label. The HMAC bytes are public
attestations; HMAC keys stay only in an explicit verifier trust set and must not
appear in filenames, projections, or diagnostics.

If multiple attestation records claim the same event basename, their substrate
or fixture order is not authoritative. Any valid trusted attestation accepts the
event. If none verify, the profile reports a stable signature diagnostic chosen
by diagnostic priority, not by listing order.

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

## Additional Profiles

The profiles below are v1.0 substrate targets beyond local and FTP. Git and DNS
remain planned read-normalizers. WebDAV now has a runtime store boundary,
publish semantics, mock store tests, and CLI parity tests; live credentials are
still deliberately outside the default test suite.

The production registry names these profiles so witness fixtures can compare
substrates through one API. `GobanFTP::Profile::Adapter` continues to normalize
fixture-like Git, DNS, and WebDAV listing presentations into visible names.
Runtime store admission is separate: Git and DNS remain planned until they have
full adapter/store boundaries, publish semantics, fixtures, and smoke commands.

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
implemented
```

Consensus version:

```text
GOFTP-PROFILE/webdav-goftp1/1
```

Substrate:

```text
WebDAV collection listing
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
extract direct resource basenames from href path segments under the current
game descriptor collection
percent-decode exactly once
reject dot segments, encoded traversal segments, encoded slash, and encoded
backslash before event-name acceptance
reject decoded names outside the GOFTP/1 public ASCII basename alphabet
normalize and verify GOFTP/1 event basenames
```

Publish algorithm:

```text
ensure the game, events/, and tmp/ collections exist through MKCOL
if events/<event_name> is already visible, treat publish as success
write a zero-byte temporary resource under tmp/
MOVE the temporary resource to events/<event_name> with Overwrite: F
verify publication by a bounded fresh PROPFIND of events/
optional mkcol publish mode creates events/<event_name> as a collection
```

Auth stance:

```text
WebDAV credentials protect transport access only
locks are publish coordination hints, not replay consensus
bearer tokens and passwords must never appear in filenames, projections,
diagnostics, or public fixtures
```

Fixtures and smoke:

```text
t/store-webdav-mock.t
t/webdav-cli-parity.t
t/fixtures/v1/cross-substrate/*/webdav-goftp1/listing.names
t/fixtures/v1/publish-failures/webdav-publish-failure/
GOBANFTP_STORE=webdav GOBANFTP_WEBDAV_URL=<url> perl -Ilib script/gobanftp play --once <game>
```

## Profile Admission Gate

A profile cannot move from `planned` to `implemented` until it has:

```text
written profile section
adapter or store boundary
read fixture
publish fixture or explicit read-only decision
attack fixtures or mock tests for ignored metadata
event_set_root parity fixture against local-goftp1
CLI or smoke command
diagnostics for malformed, rejected, stale, and conflicting inputs
```

The admission gate is intentionally strict. Profiles are how v1.0 prevents
protocol abuse from turning into protocol ambiguity.
