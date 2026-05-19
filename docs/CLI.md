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

Set `GOBANFTP_STORE=git-tree` to read a declared Git tree snapshot. Git tree
mode is read-only; it can verify, replay, print SGF, and run bounded play/watch
inspection, but publish and create commands fail with storage exit code `4`.
It uses:

```text
GOBANFTP_GIT_REPO
GOBANFTP_GIT_TREEISH
GOBANFTP_GIT_BINARY
```

`GOBANFTP_GIT_REPO` is required in Git tree mode. `GOBANFTP_GIT_TREEISH`
defaults to `HEAD`, and `GOBANFTP_GIT_BINARY` defaults to `git`. Replay uses
direct child names from `<treeish>:<game>/events`; blob bytes, commit metadata,
refs, branches, and tags are not replay inputs.

Set `GOBANFTP_STORE=dns-record` to read a local or otherwise declared DNS-like
record file. DNS record mode is read-only; it can verify, replay, print SGF, and
run bounded play/watch inspection, but publish and create commands fail with
storage exit code `4`. It uses:

```text
GOBANFTP_DNS_RECORD_FILE
GOBANFTP_DNS_OWNER_SUFFIX
```

`GOBANFTP_DNS_RECORD_FILE` is required in DNS record mode.
`GOBANFTP_DNS_OWNER_SUFFIX` is optional. The CLI reads only the declared record
file and does not query live DNS, request AXFR, validate DNSSEC trust, call
provider APIs, use resolver cache state, or publish DNS records. TTL, record
order, answer order, cache age, DNSSEC status, authoritative server identity,
and provider metadata are not replay inputs.

Set `GOBANFTP_STORE=webdav` to use WebDAV. WebDAV event commands read and
write game descriptor collections and `events/` names under
`GOBANFTP_WEBDAV_URL` and use:

```text
GOBANFTP_WEBDAV_URL
GOBANFTP_WEBDAV_USER
GOBANFTP_WEBDAV_PASSWORD
GOBANFTP_WEBDAV_TOKEN
GOBANFTP_WEBDAV_TIMEOUT
GOBANFTP_WEBDAV_CLASS
GOBANFTP_WEBDAV_PUBLISH_MODE
```

`GOBANFTP_WEBDAV_URL` is required in WebDAV mode. `GOBANFTP_WEBDAV_TOKEN` is a
bearer token and cannot be combined with WebDAV user/password fields.
Credentials and tokens protect transport access only; they must never be printed
in status lines or diagnostics.

### Signed/Auth Operation And Key Lifecycle Boundary

`keygen`, `keyid`, `attest`, `publish-token`, `publish-auth`, and
`trust-report` belong to explicit auth profiles. They must not change unsigned
`GOFTP/1` replay. Until a signed profile declares otherwise, `verify`,
`replay`, `sgf`, `project`, `play`, and `watch` continue to read only the game
descriptor basename and accepted direct `events/` basenames.

Auth material is public unless it is private key material. Public key records,
trust files, and attestation records may appear in fixtures and sidecars, but
they are ignored by unsigned profiles. Private keys, seeds, passwords, bearer
tokens, HMAC secrets, and signing secrets must not appear in event basenames,
game descriptors, projection files, diagnostics, or public fixture examples.

`v1 keygen` is implemented only for the verifier-local signed-HMAC operation
path:

```text
gobanftp v1 keygen --profile signed-hmac-goftp1 --out <hmac-key-file>
```

It uses an operating-system random source, writes an explicit private key file
with mode `0600`, refuses to overwrite an existing file, and never prints the
HMAC secret. Its stdout reports only public operation fields:

```text
gobanftp.v1.keygen=ok
profile_id=signed-hmac-goftp1
algorithm=hmac-sha256
key_id=<public-hmac-selector>
key_path=<hmac-key-file>
```

Canonical verifier-local HMAC key file:

```text
GOFTP-HMAC-KEY/1
profile=signed-hmac-goftp1
algorithm=hmac-sha256
key_id=<16-char-public-hmac-selector>
secret_hex=<64-lowercase-hex-private-secret>
```

