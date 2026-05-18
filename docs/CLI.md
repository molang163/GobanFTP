# CLI Specification

The CLI name is `gobanftp`.

Commands should write human-readable status to stdout, diagnostics to stderr,
and use stable exit codes.

Commands use simple `key=value` status lines on stdout. Diagnostics use
single-line records on stderr beginning with `diagnostic`, followed by stable
`key=value` fields.

## Exit Codes

```text
0 success
1 invalid command or arguments
2 protocol validation failed
3 replay conflict needs attention
4 storage error
5 internal error
```

## Commands

### Store Selection

By default, commands use the local filesystem. Local descriptor arguments are
resolved under `GOBANFTP_ROOT`, or the current directory when unset.

Set `GOBANFTP_STORE=ftp` to use FTP. FTP event commands read and write game
descriptor and `events/` names under `GOBANFTP_FTP_ROOT` and use:

```text
GOBANFTP_FTP_HOST
GOBANFTP_FTP_USER
GOBANFTP_FTP_PASSWORD
GOBANFTP_FTP_PORT
GOBANFTP_FTP_PASSIVE
GOBANFTP_FTP_TIMEOUT
GOBANFTP_FTP_PUBLISH_MODE
```

`GOBANFTP_FTP_HOST` is required in FTP mode. The other fields are optional
unless required by the server.

### Draft Auth And Key Lifecycle Boundary

`keygen`, `keyid`, `attest`, and `trust-report` are reserved for explicit auth
profiles. They must not change unsigned `GOFTP/1` replay. Until a signed profile
declares otherwise, `verify`, `replay`, `sgf`, `project`, `play`, and `watch`
continue to read only the game descriptor basename and accepted direct
`events/` basenames.

Auth material is public unless it is private key material. Public key records,
trust files, and attestation records may appear in fixtures and sidecars, but
they are ignored by unsigned profiles. Private keys, seeds, passwords, bearer
tokens, HMAC secrets, and signing secrets must not appear in event basenames,
game descriptors, projection files, diagnostics, or public fixture examples.

Future `keygen` has two distinct modes:

```text
gobanftp keygen --out <private-key-file> --public-out <public-key-file>
gobanftp keygen --fixture --label <public-label>
```

The production form must use an operating-system CSPRNG, must write the private
key to an explicit file with private permissions, must fail if the private file
already exists, and must not print private bytes to stdout or stderr. Its stdout
may report only public fields such as `gobanftp.keygen=ok`, `key_id=...`, and
the public key path.

The fixture form must not create a signing-capable private key. It may emit only
deterministic public fixture key records for tests and documentation. A fixture
record is not a private key and cannot authorize a signed profile.

Future `keyid` is read-only:

```text
gobanftp keyid <public-key-file>
gobanftp keyid --fixture <public-key-file>
```

It reads a public key record, validates the public format, and prints the
derived key id. It must not read private key files and must not echo key file
contents in diagnostics. The fixture form accepts only fixture public key
records.

Canonical public key record:

```text
gobanftp-public-key-v1
suite=<suite-id>
public_hex=<lowercase-public-key-hex>
```

For fixture-only records, `suite` is `fixture-ed25519-v1` and `public_hex` is
exactly 32 public bytes encoded as 64 lowercase hex characters. The fixture
suite is deliberately not a real signing suite.

Key id preimage:

```text
"GOFTP-KEY/1\0" ||
suite || "\0" ||
public_key_bytes || "\0"
```

Key id encoding:

```text
key_id = "k1." || first 32 chars of lowercase base32hex(SHA256(preimage))
```

Only `suite` and public key bytes are key-id inputs. Labels, owners, comments,
trust status, creation time, and revocation time are metadata and do not change
the key id.

Example public fixture key:

```text
gobanftp-public-key-v1
suite=fixture-ed25519-v1
public_hex=000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f
```

Its key id is:

```text
k1.jk4bs0r77srdlpds260hka9fpp49clpg
```

Future `attest` writes only advisory public attestation records unless the
selected profile is an explicit signed profile:

