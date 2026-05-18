# Diagnostics Contract

GobanFTP diagnostics are for replay, projection, storage, and maintenance. They
must be stable enough for tests and scripts, but they are not a secret channel.

## Streams

CLI commands write machine-readable summaries to stdout and diagnostics to
stderr.

Stdout summary fields:

```text
gobanftp.create-game
gobanftp.play
gobanftp.project
gobanftp.publish-ack
gobanftp.publish-move
gobanftp.replay
gobanftp.sgf
gobanftp.verify
gobanftp.v1.compare-replay
gobanftp.v1.compare-roots
gobanftp.v1.witness
gobanftp.watch
gobanftp.<command>
fixture_id
game
game_descriptor
profile_id
profile_consensus_version
adapter_id
ruleset_id
ruleset_semver
ruleset_seal_version
ruleset_fixture_digest
ruleset_seal
comparison_scope
profile_count
profiles
baseline_profile
compared_fields
mismatch_count
mismatch_fields
mismatch_profiles
profile_roots
profile_replay_statuses
events
raw_count
normalized_count
normalized_events
accepted_count
accepted_events
rejected_count
rejected_codes
rejected_classes
event_set_count
event_set_root
replay_status
canonical_moves
legal_moves
canonical_tip
canonical_ids
legal_ids
diagnostic_codes
diagnostic_classes
diagnostic_count
board_hash
sgf_hash
variations_sgf_hash
attestation_count
trusted_hmac_key_ids
signature.status
snapshot
store
root
event
event_id
sgf
board
verdict
listing
turn_color
turn_player
worldline.status
worldline.canonical_ids
worldline.legal_ids
worldline.fork.parent_id
worldline.fork.child_ids
```

`play` and `watch` snapshots use the same replay summary fields as `verify` and
`replay`, then add turn and worldline fields. `watch` also emits `snapshot=<n>`
for bounded polls. `worldline.status` is one of `main`, `fork`, or
`validation`; fork snapshots include `worldline.fork.parent_id` and
`worldline.fork.child_ids`.

`event_set_count` is the number of direct event basenames accepted into the
`GOFTP-EVENT-SET/1` root after filename parsing and event-id verification.
`event_set_root` is the lowercase SHA-256 hex digest of that accepted event set.
It is a witness field for the observed listing, not a replay success claim.

For `gobanftp v1 witness`, `rejected_count`, `rejected_codes`, and
`rejected_classes` describe profile admission failures before replay, such as a
signed profile rejecting an event attestation. `diagnostic_count`,
`diagnostic_codes`, and `diagnostic_classes` describe replay diagnostics after
the accepted event set has been built. Both diagnostic families may emit stable
`diagnostic ...` lines on stderr.

The `ruleset_*` fields identify the replay rule contract used by the witness.
They are not inputs to `event_set_root`; `compare-replay` compares them so two
substrates cannot silently agree on event names while using different rule
semantics.

For `gobanftp v1 compare-roots` and `gobanftp v1 compare-replay`, a fork or
validation replay status is not itself a command failure. The compare commands
exit successfully when every compared profile agrees with the baseline witness,
and exit `2` only when `mismatch_fields` is non-empty.

Stderr diagnostics use one line per issue:

```text
diagnostic key=value key=value
```

The `code` field is required. Other fields are optional and depend on the
diagnostic code.

## Diagnostic Fields

Only scalar values and comma-joined arrays are emitted by the CLI diagnostic
line format. Nested objects are skipped. The CLI percent-encodes characters
outside the diagnostic token alphabet so every diagnostic remains one line:
letters, digits, `.`, `_`, `:`, `/`, `,`, and `-` are printed literally.

Allowed stderr diagnostic fields:

```text
child_ids
code
color
error
event_id
expected_color
expected_player
expected_ply
index
key_id
name
names
parent_id
parent_kind
player
ply
profile_id
reason
signature_id
stage
target_id
target_kind
trust_set_id
```

Field meanings:

```text
code             stable diagnostic code
name             public event basename
names            public event basenames, comma-joined
event_id         public 16-character event id
parent_id        public parent event id or genesis
target_id        public ack target event id
child_ids        public fork child event ids, comma-joined
color            submitted move color
expected_color   expected move color
player           submitted public player id
expected_player  expected public player id, or comma-joined allowed players for an ack
ply              submitted ply value
expected_ply     expected ply value
parent_kind      parsed kind of a bad parent event
target_kind      parsed kind of a bad ack target event
reason           rule engine reason string, or an ack target rejection reason
error            parser, rule, or storage error class
index            zero-based item index for malformed in-memory replay input
stage            pipeline stage that produced the diagnostic
profile_id       public profile id that produced the diagnostic
key_id           public signature key selector, not a secret
signature_id     public signature record selector or event id
trust_set_id     public trust-set label when one is configured
```

