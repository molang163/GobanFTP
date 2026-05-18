# Design Decisions

This file records durable design choices so future maintainers do not need to
infer them from scattered context.

## 001: Use GobanFTP / GOFTP/1

The project name is `GobanFTP`. The storage protocol is `GOFTP/1`.

Reason:

- `Goban` avoids confusion with the Go programming language.
- `FTP` names the central protocol abuse directly.
- `GOFTP/1` is short enough for event names and docs.

## 002: Use Merkle DAG, Not Single Canonical Hash Chain

A normal line of play is a hash chain of filename events, but the whole event
set is a DAG.

Reason:

- FTP weak consistency naturally creates forks.
- Forks should be visible and recoverable.
- A single hash chain treats ordinary network races as fatal.

## 003: Keep Filename Layer Boring

The project aesthetic may be strange, but protocol filenames must be
deterministic.

Reason:

- Event ids require stable names.
- Maintainers need explicit filename grammar.
- FTP clients vary too much to rely on exotic filenames or metadata.

## 004: Projections Are Not Truth

`projections/board/`, `projections/graveyard/`, `projections/sgf/`, and
`projections/oracle/*.txt` are projections.

Reason:

- Eating stones touches multiple board points.
- FTP has no transaction across multiple files.
- Rebuildable projections make failures easy to repair.

## 005: Inline::C Is for Rules, Perl Is for Protocol

Inline::C should implement low-level board mechanics. Perl should implement
filename protocol, storage, DAG, SGF, and CLI.

Reason:

- The source-art oracle stays maintainable.
- FTP and filename parsing are easier to inspect in Perl.
- The rule core can be small and testable.

## 006: No Secret Tokens in Filenames

Filenames are public. Any token in a filename is decorative or a nonce, not a
secret.

Reason:

- FTP listings expose names.
- Server logs expose names.
- The protocol should not pretend otherwise.

## 007: Use Canonical Filename Grammar

GOFTP/1 uses strict filename grammar as the core wire format.

Reason:

- listing alone should replay the game
- `RETR` should not be required for core protocol
- the project aesthetic should not leak into protocol bytes

## 008: Ack Is a Filename Event

Acknowledgements are event names under `events/`, not JSON objects.

Reason:

- one authoritative listing is easier to replay
- ack should respect the ls-first premise
- sidecar data must not become a second consensus layer

## 009: C Does Not Own Protocol Names

Inline::C may compute board mechanics, but Perl owns filename grammar, event id
calculation, and any state byte framing used by replay tests.

Reason:

- C structs can vary by platform
- endianness and integer size must not affect hashes
- protocol fixtures should be readable from Perl tests
- sidecar JSON remains optional and outside core replay

## 010: Prefer Simple Deterministic Rule Algorithms for v1

The v1 rule core uses full flood-fill for liberties and captures, board-copy
replay for forks, canonical board-byte hashes for repeated positions, and
ancestor hash comparison for positional superko.

Reason:

- 19x19 boards are small enough for complete checks per move
- simple replay is easier to test from filename fixtures
- branch correctness matters more than engine-style optimization
- incremental group caches and authoritative Zobrist hashes add complexity before
  the project has measured need

## 011: Algorithmic Elegance Must Preserve Testability

GobanFTP allows unusual aesthetics and compact algorithms, but algorithmic
elegance is defined as simpler invariants, fewer hidden states, and deterministic
listing-first replay.

Reason:

- future maintainers may over-optimize toward cleverness
- source art already provides enough theatrical surface
- the protocol depends on boring, reproducible filename semantics
- every elegant shortcut must still be fixture-testable

## 012: Source-Art Oracle Is Decorative

`oracle/goban.pl` may look like a goban and may optionally load Inline::C for a
tiny smoke function, but it must stay a thin wrapper around `lib/GobanFTP/*`.

Reason:

- source art must not become a second protocol implementation
- event ids, DAG construction, and rules stay in tested modules
- missing Inline::C must not break syntax checks or smoke runs

## 013: Projection Visuals Are Replay-Derived