```text
gobanftp attest --event-set-root <root> --key <private-key-file> <game-root|game-descriptor>
gobanftp attest --fixture --event-set-root <root> --key-id <key-id> <game-root|game-descriptor>
```

The production form is not specified until a real signing suite is selected.
The fixture form must write or print placeholder attestations that are visibly
fixture-only and not cryptographic signatures.

Event-set attestation preimage:

```text
"GOFTP-ATTEST-EVENT-SET/1\0" ||
profile_id || "\0" ||
game_descriptor_basename || "\0" ||
event_set_root_version || "\0" ||
event_set_root || "\0"
```

Event-name attestation preimage:

```text
"GOFTP-ATTEST-EVENT/1\0" ||
profile_id || "\0" ||
game_descriptor_basename || "\0" ||
event_basename || "\0"
```

Future `trust-report` is read-only. It may summarize public trust files,
public key records, and public attestations, but it must first run the normal
profile replay boundary and report the observed `event_set_root`.

```text
gobanftp trust-report [--trust-file <trust.tsv>] <game-root|game-descriptor>
gobanftp trust-report --fixture <fixture-dir>
```

Unsigned old games are verified exactly as before:

```text
gobanftp verify <game-root|game-descriptor>
```

If a trust report is run for an unsigned old game, the consensus result is still
the normal `verify` result. Missing trust material is reported as unsigned or
untrusted advisory state, not as replay failure. Only an explicit signed profile
may turn missing, bad, stale, or revoked signatures into validation failures.

### `gobanftp v1 witness --profile <profile-id> --fixture <fixture-dir> [--attestations <jsonl>] [--trusted-hmac-key <id=key>]`

Builds a read-only v1 witness from fixture files. The command reads:

```text
<fixture-dir>/game.name
<fixture-dir>/<profile-id>/listing.names
```

For `signed-hmac-goftp1`, pass public attestation records with
`--attestations` and one or more explicit verifier keys with
`--trusted-hmac-key <id=key>`. The key id is public, must be a single
diagnostic-safe token, and may appear in stdout or diagnostics; the key bytes
must not be printed.

The command calls `GobanFTP::Witness` and does not recompute roots, signatures,
or replay results inside CLI code. It does not write events or projections.

On success, writes key/value fields such as:

```text
gobanftp.v1.witness=ok
profile_id=<profile-id>
profile_consensus_version=GOFTP-PROFILE/<profile-id>/1
adapter_id=<adapter-id>
game_descriptor=<game-descriptor>
raw_count=<n>
normalized_count=<n>
accepted_count=<n>
rejected_count=<n>
event_set_root=<sha256-hex>
replay_status=<ok|fork|validation>
canonical_tip=<event-id|genesis>
canonical_ids=<comma-joined-event-ids>
legal_ids=<comma-joined-event-ids>
board_hash=<sha256-hex>
sgf_hash=<sha256-hex>
variations_sgf_hash=<sha256-hex>
signature.status=<unsigned|ok|failed>
```

If the witness has profile-gate rejections or replay validation diagnostics, the
command writes `gobanftp.v1.witness=failed`, emits stable diagnostics to stderr,
and exits `2`. A fork-only replay writes `gobanftp.v1.witness=fork` and exits
`3`.

`rejected_*` fields are profile admission failures before replay, including
signature failures. `diagnostic_*` fields are replay diagnostics for the accepted
event set.

### `gobanftp v1 compare-roots --fixture <fixture-dir> [--profiles <ids>]`

Compares `event_set_root` across the built-in unsigned fixture read-normalizer
matrix present under `<fixture-dir>`, or across the comma-joined `--profiles`
subset. The command reads the same `game.name` and per-profile `listing.names`
files as `v1 witness`.

This is a fixture/read-normalizer proof command. It demonstrates that the
declared fixture presentations normalize to the same root; it does not claim
that planned Git, DNS, or WebDAV profiles are fully admitted substrate adapters.
`signed-hmac-goftp1` is excluded from this compare matrix because it needs
explicit attestation and trust inputs.

On equality, exits `0` and writes fields such as:

```text
gobanftp.v1.compare-roots=ok
comparison_scope=fixture-read-normalizer
fixture_id=<fixture-basename>
profile_count=<n>
profiles=<comma-joined-profile-ids>
baseline_profile=<profile-id>
compared_fields=event_set_root
mismatch_count=0
mismatch_fields=
profile_roots=<profile-id>:<sha256-hex>,...
event_set_root=<sha256-hex>
accepted_count=<n>
accepted_events=<comma-joined-event-basenames>
rejected_count=<n>
```

If any compared profile differs from the baseline profile, the command writes
`gobanftp.v1.compare-roots=failed`, reports `mismatch_fields` and
`mismatch_profiles`, and exits `2`.

### `gobanftp v1 compare-replay --fixture <fixture-dir> [--profiles <ids>]`

Compares root and replay-derived witness fields across profile fixtures:
`event_set_root`, accepted and rejected event-set fields, replay status,
canonical and legal ids, board hash, SGF hashes, and diagnostic/rejection codes
and classes/counts.

Equal fork or equal validation witnesses are successful comparisons. The command
fails only when profiles disagree with the baseline witness.

### `gobanftp create-game <game-descriptor>`

Creates the game root plus empty `events/` and `tmp/` directories through the
configured store.

### `gobanftp create-game --id <id> --black <player> --white <player> [--size <n>] [--rules <id>] [--komi <milli>]`

Builds a game descriptor and creates it through the configured store. Defaults:
`--size 19`, `--rules chinese-area-v1`, `--komi 7500`.

On success, writes:

```text
gobanftp.create-game=ok
store=<local|ftp>
game=<game-descriptor>
root=<local-path-or-descriptor>
```

### `gobanftp verify <game-root|game-descriptor>`

Reads the game descriptor and `events/` listing. Verifies filename grammar,
event ids, and graph consistency.

Must not write authoritative events or projections.

The stdout summary includes `event_set_count=<n>` and
`event_set_root=<sha256-hex>` for the observed authoritative listing. These
fields describe the accepted filename event set; they do not mean replay
succeeded.

When `GOBANFTP_STORE=ftp`, the argument may be the game descriptor basename and
the command reads the FTP `events/` listing.

### `gobanftp replay <game-root|game-descriptor>`

Replays valid event names and prints canonical line summary.

Must not write authoritative events. May write no files.

The stdout summary includes the same event-set witness fields as `verify`.

When `GOBANFTP_STORE=ftp`, the argument may be the game descriptor basename and
the command reads the FTP `events/` listing.

### `gobanftp project <game-root|game-descriptor>`

Rebuilds `projections/` from the canonical line.

May overwrite projection files. Must not edit event names.

Projection writing is local-only for now. In `GOBANFTP_STORE=ftp` mode,
`project` exits with storage code `4` before constructing an FTP connection or
replaying the FTP event listing instead of writing projection files beside the
current working directory. Use plain `sgf` to print SGF from FTP listings.

On success, writes:

```text
projections/sgf/main.sgf
projections/sgf/variations.sgf
projections/board/current.txt
projections/board/points/<point>.txt
projections/graveyard/captures.txt
projections/oracle/board.txt
projections/oracle/verdict.txt
```

It also creates the containing `projections/board/`,
`projections/board/points/`, `projections/graveyard/`,
`projections/sgf/`, and `projections/oracle/` directories. The stdout
`sgf=`, `board=`, and `verdict=` paths report `main.sgf`,
`oracle/board.txt`, and `oracle/verdict.txt`.

If replay finds only a fork conflict, local `project` still writes rebuildable
fork projections, including `projections/sgf/variations.sgf` and an oracle
verdict with `status=fork`, then exits `3`. Validation failures still write no
projections.

### `gobanftp sgf <game-root|game-descriptor>`

Prints the main-line SGF to stdout by default. With `--write`, writes
`projections/sgf/main.sgf`.

With `--variations`, prints the variation-tree SGF. A fork-only replay exits
`3`, prints the variation tree to stdout, and emits the fork diagnostic on
stderr. `--write` and `--variations` cannot be combined.

When `GOBANFTP_STORE=ftp`, plain `sgf` may accept the game descriptor basename
and reads the FTP `events/` listing. `sgf --write` writes local projection
files and is rejected in FTP mode before constructing an FTP connection or
replaying the FTP event listing.

