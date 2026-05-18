# Build And Development

GobanFTP is a Perl project with an optional Inline::C rules-mechanics backend.

## Requirements

Minimum local target:

```text
Perl 5.34+
make
```

Declared dependencies are kept in sync across `Makefile.PL`, `cpanfile`, and
this file. The block below is intentionally machine-readable for
`t/dependency-sync.t`.

<!-- gobanftp-deps:start -->
```text
runtime: Digest::SHA Net::FTP
test: File::Temp Test::More
optional: Inline Inline::C
```
<!-- gobanftp-deps:end -->

Inline and Inline::C are optional for ordinary test and replay runs. Install
them, plus a usable C compiler, only when exercising the C board-mechanics
backend.

## Local Workflow

Run the normal Perl build and test flow with:

```sh
perl Makefile.PL
make
make test
```

FTP integration tests should be disabled by default. Enable them explicitly:

```sh
GOBANFTP_FTP_TEST=1 \
GOBANFTP_FTP_HOST=ftp.example.test \
GOBANFTP_FTP_USER=gobanftp \
GOBANFTP_FTP_PASSWORD=<test-password> \
GOBANFTP_FTP_ROOT=/goftp-test \
make test
```

Optional live FTP knobs are `GOBANFTP_FTP_PORT`, `GOBANFTP_FTP_TIMEOUT`,
`GOBANFTP_FTP_PASSIVE`, `GOBANFTP_FTP_DEBUG`, `GOBANFTP_FTP_CLASS`, and
`GOBANFTP_FTP_PUBLISH_MODE`. Use an isolated, disposable `GOBANFTP_FTP_ROOT` for
live FTP tests. The test suite creates game directories and temporary publish
entries under that root; do not point it at a shared game tree or any FTP
directory with data that must be preserved.

For a disposable localhost live FTP smoke, install `pyftpdlib` separately and
run:

```sh
python3 -m pip install pyftpdlib
script/live-ftp-smoke
```

`pyftpdlib` is intentionally not a default Perl runtime or test dependency. The
helper starts a temporary `pyftpdlib` server on a random localhost port with a
one-time FTP root, user, and password, then runs:

```sh
prove -l t/store-ftp.t t/ftp-live-flow.t
```

It sets `GOBANFTP_FTP_TEST=1` and the matching FTP environment for the child
test process, shuts the server down afterward, and removes the temporary
directory. If `pyftpdlib` is missing, the helper exits before running tests and
prints an install hint.

## Inline::C Notes

Perl is the authoritative default rule engine. The C boundary is lazy-loaded and
handles only compact board mechanics: board bytes, board size, move index, stone
byte, and returned capture indices. Perl still owns filename parsing, event ids,
state hash framing, superko, DAG replay, SGF, CLI, and projections.

The rules engine can be selected with:

```sh
GOBANFTP_RULES_ENGINE=perl    # default, never loads Inline::C
GOBANFTP_RULES_ENGINE=auto    # use C if available, otherwise Perl
GOBANFTP_RULES_ENGINE=c       # require C, fail explicitly if unavailable
GOBANFTP_RULES_ENGINE=shadow  # run Perl authoritatively, compare C if available
```

For tests or diagnostics, force C unavailable with:

```sh
GOBANFTP_RULES_DISABLE_C=1
```

Expected no-C verification:

```sh
GOBANFTP_RULES_DISABLE_C=1 GOBANFTP_RULES_ENGINE=auto prove -l t
GOBANFTP_RULES_ENGINE=perl prove -l t/rules-play.t t/rules-flow.t t/rules-superko.t t/replay.t
```

When Inline::C is available, run deterministic and seeded random C equivalence:

```sh
prove -l t/rules-c-equivalence.t t/rules-c-random-equivalence.t

GOBANFTP_RULES_RANDOM_SEED=local-check \
GOBANFTP_RULES_RANDOM_TRIALS=1000 \
prove -l t/rules-c-random-equivalence.t

GOBANFTP_RULES_RANDOM_STRESS=1 prove -l t/rules-c-random-equivalence.t
```

Inline::C creates local build caches. Generated files must not be committed.

Expected generated paths include:

```text
_Inline/
blib/
MYMETA.json
MYMETA.yml
pm_to_blib
```

Release hygiene is enforced by `MANIFEST.SKIP`. Before making a distribution,
regenerate `MANIFEST` from the working tree so local build products stay out of
the tarball:

```sh
make manifest
make dist
make disttest
```

`MANIFEST.SKIP` must continue to exclude Inline::C caches, `blib/`,
`MYMETA.json`, `MYMETA.yml`, `pm_to_blib`, and `*.part`, `*.tmp`, and `*.bak`
scratch files.

## Display And Distribution Hygiene

Generated distribution artifacts are local outputs, not the default project
entrance. A stale `GobanFTP-*.tar.gz`, unpacked `GobanFTP-*` directory, `blib/`,
`_Inline/`, `Makefile`, `MYMETA.*`, or `pm_to_blib` may describe an older
checkpoint than the working tree.

When the project is not being published, prefer to keep those generated outputs
outside the presentation root. Before a demo or public release, either move
stale outputs aside or regenerate them from the current working tree and rerun
the release gates:

```sh
make manifest
make dist
make disttest
make distcheck
```

If a tarball remains in the root after a local release check, document that it is
a build artifact unless it is the artifact being intentionally distributed.

## v0.1 Release Boundary

For v0.1, release checks are hardening and showcase checks, not protocol
expansion. The expected release surface is the playable protocol artwork:
listing-first local and FTP replay, create/publish/play/watch flows, source-art
oracle smoke, SGF/board/graveyard/oracle projections, and the browsable fixture.

`projections/oracle/listing.txt`, when present, is a generated projection like
the other oracle outputs. It may be deleted and rebuilt without changing
`GOFTP/1` replay.

Do not block v0.1 on scoring, final result events, or signed consensus. Those
belong in a future phase, protocol version, or explicit profile.

`oracle/goban.pl` must pass:

```sh
perl -c oracle/goban.pl
```

The source-art wrapper should call modules from `lib/`; it should not contain
the whole rule engine.