`Projection.pm` writes SGF, board, point, graveyard, and oracle verdict files
from replay outputs and event names only. It does not read event file bytes,
sidecars, tmp files, or previous projection state.

Reason:

- replay already exposes canonical steps, legal branch children, events by id,
  and capture lists
- projection files can be deleted and rebuilt without consensus loss
- event bytes and projection files must remain non-authoritative
- verdict status should stay deterministic with `validation > fork > ok`

## 014: Ack-Assisted Recovery Is Explicit

Ack-assisted fork recovery is an explicit replay policy and CLI action, not the
default replay mode.

Reason:

- conservative replay must keep visible FTP races inspectable by default
- ack events already have stable filename grammar and event ids
- fork recovery should not require a new event type or store behavior
- `publish-ack` and `play --ack` make the player intent visible in listings
- SGF, projections, watch, and plain play should not silently resolve forks

## 015: Replay Inputs Are Name-First

`GobanFTP::Replay` treats event basenames as the authoritative replay input. If
callers pass legacy item hashes with both `name` and `event`, replay ignores the
event payload and reparses the name. Event payloads without names are rejected.

Reason:

- replay must preserve the listing-first protocol boundary
- filename grammar and event-id checks must not be bypassed by parsed objects
- low-level typed event APIs belong below replay, such as inside DAG fixtures

## 016: Source-Art Glyphs Are Non-Protocol

`oracle/goban.pl` may use executable ASCII glyphs such as `q(.)` and `q(+)` to
look like a Go board. Those glyphs are visual smoke-test input only. They must
not affect event ids, replay, rule legality, storage behavior, SGF output, or
projection rebuilding.

Reason:

- source code can be a visible ritual surface without becoming consensus
- changing comments, spacing, borders, or star-point artwork should not fork a
  game
- the oracle wrapper stays maintainable when protocol semantics remain in
  tested modules

## 017: Sidecar Signatures Are Advisory

`sidecar/` signatures, attestations, HMACs, tokens, notes, and other marginalia
may document trust notes or operator claims, but they are not `GOFTP/1`
consensus inputs.

Reason:

- deleting `sidecar/` must leave `GOFTP/1` core replay identical
- sidecar signatures must not affect replay, event ids, canonical line choice,
  fork resolution, publish acceptance, SGF output, or projection rebuilding
- HMACs, tokens, and secrets must not be placed in filenames or smuggled into
  `GOFTP/1` consensus
- any future signed-consensus mode must use a new protocol version or explicit
  profile instead of changing `GOFTP/1` sidecar interpretation

## 018: Listing Transcript Is a Projection

`projections/oracle/listing.txt` is a reader-facing transcript derived from the
authoritative game descriptor name, direct `events/` basenames, and replay
result. It is not a `GOFTP/1` consensus input.

Reason:

- the transcript makes the listing-first read path inspectable
- deleting or rebuilding it must not affect event ids, DAG replay, fork
  resolution, rules validation, SGF output, or board state
- transcript wording, formatting, and ordering are explanatory surface, not
  protocol semantics
- replay must continue to ignore existing projection files

## 019: v0.1 Does Not Expand GOFTP/1 Consensus

The v0.1 release boundary freezes `GOFTP/1` consensus around the existing
descriptor-name and direct-`events/` filename protocol. v0.1 may harden docs,
release checks, examples, projections, FTP smoke coverage, and terminal
playability, but it must not add new consensus inputs or new result/scoring
semantics.

Reason:

- the v0.1 goal is playable protocol artwork, not a larger rules or trust model
- scoring and final result events need their own future phase or decision
- signed consensus needs a future protocol version or explicit profile
- release hardening should make the current boundary clearer instead of moving it

## 020: Other Systems Need Explicit Profiles

GobanFTP may grow beyond FTP in v1.0. Additional systems must enter through an
explicit profile, adapter, or projection boundary. They must not silently change
`GOFTP/1` replay, event ids, DAG construction, rule legality, SGF output, or
projection rebuilding.

Reason:

- the v1.0 work should make the protocol-abuse surface larger without making
  the v0.1 contract vague