### `gobanftp publish-move [--nonce <n>] <game-root|game-descriptor> <aa|play-aa|pass|resign>`

Creates and publishes one move event name through the configured store. A bare
point such as `aa` is normalized to `play-aa`. The optional nonce must match
`[a-z0-9_-]{1,16}`; when omitted, the client generates one.

For local store, writes directly through the store abstraction.
For FTP store, writes a zero-byte `tmp/` entry then `RNTO` to `events/`.

The command order is:

```text
list events -> replay existing events -> validate candidate by replay
-> publish_event_name -> list events -> replay again
```

If the existing replay has a validation failure, the command exits `2` and does
not publish. If the existing replay has a fork, the command exits `3` and does
not publish. The command never reads event file bytes or sidecar files.

### `gobanftp publish-ack [--nonce <n>] <game-root|game-descriptor> <event-id>`

Creates and publishes one ack event for a known legal move event id. The acking
player is derived from the target move's opponent using the game descriptor
`pb`/`pw` binding. The optional nonce must match `[a-z0-9_-]{1,16}`.

`publish-ack` uses conservative replay for existing state and for the
post-publish reload. It rejects existing validation failures with exit `2`, but
it is allowed when the only existing problem is a fork. In that case it still
exits `3` after publishing because conservative replay continues to report the
fork.

Unknown, non-move, or non-legal targets are rejected without publishing and
reported as `diagnostic code=ack_target_invalid ...`.

### `gobanftp play [--once] [--move <move>|--ack <event-id>] [--nonce <n>] <game-root|game-descriptor>`

Renders a terminal snapshot of the current canonical board. The snapshot is
derived from the configured store's `events/` listing and replay result only.
It does not write projections.

With `--once`, the command prints one snapshot and exits with the replay exit
code. Without `--once`, `--move`, or `--ack`, it enters a plain terminal loop.
Accepted interactive input is:

```text
aa
play-aa
pass
resign
refresh
quit
exit
q
```

Bare points are normalized to `play-<point>`. `refresh` reloads the listing and
prints another snapshot. `quit`, `exit`, and `q` exit without publishing.

With `--move`, `play` publishes exactly one move through the same pipeline as
`publish-move`, then renders the updated board. If a concurrent publish creates
a fork before the post-publish reload, `play --move` still reports the event it
published, renders the fork snapshot, emits the fork diagnostic, and exits `3`:

```text
event=<published-event-basename>
event_id=<event-id>
gobanftp.play=ok
game=<game-descriptor>
events=<n>
event_set_count=<n>
event_set_root=<sha256-hex>
canonical_moves=<n>
legal_moves=<n>
turn_color=<b|w>
turn_player=<player-id>
worldline.status=<main|fork|validation>
worldline.canonical_ids=<comma-joined-event-ids>
worldline.legal_ids=<comma-joined-event-ids>
...
```

Candidate validation failures in interactive mode are printed and the loop
continues without publishing the candidate. Existing validation failures and
forks stop the loop with exit code `2` or `3`.

With `--ack`, `play` publishes one ack through the same target rules as
`publish-ack`, then reloads and renders the snapshot with explicit
ack-assisted replay. If the ack resolves the visible fork, the snapshot exits
`0` and `worldline.status=main`. Plain `play --once`, interactive `play`,
`watch`, `replay`, `sgf`, and `project` remain conservative by default on the
same listing.

### `gobanftp watch [--once] [--count <n>|--max-polls <n>] [--interval <seconds>] <game-root|game-descriptor>`

Repeatedly reloads the store listing and prints terminal snapshots. `--once` is
equivalent to `--count 1`. `--max-polls` is an alias for `--count`. The default
interval is two seconds; `--interval 0` is intended for bounded tests and scripts.

Each poll uses:

```text
list events -> sort event basenames -> replay -> render snapshot
```

The polling interval is not a replay input. `watch` never reads event file
contents, file size, mtime, LIST order, sidecar files, `tmp/`, or projections.
It exits `2` for validation failures and `3` for forks.
