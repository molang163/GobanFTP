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
gobanftp.watch
gobanftp.<command>
game
events
event_set_count
event_set_root
canonical_moves
legal_moves
canonical_ids
legal_ids
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

Stderr diagnostics use one line per issue:

```text
diagnostic key=value key=value
```

The `code` field is required. Other fields are optional and depend on the
diagnostic code.

## Diagnostic Fields

Only scalar values and comma-joined arrays are emitted by the CLI diagnostic
line format. Nested objects are skipped.

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
name
names
parent_id
parent_kind
player
ply
reason
stage
target_id
target_kind
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
```

Current classes are:

```text
parse
event-id
dag
rules
fork
```

`storage` and `signature` are reserved v1 diagnostic classes. They are not
emitted by current `diagnostic ...` replay lines.

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
missing_parent
parent_not_legal
parent_not_move
parse_event
parse_game_descriptor
rules
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