- every new system needs a written list of authoritative inputs and ignored
  metadata before it can be trusted
- transport quirks such as ordering, timestamps, object size, and payload bytes
  must not become accidental consensus
- if a new system needs different consensus inputs, it deserves a new protocol
  version or explicit profile with fixtures

## 021: v1.0 Is A Proof Machine

The v1.0 release target is not a game server. It is a proof machine that shows a
Go game can emerge from untrusted enumerable substrates while preserving the
same replay truth for the same accepted event basenames.

Reason:

- a hard Definition of Done prevents the v1.0 route from becoming a loose
  collection of backends and displays
- `event_set_root` should commit to the accepted event set for witness
  comparison without becoming a `GOFTP/1` event-id input
- attack fixtures, grammar vectors, diagnostics, ruleset seals, and
  cross-system witnesses are release assets, not optional polish
- source art, C acceleration, terminal interfaces, and Web views may reveal the
  proof, but they must not decide truth

## 022: Source-Art Motifs Are Surfaces

GobanFTP may use repeated source-art motifs such as an altar, goban, hash seal,
DAG tree, FTP gate, projection mirror, witness eye, root monolith, signature
seal, observatory, and a small arch-gate easter egg.

Reason:

- a motif register makes the repository feel intentionally strange instead of
  randomly decorated
- each picture should correspond to a protocol responsibility readers can audit
- the arch-gate easter egg is a hidden developer wink, not project branding,
  protocol naming, package metadata, or an official affiliation claim
- source-art motifs must remain outside event ids, `event_set_root`, replay,
  rule legality, SGF, storage semantics, and diagnostics

## 023: Signed HMAC Gates Event Acceptance

The first signed/auth profile target is `signed-hmac-goftp1`. It uses
per-event HMAC verification as a signed profile acceptance gate after GOFTP/1
filename parsing and event-id verification, and before `event_set_root`
calculation.

Reason:

- unsigned `GOFTP/1` must keep replaying from the game descriptor basename and
  direct `events/` basenames alone
- sidecar signatures remain ignored input for unsigned profiles
- a per-event HMAC can reject one unsigned, wrong, or untrusted event before it
  enters the signed profile's accepted set
- the HMAC payload must bind the profile id, algorithm id, public HMAC key
  selector, game descriptor basename, exact event basename, and visible event id
- signing only `event_set_root` is a post-acceptance set attestation; it cannot
  decide which individual basenames enter the root
- key ids are public selectors, while HMAC secrets live only in an explicit
  verifier trust set and must never appear in filenames, projections, or
  diagnostics

## 024: Production Witness API Starts With Explicit Gates

`GobanFTP::Witness` is the production read-only witness assembly point for v1
substrate profiles. It accepts a profile id, game descriptor, and raw listing
rows, then delegates listing presentation differences to
`GobanFTP::Profile::Adapter` before computing `event_set_root`, replay status,
board hash, SGF hash, and diagnostic classes. Explicit signed profiles may add
an acceptance gate after GOFTP/1 filename and event-id validation.

Reason:

- unsigned `GOFTP/1` and baseline profiles can move out of test-only harnesses
  without changing event filename grammar, event id preimages, DAG replay, rules,
  SGF, or projection semantics
- Git and DNS are useful v1.0 proof fixtures as read-normalizers; both now have
  read-only runtime admission, while DNS publish, live DNS, AXFR, DNSSEC trust,
  and provider APIs remain outside the current profile. WebDAV has an admitted
  runtime store while its fixture read-normalizer remains part of the
  cross-substrate witness matrix
- bad event-looking basenames must still reach replay diagnostics even if the
  event-set root gate rejects them, because rejected truth should be visible
  rather than silently filtered away
- the signed-HMAC gate must be an explicit profile behavior, not a hidden
  modifier on unsigned `GOFTP/1`

## 025: Signed HMAC Has No Key Lifecycle Yet

`signed-hmac-goftp1` is production witness behavior for deterministic signed
acceptance, but it is not a production key-management system. Verifiers pass an
explicit in-memory trust set to `GobanFTP::Witness`; HMAC secrets stay outside
filenames, projections, diagnostics, and generated witness output.