The key id is a verifier-local HMAC selector derived from the private secret. It
is public enough to appear in witness output, but it is not a `GOFTP-KEY/1`
`k1.` public-key id and does not create a public-key trust chain.

This is not a complete production key lifecycle. It does not define account
identity binding, public-key signing suites, revocation publication, key loss
recovery, automatic sidecar discovery, real writer authorization, or transport
authentication.

`v1 attest` writes HMAC attestations for the currently accepted event basenames
of a game for the signed-HMAC profile:

```text
gobanftp v1 attest --profile signed-hmac-goftp1 --key <hmac-key-file> --out <attestations.jsonl> <game-root|game-descriptor>
```

It reads the game through the normal configured store, attests only a clean
accepted event set for the selected game descriptor, writes public attestation
JSONL to a new output file, and refuses to overwrite the output file. For local
games, `--out` must be outside the game root so an attestation file cannot
become a replay-visible `events/`, `sidecar/`, `tmp/`, or projection artifact.
The command fails closed without writing attestations when the observed event
set or replay has diagnostics, including forks. It does not publish events,
alter replay, write sidecars, or make unsigned profiles read signatures.

Successful output is:

```text
gobanftp.v1.attest=ok
profile_id=signed-hmac-goftp1
game=<game-descriptor>
event_set_count=<n>
event_set_root=<sha256-hex>
attestation_count=<n>
key_id=<public-hmac-selector>
attestations=<attestations.jsonl>
```

Each public attestation row uses `GOFTP-HMAC-EVENT/1`, `hmac-sha256`,
`signed-hmac-goftp1`, the game descriptor basename, the exact event basename,
the visible event id, the public HMAC selector, and the HMAC signature. The
private HMAC secret must not appear in the JSONL, stdout, or diagnostics.

`v1 publish-token` writes one verifier-local publish-purpose HMAC token for one
proposed event basename under the signed-HMAC profile:

```text
gobanftp v1 publish-token --profile signed-hmac-goftp1 --key <hmac-key-file> --out <publish-token.jsonl> [--key-status trusted|rotated|revoked|expired] <game-root|game-descriptor> <event-basename>
```

The token payload uses `GOFTP-HMAC-PUBLISH/1` with `purpose=publish`. It binds
the game descriptor basename, exact event basename, visible event id, public
HMAC selector, profile, purpose, and algorithm. The command writes exactly one
public JSONL token row to a new output file. For local games that already exist,
`--out` must be outside the game root.

Lifecycle status has publish-purpose semantics: only `trusted` may mint fixture
publish-purpose material. `rotated`, `revoked`, and `expired` fail closed
before any output file is written. This is a fixture/verifier-local
publish-purpose token; it does not publish the event, authorize a real writer
account, change transport credentials, or make unsigned replay read signatures.

`v1 publish-auth` verifies a public publish token for one proposed event:

```text
gobanftp v1 publish-auth --profile signed-hmac-goftp1 --token <publish-token.jsonl> [--trusted-hmac-key <id=key>] [--trusted-hmac-key-file <hmac-key-file>] [--trusted-hmac-status <id=status>] <game-root|game-descriptor> <event-basename>
```

The command returns the fixture-preflight status literal `authorized` only when
the token verifies under an explicit verifier-supplied HMAC trust input and the
selector lifecycle status is `trusted` for publish. `rotated`, `revoked`, and
`expired` are denied for new material. `GOFTP-TRUST/1` public `k1.` rows do not
authorize signed-HMAC selectors, and HMAC selectors beginning with `k1.` remain
rejected.

Successful fixture-preflight output includes:

```text
gobanftp.v1.publish-auth=authorized
profile_id=signed-hmac-goftp1
game=<game-descriptor>
event=<event-basename>
event_id=<event-id>
key_id=<public-hmac-selector>
publish_auth.status=authorized
diagnostic_count=0
```

`publish-move`, `publish-ack`, `play --move`, `play --ack`, and `play --tui`
can explicitly opt into this verifier-local publish preflight gate:

```text
--publish-auth-token <publish-token.jsonl>
--publish-auth-profile signed-hmac-goftp1
--publish-auth-trusted-hmac-key <id=key>
--publish-auth-trusted-hmac-key-file <hmac-key-file>
--publish-auth-trusted-hmac-status <id=trusted|rotated|revoked|expired>
```

