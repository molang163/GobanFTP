# GOFTP/1 Filename Grammar

This document is the implementation-facing filename grammar for GOFTP/1. It is
intended for independent implementations that need to parse, validate, hash, and
replay public directory-entry names without reading event file bytes.

GOFTP/1 consensus input is limited to:

```text
game descriptor directory basename
direct events/ child basenames
```

Event file contents, file size, entry type, timestamps, listing order, sidecars,
temporary entries, and projections are not grammar inputs.

## Public ASCII Names

Protocol basenames are public. They are exposed by directory listings, server
logs, mirrors, screenshots, and diagnostics. Do not put passwords, bearer tokens,
HMAC secrets, private keys, session ids, or other secrets in GOFTP/1 filenames.

All protocol basenames are ASCII and use only:

```text
a-z 0-9 . _ -
```

Dot is structural. Field values must not contain dot. Slashes are path
separators, not basename characters. Percent escapes, Unicode, spaces, colons,
shell metacharacters, and control characters are invalid.

Implementations should keep event basenames under 120 bytes where practical.

## Near-ABNF

This grammar is intentionally close to ABNF, but uses regex-style `{n}` and
`{m,n}` repetition for readability.

```text
lower          = "a" / "b" / "c" / "d" / "e" / "f" / "g" / "h" /
                 "i" / "j" / "k" / "l" / "m" / "n" / "o" / "p" /
                 "q" / "r" / "s" / "t" / "u" / "v" / "w" / "x" /
                 "y" / "z"
digit          = "0" / "1" / "2" / "3" / "4" / "5" / "6" / "7" /
                 "8" / "9"
base32hex      = digit / "a" / "b" / "c" / "d" / "e" / "f" / "g" /
                 "h" / "i" / "j" / "k" / "l" / "m" / "n" / "o" /
                 "p" / "q" / "r" / "s" / "t" / "u" / "v"
atom-char      = lower / digit / "_" / "-"
atom           = 1*(atom-char)

uint           = "0" / (("1" / "2" / "3" / "4" / "5" / "6" /
                 "7" / "8" / "9") *digit)
size           = uint            ; integer 2..26, no leading zero
komi-milli     = uint            ; integer >= 0, no leading zero except "0"
ply            = 6digit          ; p000001, p000002, ...
color          = "b" / "w"
point          = lower lower     ; both coordinates must be inside board size
action         = "play-" point / "pass" / "resign"
event-id       = 16base32hex
parent         = "genesis" / event-id
target         = event-id
nonce          = 1*16(atom-char)
game-id        = atom
rules-id       = atom
player-id      = atom

game-descriptor =
    "g1.id-" game-id
    ".s" size
    ".r-" rules-id
    ".k" komi-milli
    ".pb-" player-id
    ".pw-" player-id

move-event-without-hash =
    "m1.p" ply
    "." color
    "." action
    ".pa-" parent
    ".by-" player-id
    ".n-" nonce

move-event =
    move-event-without-hash ".h-" event-id

ack-event-without-hash =
    "a1.t-" target
    ".by-" player-id
    ".n-" nonce

ack-event =
    ack-event-without-hash ".h-" event-id

event-basename = move-event / ack-event
```

Additional semantic checks:

- `size` must be from 2 through 26.
- `point` is row-major SGF-style wire coordinate; `aa` is top-left and the
  letter `i` is not skipped.
- Both point coordinates must be less than the descriptor size.
- `player-id` in a move must match the descriptor player for that color.
- `pa-genesis` is valid only for a first black move candidate.
- Non-genesis parents must identify existing move events, not ack events.
- `ply` must equal parent depth plus one for a legal replay candidate.
- Ack targets must identify move events.
- Ack publishers must be one of the descriptor players.

Unknown direct event versions such as `m2.*` or `a2.*` are visible listing
inputs, but they are not GOFTP/1 events. They should produce a stable parse
diagnostic and be excluded from event-id maps, DAG construction, rule replay,
and projections.

Recursive descendants such as `events/<event-basename>/child` are not direct
event basenames and must be ignored before grammar parsing.

## Event ID

The event id is derived from the canonical event basename without the final
`.h-<event-id>` segment.

Preimage bytes:

```text
"GOFTP-EVENT/1\0" ||
game_descriptor_basename || "\0" ||
event_name_without_hash
```

`game_descriptor_basename` is the direct game root basename. It does not include
a path prefix or trailing slash.

`event_name_without_hash` is the direct `events/` child basename with the final
`.h-<event-id>` segment removed. It does not include `events/`, any parent path,
or recursive child names.

Hash and encoding:

```text
digest       = SHA256(preimage)
encoded      = lowercase base32hex(digest), no padding
event-id     = first 16 characters of encoded
```

Base32hex alphabet is:

```text
0123456789abcdefghijklmnopqrstuv
```