Reason:

- v1.0 needs a real signed acceptance gate before display surfaces can honestly
  show signature status
- key generation, rotation, revocation, private-key storage, and publish
  authentication have different threat boundaries and should not be implied by
  fixture HMAC vectors
- unsigned profiles must continue ignoring attestations, trust files, sidecar
  signatures, and HMAC records completely
- signature diagnostics may expose public event basenames, event ids, key ids,
  and profile ids, but never HMAC secrets

## 026: Ruleset Seal Is Semantic Witness Metadata

`chinese-area-v1` has a `GOFTP-RULESET-SEAL/1` witness seal built from an
explicit semantic preimage and the byte digests of the current rule fixtures.
The seal is reported by `GobanFTP::Witness` and compared by `v1 compare-replay`,
but it is not an input to `event_set_root`.

Reason:

- `event_set_root` must remain a commitment to accepted event basenames, not to
  local replay implementation details
- witnesses still need to prove which rule contract interpreted those basenames
- the seal must be independent of Inline::C availability, selected rule engine,
  source-art layout, projection text, platform, and environment
- fixture digests force a deliberate seal decision when rule behavior vectors
  change

## 027: WebDAV Uses PROPFIND And MOVE As Transport Ceremony

`webdav-goftp1` is admitted as a runtime store/profile without changing
`GOFTP/1` replay. WebDAV reads use `PROPFIND Depth: 1`; only direct href
basenames under `events/` can become candidate event names. WebDAV publishes use
a zero-byte temporary resource under `tmp/`, `MOVE` to `events/<event_name>` with
overwrite disabled, and a bounded fresh `PROPFIND` confirmation.

Reason:

- href order, ETag, Last-Modified, content length, display name, lock state,
  resource body bytes, `tmp/`, sidecars, and projections must not become replay
  inputs
- a visible final event name is immutable; an already visible identical final
  basename is publish success
- credentials, bearer tokens, and WebDAV locks protect transport operations
  only and must not alter unsigned event acceptance
- the WebDAV store should share the local/FTP storage interface so CLI flows can
  remain listing-first and projection writes can stay local-only

## 028: Fixture Key IDs Are Public Identity, Not Trust

`gobanftp v1 keyid --fixture` derives `GOFTP-KEY/1` `k1.` key ids from public
fixture key records. The id preimage contains only the suite id and public key
bytes; labels, principals, comments, trust status, creation time, and revocation
metadata are excluded. This fixture command is read-only and does not create
private keys, signatures, trust, or signed-profile acceptance.

Reason:

- v1.0 needs stable public key identity before it can honestly describe
  rotation, revocation, or trust reports
- HMAC key selectors are secret-verifier fixture inputs and must not be confused
  with public `GOFTP-KEY/1` identities
- unsigned `GOFTP/1` must continue ignoring public key records, trust files,
  sidecars, and attestations
- fixture key ids provide a testable auth surface without pretending that a real
  Ed25519 lifecycle or production private-key store exists

## 029: Fixture Trust Reports Are Advisory

`gobanftp v1 trust-report --fixture` reads a fixture game descriptor, raw local
listing, public fixture keys, and optional `GOFTP-TRUST/1` TSV rows. It runs the
normal `local-goftp1` witness first and reports trust state after that witness.
Trust rows can describe `trusted`, `rotated`, `revoked`, and `expired` key ids,
but this command does not parse attestations and does not enforce signed-HMAC
revocation or expiry.

Reason:

- v1.0 needs a public vocabulary for key lifecycle before signed profiles can
  enforce revoked or expired keys
- revoked or expired public trust rows must not make old unsigned `GOFTP/1`
  games fail
- the event set root, replay status, board hash, and SGF remain consequences of
  accepted event basenames, not trust metadata
- fixture trust reporting can expose lifecycle state without creating a real
  private-key system or production trust store

## 030: Signed-HMAC Does Not Use Public `k1.` Key IDs