The gate is default-off. Without these options, the existing publish commands
do not read token files, key files, sidecars, or event bytes. When enabled, the
candidate event is still built and replay-validated first. Only then is the
publish token checked; denial exits `2`, prints signature-class diagnostics,
and does not call the configured store's publish primitive. This is a
verifier-local fixture gate for one candidate basename, not production writer
authorization.

`v1 keyid --fixture` is implemented as a read-only fixture command. Production
`keyid` remains reserved until a real public-key suite is selected:

```text
gobanftp v1 keyid --fixture <public-key-file>
```

It reads a fixture public key record, validates the public format, and prints
the derived key id. It must not read private key files and must not echo key
file contents in diagnostics. The fixture form accepts only fixture public key
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

Successful fixture output is:

```text
gobanftp.v1.keyid=ok
key_id=k1.jk4bs0r77srdlpds260hka9fpp49clpg
key_id_version=GOFTP-KEY/1
public_key_version=gobanftp-public-key-v1
suite=fixture-ed25519-v1
public_key_bytes=32
```

`v1 trust-report --fixture` is implemented as a read-only fixture command. It
summarizes public trust files and public key records, but it first runs the
normal profile replay boundary and reports the observed `event_set_root`.
Production `trust-report` and attestation reporting remain reserved until a
real signed/auth suite is selected.

```text
gobanftp v1 trust-report --fixture <fixture-dir>
```

Unsigned old games are verified exactly as before:

```text
gobanftp verify <game-root|game-descriptor>
```

If a trust report is run for an unsigned old game, the consensus result is still
the normal `verify` result. Missing trust material is reported as unsigned or
untrusted advisory state, not as replay failure. Only an explicit signed profile
may turn missing, bad, stale, or revoked signatures into validation failures.

The fixture trust-report form reads:

```text
<fixture-dir>/game.name
<fixture-dir>/listing.names
<fixture-dir>/keys/*.pub
<fixture-dir>/trust.tsv
```

`keys/` and `trust.tsv` are optional. `trust.tsv` is advisory only and supports
`trusted`, `rotated`, `revoked`, and `expired` status rows. The command does not
parse `attestations.tsv`, does not enforce signed-HMAC revocation, and does not
use wall-clock time for expiry decisions.

### `gobanftp v1 witness --profile <profile-id> [--substrate-profile <profile-id>] --fixture <fixture-dir> [--attestations <jsonl>] [--trusted-hmac-key <id=key>] [--trusted-hmac-key-file <hmac-key-file>] [--trusted-hmac-status <id=status>] [--surface text|html|terminal]`

Builds a read-only v1 witness from fixture files. The command reads:

```text
<fixture-dir>/game.name
<fixture-dir>/<profile-id>/listing.names
```

When `--profile signed-hmac-goftp1 --substrate-profile <profile-id>` is used,
the command reads `<fixture-dir>/<substrate-profile>/listing.names`, runs that
base profile's read normalizer, and then applies the explicit signed-HMAC
acceptance gate to the normalized candidate event basenames. The overlay
substrate must be one of the admitted read profiles:
`local-goftp1`, `ftp-goftp1`, `git-tree-goftp1`, `dns-record-goftp1`, or
`webdav-goftp1`.

For `dns-record-goftp1`, `listing.names` is the local or otherwise declared
record set admitted for the fixture witness. The CLI does not query live DNS,
request AXFR, validate DNSSEC trust, call provider APIs, use resolver cache
state, or publish DNS records. TTL, record order, answer order, cache age,
DNSSEC status, authoritative server identity, and provider metadata are ignored
before `event_set_root`.