## Diagnostic Schema

The schema below is machine-readable by tests. `selector` refines a code when a
single code can report different logical classes. `required` and `optional` are
comma-joined stderr fields. A dash means no fields.

```diagnostic-schema
code|selector|class|required|optional
parse_event|error=event_id.*|event-id|code,name,error|-
parse_event|error=*|parse|code,name,error|-
parse_game_descriptor|*|parse|code,error|-
invalid_event_item|*|parse|code,index,stage|-
event_id_collision|*|event-id|code,event_id,names|-
missing_parent|*|dag|code,event_id,parent_id|-
parent_not_move|*|dag|code,event_id,parent_id,parent_kind|-
cycle|*|dag|code,event_id|-
dangling_ack_target|*|dag|code,event_id,target_id|-
ack_target_not_move|*|dag|code,event_id,target_id,target_kind|-
ack_target_invalid|*|dag|code,target_id,reason,error|-
wrong_color|*|rules|code,event_id,parent_id,expected_color,color|-
wrong_player|*|rules|code,event_id,parent_id,color,expected_player,player|-
wrong_ply|*|rules|code,event_id,parent_id,expected_ply,ply|-
illegal_move|*|rules|code,event_id,parent_id,reason|-
parent_not_legal|*|rules|code,event_id,parent_id|-
ack_wrong_player|*|rules|code,event_id,expected_player,player|-
rules|*|rules|code,error|-
fork|*|fork|code,parent_id,child_ids|-
missing_signature|*|signature|code,profile_id,name,event_id|-
wrong_signature|*|signature|code,profile_id,name,event_id,key_id,reason|-
untrusted_signature|*|signature|code,profile_id,name,event_id,key_id,reason|trust_set_id
malformed_signature|*|signature|code,profile_id,signature_id,reason|-
```

Current classes are:

```text
parse
event-id
dag
rules
fork
signature
```

`storage` is a reserved v1 diagnostic class. Signed/auth witness gates use the
`signature` class. Unsigned replay commands do not emit signature diagnostics,
because unsigned profiles ignore sidecar auth material.

Signature diagnostic codes:

```text
missing_signature
wrong_signature
untrusted_signature
malformed_signature
```

Required public fields:

```text
missing_signature   code,profile_id,name,event_id
wrong_signature     code,profile_id,name,event_id,key_id,reason
untrusted_signature code,profile_id,name,event_id,key_id,reason
malformed_signature code,profile_id,signature_id,reason
```

`missing_signature` reports an otherwise filename-valid event that has no usable
required signature under the signed profile. `wrong_signature` reports a trusted
key id whose MAC does not verify the canonical payload, including signatures
bound to a different profile, game descriptor, event basename, event id, or
algorithm. `untrusted_signature` reports a key id outside the active trust set
or outside its declared scope. `malformed_signature` reports a signature record
that cannot be parsed as the signed profile's declared format.

Signature diagnostics may print public event basenames, event ids, key ids,
profile ids, and trust-set labels. They must not print HMAC secrets, full MAC
values, private key material, or environment values.

Unknown direct move or ack event versions under `events/`, for example `m2.*`,
are reported as:

```text
diagnostic code=parse_event name=<event-basename> error=event.version
```

The unknown event name stays public and visible in diagnostics, but it is not
included in DAG or rule replay.

Known `code` values include:

```text
ack_target_invalid
ack_wrong_player
ack_target_not_move
cycle
dangling_ack_target
event_id_collision
fork
illegal_move
invalid_event_item
malformed_signature
missing_signature
missing_parent
parent_not_legal
parent_not_move
parse_event
parse_game_descriptor
rules
untrusted_signature
wrong_signature
wrong_color
wrong_player
wrong_ply
```

## Secret Handling

Diagnostics must not print passwords, bearer tokens, API keys, private key
material, cookie values, FTP credential URLs, or values from environment
variables whose names contain `PASSWORD`, `TOKEN`, `SECRET`, or `KEY`.

Public protocol names are not secrets. Event basenames, game descriptors, player
ids, event ids, parent ids, and target ids are designed to be visible in FTP
directory listings.

Maintenance scripts that capture command output must redact secret-looking
values before writing logs or reports.