`signed-hmac-goftp1` keeps using explicit verifier-local HMAC selectors such as
`fixture-key-1`. These selectors are public diagnostic labels for secrets passed
through the verifier trust set. They are not `GOFTP-KEY/1` public key ids and
must not start with `k1.`. Public `k1.` ids remain reserved for public key
records and `GOFTP-TRUST/1` rows.

Trust lifecycle status has deterministic meaning when a future signed profile
chooses to enforce it:

```text
status   verify old material   publish new material
trusted  accept                accept
rotated  accept                reject
revoked  reject                reject
expired  reject                reject
```

`not_before`, `not_after`, and `revoked_at` are explicit public row evidence,
not wall-clock replay inputs. P12c-0 defines this boundary and rejects `k1.`
HMAC selectors; it does not make advisory `GOFTP-TRUST/1` rows authorize or
reject `signed-hmac-goftp1` events.

Reason:

- `fixture-ed25519-v1` public keys are parser fixtures and not HMAC secrets
- silently mapping public `k1.` trust rows onto HMAC secrets would merge two
  different authentication models
- rotated keys must be able to verify old material without publishing new
  material
- signed/auth lifecycle policy needs deterministic rows, not ambient time

## 031: Signed-HMAC Lifecycle Enforcement Is Explicit Verifier Input

`signed-hmac-goftp1` may enforce HMAC selector lifecycle status only when the
verifier supplies that status as part of the signed-HMAC trust input. The
fixture CLI expresses this with `--trusted-hmac-key <id=key>` plus optional
`--trusted-hmac-status <id=status>`. Omitted status means `trusted`.

For verification, `trusted` and `rotated` selectors can accept old signed
events. `revoked` and `expired` selectors reject before MAC verification and
emit `untrusted_signature` with `reason=key.revoked` or `reason=key.expired`.

This is deliberately separate from `GOFTP-TRUST/1`: public key trust rows do
not authorize, revoke, or expire HMAC selectors, and `trust-report` remains an
advisory report rather than an enforcement command.

Reason:

- signed-HMAC is a symmetric fixture verifier, not a public key suite
- lifecycle enforcement must be explicit profile input, never an unsigned
  replay input
- revoked or expired selectors should fail before spending semantics on MAC
  validity
- the signed profile can harden without changing `GOFTP/1`, `local-goftp1`, or
  cross-substrate unsigned witnesses

## 032: Source-Art Smoke Displays Witness Truth

The executable source-art wrapper may display protocol proof fields, but it
must receive those fields from `GobanFTP::Witness`. The smoke path can show
profile id, adapter id, `event_set_root`, replay status, canonical tip, board
hash, SGF hash, and diagnostic count. It must not own filename grammar, event
id calculation, DAG replay, rules, projection hashing, storage normalization,
or signed profile acceptance.

Visual board glyphs and Inline::C availability are presentation/smoke inputs
only. Tests must prove they do not change the witness truth fields.

Reason:

- P13 needs a visible proof surface before larger TUI or Web work
- source art should reveal the proof machine without becoming another protocol
  implementation
- `GobanFTP::Witness` is already the v1 read-only assembly point for profile
  truth
- optional acceleration and decorative glyphs must remain outside replay,
  `event_set_root`, board hash, SGF hash, and diagnostics

## 033: Surface Renderers Format Existing Witnesses

Reusable inspection surfaces may format fields that already exist in a
`GobanFTP::Witness` result and may include already-rendered projection text.
They must not read storage, normalize listings, parse event names, compute event
ids, recompute `event_set_root`, run replay or rules, hash projection text, or
decide signed profile acceptance.

`GobanFTP::Surface::WitnessView` is the first module on this boundary. It can
render plain text and static HTML for inspection, and tests force the consensus
entry points to fail while the renderer still works from supplied data.

Reason:

- P13 needs a shared base for terminal and static Web observatory surfaces
- display code should be removable or replaceable without changing proof
  fields
- static HTML and terminal formatting are presentation artifacts, not another
  witness assembler
- witness roots, replay status, SGF hashes, board hashes, diagnostics, and
  signature status must stay consequences of the supplied witness data