For `signed-hmac-goftp1`, pass public attestation records with
`--attestations` and one or more explicit verifier keys with
`--trusted-hmac-key <id=key>` or `--trusted-hmac-key-file <hmac-key-file>`. The
key id is public, must be a single diagnostic-safe token, and may appear in
stdout or diagnostics; the key bytes must not be printed. The HMAC key id is a
verifier-local selector, not a `GOFTP-KEY/1` public key id. Selectors starting
with `k1.` are rejected for `--trusted-hmac-key` so fixture public-key trust
rows cannot silently authorize HMAC attestations. `--trusted-hmac-key-file`
reads the private-mode `GOFTP-HMAC-KEY/1` file written by `v1 keygen`;
duplicate selectors across inline and file keys are rejected.

The signed-HMAC overlay is read-only witness evidence. It does not write events,
publish sidecar files, discover attestation files automatically, authorize a
writer, define account identity binding, or provide transport authentication.

`--trusted-hmac-status <id=status>` is an explicit signed-HMAC lifecycle input.
It is separate from `GOFTP-TRUST/1` public key rows and applies only to a
selector already supplied by `--trusted-hmac-key` or
`--trusted-hmac-key-file`. If omitted, the selector is treated as `trusted`. For
verification, `trusted` and `rotated` selectors may accept signed material;
`revoked` and `expired` selectors reject it with `untrusted_signature` and a
lifecycle reason. This command has no publish path, so rotated publish rejection
is only a documented lifecycle rule.

The command calls `GobanFTP::Witness` and does not recompute roots, signatures,
or replay results inside CLI code. It does not write events or projections.

`--surface text|html|terminal` replaces the default key/value stdout summary with a
read-only inspection surface. `text` writes a `GOFTP-WITNESS-SURFACE/1` plain
text view. `html` writes self-contained static HTML suitable for redirecting to
a file. `terminal` writes a `GOFTP-TERMINAL-OBSERVATORY/1` static terminal
status panel with the witness root, replay status, signature status, board
hashes, and board/verdict projection excerpts. All formats are derived from the
same witness result and projection text already rendered by `GobanFTP::Witness`;
the CLI does not read
`projections/`, rerun replay, recompute `event_set_root`, or decide profile
acceptance. Exit codes and stderr diagnostics are unchanged.

On success, writes key/value fields such as:

```text
gobanftp.v1.witness=ok
profile_id=<profile-id>
profile_consensus_version=GOFTP-PROFILE/<profile-id>/1
adapter_id=<adapter-id>
substrate_profile_id=<profile-id>
substrate_adapter_id=<adapter-id>
game_descriptor=<game-descriptor>
ruleset_id=chinese-area-v1
ruleset_semver=1.0.0
ruleset_seal_version=GOFTP-RULESET-SEAL/1
ruleset_fixture_digest=<sha256-hex>
ruleset_seal=<sha256-hex>
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
declared fixture presentations normalize to the same root. Git tree and DNS
record profiles have read-only runtime admission boundaries, but this compare
command still reads fixture rows rather than opening a Git repository,
contacting DNS, or contacting a WebDAV server. DNS comparison is limited to the
local or declared record set and has no live DNS, AXFR, DNSSEC trust, provider
API, or publish behavior. `signed-hmac-goftp1` is excluded from this compare
matrix because it needs explicit attestation and trust inputs.

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

Compares ruleset seal, root, and replay-derived witness fields across profile
fixtures: `ruleset_id`, `ruleset_semver`, `ruleset_seal_version`,
`ruleset_fixture_digest`, `ruleset_seal`, `event_set_root`, accepted and
rejected event-set fields, replay status, canonical and legal ids, board hash,
SGF hashes, and diagnostic/rejection codes and classes/counts.

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
store=<local|ftp|webdav>
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

When `GOBANFTP_STORE=ftp`, `GOBANFTP_STORE=git-tree`, or
`GOBANFTP_STORE=webdav`, the argument may be the game descriptor basename and
the command reads that substrate's `events/` listing.

### `gobanftp replay <game-root|game-descriptor>`

Replays valid event names and prints canonical line summary.

Must not write authoritative events. May write no files.

The stdout summary includes the same event-set witness fields as `verify`.

When `GOBANFTP_STORE=ftp`, `GOBANFTP_STORE=git-tree`, or
`GOBANFTP_STORE=webdav`, the argument may be the game descriptor basename and
the command reads that substrate's `events/` listing.

### `gobanftp project <game-root|game-descriptor>`

Rebuilds `projections/` from the canonical line.

May overwrite projection files. Must not edit event names.

Projection writing is local-only for now. In `GOBANFTP_STORE=ftp`,
`GOBANFTP_STORE=git-tree`, or `GOBANFTP_STORE=webdav` mode, `project` exits
with storage code `4` before constructing a nonlocal connection or replaying
the nonlocal event listing instead of writing projection files beside the
current working directory. Use plain `sgf` to print SGF from nonlocal listings.

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

When `GOBANFTP_STORE=ftp`, `GOBANFTP_STORE=git-tree`, or
`GOBANFTP_STORE=webdav`, plain `sgf` may accept the game descriptor basename
and reads that substrate's `events/` listing. `sgf --write` writes local
projection files and is rejected in nonlocal store mode before constructing a
nonlocal connection or replaying the nonlocal event listing.

### `gobanftp publish-move [--nonce <n>] [--publish-auth-token <publish-token.jsonl>] [--publish-auth-trusted-hmac-key-file <hmac-key-file>] <game-root|game-descriptor> <aa|play-aa|pass|resign>`

Creates and publishes one move event name through the configured store. A bare
point such as `aa` is normalized to `play-aa`. The optional nonce must match
`[a-z0-9_-]{1,16}`; when omitted, the client generates one.

For local store, writes directly through the store abstraction.
For FTP store, writes a zero-byte `tmp/` entry then `RNTO` to `events/`.
For WebDAV store, writes a zero-byte `tmp/` resource then `MOVE`s it to
`events/` and confirms visibility with `PROPFIND Depth: 1`.

The default command order is:

```text
list events -> replay existing events -> validate candidate by replay
-> publish_event_name -> list events -> replay again
```

With explicit publish preflight auth enabled, the order is:

```text
list events -> replay existing events -> validate candidate by replay
-> verify publish token for the candidate -> publish_event_name
-> list events -> replay again
```

If the existing replay has a validation failure, the command exits `2` and does
not publish. If the existing replay has a fork, the command exits `3` and does
not publish. The auth gate is reached only after candidate replay validation.
An auth denial exits `2`, reports `publish_auth.status=denied`, and does not
publish. The command never reads event file bytes or sidecar files.

### `gobanftp publish-ack [--nonce <n>] [--publish-auth-token <publish-token.jsonl>] [--publish-auth-trusted-hmac-key-file <hmac-key-file>] <game-root|game-descriptor> <event-id>`

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

When publish preflight auth is enabled, the ack candidate must pass this
verifier-local token preflight with a token bound to the exact `a1.*` basename
and visible event id before the store write runs. A denied ack leaves no `a1.*`
event behind.

### `gobanftp play [--once|--tui] [--move <move>|--ack <event-id>] [--nonce <n>] [--publish-auth-token <publish-token.jsonl>] [--publish-auth-trusted-hmac-key-file <hmac-key-file>] <game-root|game-descriptor>`

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

With `--tui`, `play` opens a local raw terminal board when both stdin and stdout
are terminals. Arrow keys and `hjkl` move the cursor, Enter or an SGR mouse
click selects the point, and the same Enter or click confirms publication. `p`
selects pass, `R` selects resign, `r` reloads, and `q` exits without publishing.
After confirmation, input is locked while the publish path runs. A successful
publish leaves the TUI immediately and prints the same event and snapshot lines
as `play --move`, so another click cannot publish a second move from the same
TUI session. The TUI does not write projections and does not own replay truth;
it reloads the `events/` listing and uses the same publish validation path as
`publish-move`.

Terminal compatibility is intentionally conservative: SGR mouse is enabled on a
best-effort basis where available, while arrow keys and `hjkl` remain the
fallback for xterm-compatible PTY, multiplexer, and SSH environments. When
stdin or stdout is not a terminal, `play --tui` refuses to start instead of
silently falling back to a line parser. This is a supported fallback design,
not a cross-terminal compatibility matrix or terminal certification claim.

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

If publish preflight auth is enabled and denied, `play --move`, `play --ack`,
and `play --tui` print the failed publish summary and auth diagnostics without
rendering a post-publish board snapshot.

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
