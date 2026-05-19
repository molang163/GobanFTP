# Source Art Motif Plan

GobanFTP source art is a surface layer. It may make the repository feel like a
protocol shrine, but it must not decide protocol truth.

The art rule is simple:

```text
the picture may guide the reader
the picture must not guide replay
```

Changing comments, borders, whitespace, glyph layout, colors, terminal frames,
Web assets, or projection wording must not change event ids, `event_set_root`,
DAG replay, rule legality, SGF output, or diagnostics.

## Motif Register

Each motif should belong to a protocol role. This keeps the project strange
without turning the repository into unrelated decoration.

```text
altar                 entry ritual, smoke wrapper, first visual contact
goban                 board truth revealed from names
hash seal             filename event id and immutable packet identity
DAG tree              hash chain, forks, and visible races
FTP gate              tmp -> publish -> visible listing
projection mirror     rebuilt shadows, never consensus
SGF scroll            normal Go record exported from strange storage
witness eye           cross-system proof and diagnostics
root monolith         event_set_root commitment
signature wax seal    explicit signed/auth profile surfaces
terminal observatory  mouse/keyboard TUI and readable status panels
Web observatory       static witness viewer and projection browser
arch gate             hidden A-shaped mountain gate, a developer easter egg
```

## Placement

Strong source art belongs in wrappers, fixtures, projections, and display
surfaces:

```text
oracle/goban.pl
examples/fixtures/**/projections/oracle/*.txt
future witness projection files
future TUI frames
future static Web export
```

Small header glyphs may appear in core modules only when they do not obscure the
code:

```text
lib/GobanFTP/EventID.pm       hash seal
lib/GobanFTP/DAG.pm           DAG tree
lib/GobanFTP/Replay.pm        canonical path
lib/GobanFTP/Store/FTP.pm     FTP gate
lib/GobanFTP/Projection.pm    projection mirror
lib/GobanFTP/SGF.pm           SGF scroll
```

Core modules must remain easier to maintain than to admire. If a picture makes a
function harder to audit, move the picture to `oracle/`, a fixture, or a
projection.

## Current Wrapper Boundary

`oracle/goban.pl` is currently the strong altar/goban source wrapper. Its banner
is the altar surface, its executable 9x9 array is the goban surface, and its
small source-only arch-gate is a threshold marker. The wrapper delegates smoke
truth to `GobanFTP::Oracle::Smoke`; it must not parse event names, compute event
ids, choose replay, decide rules, hash SGF, normalize storage, or turn visual
glyphs into witness fields.

This boundary records the current source-art role of the wrapper. It does not
make a release-status claim for source art, P14, or v1.0.

## Arch-Gate Easter Egg

The arch-gate easter egg is allowed as a small hidden motif, not as branding.

Use it as an A-shaped mountain gate inside the ritual surface:

```text
     /\
    /__\
   /_/\_\
```

Preferred locations:

```text
oracle/goban.pl border or margin
future projections/oracle/altar.txt
future TUI about/status panel
future Web witness footer
```

Avoid:

```text
README hero or project logo
package metadata
protocol names
event basenames
profile ids
release artifact names
anything that looks like official endorsement
```

The easter egg should read as a small source-art threshold: an arch-shaped gate
in the shrine. It should not copy the official Arch Linux logo or wordmark, and
it should not suggest that GobanFTP is affiliated with, endorsed by, or packaged
by the Arch Linux project.

The current placement is in `oracle/goban.pl` as a source-only
`arch-gate` threshold beside the smoke wrapper. `t/source-art.t` asserts that
the motif exists, stays ASCII, the wrapper contains no obvious Arch Linux,
official, or endorsement wording, and the motif is not emitted as witness truth.
The executable board glyphs still feed only
`GobanFTP::Oracle::Smoke`, and the smoke truth fields remain invariant under
alternate visual boards.

## ASCII And Runtime Rules

Source art should stay ASCII unless a later decision explicitly changes that.

Required checks for executable art:

```sh
perl -c oracle/goban.pl
perl oracle/goban.pl --smoke
prove -l t/source-art.t
```

The smoke command is allowed to display proof fields, but it must obtain them
through `GobanFTP::Witness`. It may print profile id, adapter id,
`event_set_root`, replay status, canonical tip, board hash, SGF hash, and
diagnostic count. It must not become a second implementation of filename
parsing, event id calculation, DAG replay, rules, projection hashing, or
storage normalization.

Additional source-art tests should assert behavior, not layout trivia. A changed
border must not fail a protocol test. A changed glyph must not alter any replay
fixture. Art can be beautiful; data stays boring.

Reusable surface renderers follow the same rule. Layout, CSS, terminal frames,
static HTML, and projection excerpts may reveal `GobanFTP::Witness` fields, but
they must not read storage, parse event names, recompute `event_set_root`, rerun
replay, or decide signed profile acceptance.

The `v1 witness --surface text|html|terminal` CLI path is such a surface. It
can emit plain text, static HTML, or a static terminal observatory for
inspection, while exit codes and diagnostics still come from the witness and
profile gates.

The minimal surface smoke freezes text, static HTML, and terminal observatory
output digests as reader-facing proof artifacts. It is not a hosted Web UI and
is separate from the local `play --tui` input surface; neither surface adds any
input to replay truth.

## v1.0 Surface Gate

Before v1.0 release, source-art work should demonstrate:

```text
one strong altar/goban source wrapper
one witness/root motif in generated projection or static viewer
one terminal or Web observatory surface
one hidden arch-gate easter egg, currently placed in `oracle/goban.pl`
tests proving source-art changes cannot alter protocol truth
```

The goal is not to fill every file with art. The goal is a coherent map: every
visual object tells the reader which part of the proof machine they are looking
at.
