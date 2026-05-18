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