The 16-character filename id is an 80-bit short id. If two different event
basenames produce the same short id, implementations must report an event-id
collision and must not silently choose one colliding event.

## Golden Event Vectors

For this game descriptor:

```text
g1.id-minimal.s9.r-chinese-area-v1.k7500.pb-alice.pw-bob
```

These event basenames are canonical vectors:

```text
m1.p000001.b.play-dd.pa-genesis.by-alice.n-k31v.h-f98qai37nace5spg
m1.p000002.w.play-ee.pa-f98qai37nace5spg.by-bob.n-q9az.h-5ivvsvtid3j6u1pg
a1.t-f98qai37nace5spg.by-bob.n-s7p2.h-tim1sb5lpmd0d4q5
```

Their event-name-without-hash values are:

```text
m1.p000001.b.play-dd.pa-genesis.by-alice.n-k31v
m1.p000002.w.play-ee.pa-f98qai37nace5spg.by-bob.n-q9az
a1.t-f98qai37nace5spg.by-bob.n-s7p2
```

Expected event ids:

```text
f98qai37nace5spg
5ivvsvtid3j6u1pg
tim1sb5lpmd0d4q5
```

## Draft Event Set Root

`event_set_root` is a draft profile/witness hash for comparing independent
listings. It is not part of GOFTP/1 event id calculation and must not change
canonical replay unless a future profile explicitly adopts it.

Inputs:

1. The game descriptor basename.
2. The sorted direct event basenames accepted as valid GOFTP/1 event packets.

For `event_set_root`, accepted means the basename parses as a GOFTP/1 `m1` or
`a1` event and its filename event id verifies against the game descriptor. A DAG
or rule-invalid event with valid grammar and event id is still accepted into the
event set root, because it is a visible GOFTP/1 packet. Malformed names, unknown
event versions, bad event ids, recursive descendants, and non-authoritative
surfaces are rejected or ignored outside the root and must remain visible through
diagnostics when applicable.

Normalization:

1. Inspect only direct `events/` child basenames.
2. Parse GOFTP/1 `m1` and `a1` event names and verify their event ids.
3. Reject malformed names, unknown versions, and event-id failures into
   diagnostics; do not include them in the root.
4. Remove duplicate accepted basenames by exact basename.
5. Sort accepted basenames lexicographically by byte value.
6. Do not read event bytes, sidecars, projections, temporary files, mtimes,
   sizes, entry types, or listing order.

Draft preimage:

```text
"GOFTP-EVENT-SET/1\0" ||
game_descriptor_basename || "\0" ||
event_count_decimal || "\0" ||
event_basename_1 || "\0" ||
event_basename_2 || "\0" ||
...
event_basename_N || "\0"
```

Draft encoding:

```text
event_set_root = lowercase hex SHA256(draft_preimage)
```

The terminal NUL after every basename is intentional. The decimal count has no
leading zero except `0`.

## Suggested Vector Fixture Layout

Future golden vectors should be file-based so other implementations can consume
them without importing Perl modules.

Suggested directory:

```text
t/fixtures/vectors/
  README.md
  grammar-valid.jsonl
  grammar-invalid.jsonl
  event-id.jsonl
  listing-normalization.jsonl
  event-set-root.jsonl
```

Suggested records:

```json
{"id":"minimal-game","kind":"game_descriptor","name":"g1.id-minimal.s9.r-chinese-area-v1.k7500.pb-alice.pw-bob","ok":true,"fields":{"game_id":"minimal","size":9,"rules":"chinese-area-v1","komi_milli":7500,"black":"alice","white":"bob"}}
{"id":"minimal-move-1","kind":"event_id","game_descriptor":"g1.id-minimal.s9.r-chinese-area-v1.k7500.pb-alice.pw-bob","event_without_hash":"m1.p000001.b.play-dd.pa-genesis.by-alice.n-k31v","event_id":"f98qai37nace5spg"}
{"id":"bad-uppercase","kind":"event","name":"M1.p000001.b.play-aa.pa-genesis.by-alice.n-a.h-0000000000000000","ok":false,"error":"filename.charset"}
```

Vector expectations should include:

- exact parse fields for valid game descriptors, moves, and acks
- stable error codes for invalid charset, field count, bounds, event version,
  event-id length, event-id alphabet, and event-id mismatch
- event id preimage inputs and expected short ids
- listing normalization inputs and sorted visible event basenames
- draft `event_set_root` inputs and expected digest
- duplicate exact basenames and event-id collision cases
- unknown direct event versions preserved for parser diagnostics and excluded
  from `event_set_root`
- recursive `events/<name>/child`, `tmp/`, `sidecar/`, and `projections/`
  entries ignored before parsing

Vectors should contain only public ASCII filenames and expected values. They
must not contain secrets, credentials, private tokens, hostnames with passwords,
or environment-specific paths.
