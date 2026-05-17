# Attack Fixture Gallery

The attack fixture gallery is a planned proof set for hostile or misleading
listings. It exists to show that GobanFTP keeps the `GOFTP/1` replay boundary
boring under pressure: game descriptor basenames and direct `events/` child
basenames are authoritative; metadata, payloads, sidecars, projections, and
temporary files are not.

Attack fixtures are protocol proof assets. They are not a fuzz garbage dump.
Each sample must be small enough to inspect, stable enough to document, and
specific enough that a failing outcome tells maintainers which protocol boundary
was weakened.

## Directory Purpose

Test attack fixtures live under:

```text
t/fixtures/attacks/
```

Reader-facing copies or larger specimens may later live under
`examples/fixtures/attacks/`, but `t/fixtures/attacks/` is the authoritative test
gallery.

Each child directory is one named attack specimen. A specimen should contain the
minimum game tree needed to demonstrate the attack and its expected rejection,
ignore behavior, or conflict report. When a case needs explanatory non-consensus
material, place it in `sidecar/` or another ignored surface and make the verdict
prove that replay did not depend on it.

The directory is for hand-curated examples, not random input accumulation. New
fixtures should be admitted only when they clarify a distinct invariant,
diagnostic, store behavior, or recovery path.

## Verdict Format

Each attack sample should have a verdict record that can be regenerated from the
fixture. The preferred file is:

```text
expected.verdict
```

The verdict uses one `key=value` field per line:

```text
attack=<attack-name>
status=<ok|ignored|validation|fork|storage>
exit=<0|2|3|4>
game=<game-descriptor>
events=<normalized-event-count>
canonical_moves=<count>
legal_moves=<count>
diagnostic.code=<code-or-empty>
diagnostic.class=<class-or-empty>
diagnostic.error=<error-or-empty>
consensus_inputs=descriptor,events
ignored_inputs=<comma-joined-ignored-surfaces>
note=<short-human-readable-judgment>
```

Rules:

- `attack` must match the fixture directory basename.
- `status` must describe the replay or store outcome, not the attacker's intent.
- `exit` must match the CLI exit code expected from the primary command.
- `diagnostic.class` must match the diagnostics schema for the expected
  diagnostic code, or be empty when the sample has no diagnostic.
- `consensus_inputs` must stay `descriptor,events` for `GOFTP/1` core replay.
- `ignored_inputs` names the misleading surfaces that were present but ignored.
- `note` is explanatory text only. It is not test input.

Additional fields may be added when a case needs them, but they must be stable,
public, and directly tied to the attack judgment.

The test gallery also uses `mode=<local|listing>` and `command=<command-name>`
to name the harness path. `local` fixtures are copied into a temporary game root
before running the CLI. `listing` fixtures exercise raw observed names directly
when the hostile condition, such as duplicate listing entries, cannot be
represented by a normal filesystem directory.

## Current Harness

The runnable harness is:

```text
t/attack-fixtures.t
```

The first gallery slice covers:

```text
bad-payload
poisoned-sidecar
projection-poison
tmp-poison
bad-list-order
duplicate-event
bad-event-id
future-version
missing-parent
fake-player
fork-race
```

Each sample proves one of three outcomes:

- ignored shadow input leaves replay and `event_set_root` unchanged
- rejected filenames stay out of `event_set_root` and DAG replay
- hash-valid but invalid packets stay visible and produce stable diagnostics

## Minimum Attack List

### `bad-mtime`

Attack: event entries have misleading modification times, including times that
would change the apparent order of play.

Expected outcome: replay ignores mtime, sorts event basenames locally, and
returns the same canonical line as a clean listing. Verdict status should be
`ok` or `ignored`; `ignored_inputs` should include `mtime`.

### `bad-payload`

Attack: event files contain bytes that contradict the event filename or include
large, malformed, or tempting structured data.

Expected outcome: core replay never reads event file bytes. The filename wins.
Verdict status should be `ok` or `ignored`; `ignored_inputs` should include
`file-bytes`.

### `bad-list-order`

Attack: the store returns legal event names in an order that would produce a
different result if server order were trusted.

Expected outcome: replay normalizes and sorts basenames before parsing. Verdict
status should be `ok`; `ignored_inputs` should include `listing-order`.

### `duplicate-event`

Attack: the same event basename appears more than once in a raw listing or is
published again.

Expected outcome: duplicate identical names are idempotent and do not create
extra moves. Verdict status should be `ok`; the normalized event count should
include the name once.

### `missing-parent`

Attack: a move references a parent event id that is absent from the listing.

Expected outcome: the move remains visible but is not replayable. The verdict
should report `validation` with a missing-parent diagnostic, or preserve a valid
canonical prefix while counting the bad event as illegal according to the replay
contract in force.

### `fake-player`

Attack: a move uses a `by-<player>` field that does not match the game
descriptor player bound to the claimed color.

Expected outcome: replay rejects the event as wrong player. Verdict status
should be `validation`; the diagnostic should identify the submitted and
expected public player ids.

### `bad-signature`

Attack: `sidecar/<event_id>.sig` contains an invalid or contradictory
signature.

Expected outcome: `GOFTP/1` core replay ignores the signature. Verdict status
should be `ok` or `ignored`; `ignored_inputs` should include `sidecar-signature`.
If a future signed profile validates it, that profile must use a separate
verdict and must not change the `GOFTP/1` result.

### `poisoned-sidecar`

Attack: sidecar JSON, notes, or cached snapshots claim a different move, board,
player, or result than the filename listing proves.

Expected outcome: filename events win. Core replay ignores the poisoned sidecar
and produces the same board as if `sidecar/` were absent. Verdict status should
be `ok` or `ignored`; `ignored_inputs` should include `sidecar`.

### `unicode-name`

Attack: a descriptor or event basename contains non-ASCII characters.

Expected outcome: filename parsing rejects the name with a stable charset or
grammar diagnostic. Verdict status should be `validation`; the rejected name
must not enter event id maps, DAG construction, rules replay, or projections.

### `path-traversal-name`

Attack: a listing, fixture path, or publish candidate tries to use `/`, `..`,
backslash, NUL, or other path traversal syntax as a protocol name.

Expected outcome: path traversal is rejected before publish or excluded during
listing normalization. Verdict status should be `validation` or `storage`,
depending on the command boundary being tested. No file outside the fixture root
may be read or written.

### `huge-directory`

Attack: a game contains a very large number of irrelevant, malformed, duplicate,
temporary, sidecar, or projection entries.

Expected outcome: normalization keeps direct `events/` basenames as the only
replay candidates, reports stable diagnostics for direct malformed event names,
and ignores non-authoritative surfaces. Verdict status depends on whether any
direct malformed event is present, but memory and runtime should remain bounded
for the documented fixture size.

### `fork-race`

Attack: two legal children of the same parent are published close together,
creating a visible race.

Expected outcome: conservative replay stops at the fork and exits `3`. The
verdict should report `fork`, the parent id, and the competing child ids.
Ack-assisted recovery may be demonstrated separately, but default replay must
not silently choose a winner.

## Admission Criteria

Before adding an attack fixture, write down:

- the invariant being attacked
- the smallest listing that demonstrates it
- the expected CLI command and exit code
- the exact consensus inputs
- the ignored or rejected inputs
- the diagnostic or verdict fields that prove the behavior

Fixtures that cannot be explained this way belong in fuzz corpora or temporary
debug scratch space, not in the attack gallery.
