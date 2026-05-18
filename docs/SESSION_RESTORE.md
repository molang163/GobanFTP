# Session Restore

One-line resume command:

```text
恢复 GobanFTP 工作：读取 docs/SESSION_RESTORE.md，按 Next Step 继续。
```

## Current State

Repository: `/run/media/molang/linux-dev/GobanFTP`

Current HEAD expectation:

```text
at or after:
- docs: add P14 release manifest tag plan
- docs: record P14 clean gate rerun
- docs: add P14 release gate dry run
- test: add showcase surface smoke gate
- feat: add terminal witness observatory
- test: freeze v1 witness surface smoke
- feat: add v1 witness surface output
- feat: add witness surface renderer
- test: route source-art smoke through witness
- test: add signed HMAC public trust poison fixture
```

Confirm the latest commit with `git log --oneline -5` when resuming.

## Recent Completed Work

```text
HEAD docs: add P14 release manifest tag plan
HEAD docs: record P14 clean gate rerun
HEAD docs: add P14 release gate dry run
HEAD test: add showcase surface smoke gate
HEAD feat: add terminal witness observatory
HEAD test: freeze v1 witness surface smoke
HEAD feat: add v1 witness surface output
HEAD feat: add witness surface renderer
HEAD test: route source-art smoke through witness
HEAD test: add signed HMAC public trust poison fixture
HEAD test: freeze signed HMAC lifecycle vectors
HEAD feat: enforce signed HMAC lifecycle status
HEAD feat: define signed HMAC trust bridge boundary
HEAD docs: clarify signed trust restore step
HEAD feat: add fixture trust report command
HEAD feat: add fixture keyid command
HEAD test: add WebDAV publish failure fixture
HEAD test: add git tree metadata poison fixture
HEAD test: add signed HMAC injected event fixture
HEAD docs: rewrite README as P14 showcase entrypoint
81e0fee test: add dns owner poison profile attack
c763103 test: add bad mtime attack fixture
cab85ad test: add v1 cross-substrate validation vectors
0bdbf42 test: add showcase demo smoke gate
ba17df8 test: add signed HMAC game descriptor mismatch fixture
60bc2c7 test: add signed HMAC payload mismatch fixture
fc7f6a2 test: add WebDAV href traversal attack fixture
04dd306 test: add WebDAV profile attack fixture
0faf00e feat: add WebDAV store backend
7884b6c feat: add ruleset seal witness
54d902c feat: add v1 compare CLI
958e47a feat: add v1 witness CLI
```

Key completed boundaries:

- P14a release-gate dry run is recorded in `docs/P14_RELEASE_GATE.md`. It ran
  the source-art, MakeMaker, perl-rules, shadow-rules, full prove, v1 witness,
  v1 compare, manifest, dist, disttest, and distcheck gates in a temporary
  worktree, then reran the same matrix from a clean detached worktree at commit
  `01e460044a64ca524fa6f80fa75b4cd0b6e5ed6e`. All executed gates passed after
  correcting manifest skip rules. This is a release-route checkpoint, not a
  v1.0 tag, P14 completion claim, hosted Web UI claim, or interactive TUI claim.
- Manifest skip rules now handle `.git` as either a directory or file and avoid
  excluding intentional attack specimens under `t/fixtures/`, including
  `t/fixtures/attacks/tmp-poison/tmp/pending.part`.
- P14 release manifest and tag planning is recorded in
  `docs/P14_RELEASE_MANIFEST_AND_TAG_PLAN.md`. The recommended next publishable
  identity is tag `v0.2`, Perl version `0.002`, and `Changes` heading
  `0.002  YYYY-MM-DD`, explicitly as a pre-v1.0/P14 checkpoint. The reserved
  v1.0 identity is tag `v1.0`, Perl version `1.000`, and `Changes` heading
  `1.000  YYYY-MM-DD`, only after the final P14 matrix and claim audit pass. Do
  not tag while `Changes`, `$VERSION`, tarball name, and artifact hash disagree.
- P12a fixture public key identity is implemented through
  `gobanftp v1 keyid --fixture`. It parses public fixture key records, derives
  documented `GOFTP-KEY/1` `k1.` ids, rejects malformed/private-looking records
  with `parse_public_key`, and keeps public key metadata separate from HMAC
  secrets, signatures, trust, and unsigned replay truth.
- P12b fixture trust reporting is implemented through
  `gobanftp v1 trust-report --fixture`. It runs the normal unsigned witness
  first, summarizes optional public `keys/*.pub` and `GOFTP-TRUST/1` rows, emits
  trusted/rotated/revoked/expired lifecycle fields, rejects malformed trust/key
  fixtures without leaking fixture material, and keeps all trust state advisory.
- P12c-0 signed-HMAC/trust bridge boundary is defined:
  `signed-hmac-goftp1` keeps explicit HMAC
  selectors separate from public `GOFTP-KEY/1` `k1.` identities, advisory
  `GOFTP-TRUST/1` rows do not authorize HMAC signatures, and lifecycle status
  has deterministic verify/publish meaning without wall-clock replay inputs.
- P12c-1 explicit signed-HMAC lifecycle enforcement is implemented:
  `v1 witness` accepts `--trusted-hmac-status <id=status>` for selectors already
  supplied by `--trusted-hmac-key`; omitted status remains `trusted`; `rotated`
  verifies old material; `revoked` and `expired` reject inside the signed
  profile gate with `untrusted_signature` lifecycle reasons. Unsigned profiles
  ignore the lifecycle input.
- P12d signed-HMAC lifecycle golden vectors are frozen:
  `t/fixtures/vectors/v1-signed-hmac-witness.jsonl` now records lifecycle
  statuses, accepted/rejected sets, and `rejected_diagnostics` for trusted,
  rotated, revoked, and expired HMAC selectors. Revoked and expired vectors
  freeze `key.revoked` and `key.expired` reasons.
- P12e signed-HMAC public trust bridge poison is implemented:
  `t/fixtures/v1/signed-hmac/public-trust-bridge-poison` carries public
  `GOFTP-TRUST/1` `k1.` rows marked trusted, revoked, and expired, including
  metadata that points at HMAC selectors. The test proves those rows cannot
  authorize `k1.` HMAC selectors, cannot revoke `fixture-key-1`, and do not
  change unsigned `local-goftp1` replay.
- P13a source-art witness smoke is implemented: `oracle/goban.pl --smoke`
  still remains an executable source-art wrapper, but the smoke module now gets
  protocol proof fields from `GobanFTP::Witness`. The test proves visual board
  glyphs and Inline::C availability do not change `event_set_root`,
  replay status, canonical tip, board hash, SGF hash, or diagnostic count.
- P13b witness/projection-only surface rendering is implemented:
  `GobanFTP::Surface::WitnessView` formats supplied witness fields and
  projection text as inspection output. It does not read storage, parse event
  names, normalize listings, recompute `event_set_root`, rerun replay/rules, or
  decide signed profile acceptance.
- P13c `v1 witness --surface text|html` is implemented as a read-only CLI
  inspection surface. It uses the existing `GobanFTP::Witness` result plus
  opt-in projection text already rendered inside `Witness`, then routes that
  data through `GobanFTP::Surface::WitnessView`. The CLI does not read
  `projections/`, rerun replay, recompute roots, or decide profile acceptance.
- P13d minimal witness surface smoke is frozen: the minimal `local-goftp1`
  `v1 witness --surface text|html` outputs now have digest and byte-length
  coverage, visible `event_set_root`, and canonical projection-section checks.
  This is a static inspection-surface gate, not a full Web or TUI release.
- P13e terminal witness observatory is implemented:
  `v1 witness --surface terminal` renders a deterministic ASCII/stdout status
  panel from the existing `GobanFTP::Witness` result and opt-in projection
  text. It freezes the minimal terminal digest, preserves fork and validation
  exit behavior, redacts signed-HMAC secrets, and remains a static terminal
  inspection surface rather than an interactive TUI.
- P13f showcase surface smoke is implemented:
  `t/showcase-demo.t` now runs the shrine replay, race fork, source-art oracle,
  default unsigned `local-goftp1` witness, and the text/static HTML/static
  terminal witness surfaces. The surface checks prove the public demonstration
  path exposes the same `event_set_root` without adding hosted Web UI,
  interactive TUI, or another witness assembler.
- WebDAV publish failure now has a fixture and CLI parity gate proving
  existing-final idempotence, delayed `MOVE` visibility, hard `HTTP 423 Locked`
  failure, bounded retries, zero-byte temporary resources, tmp debris exclusion,
  listing-first confirmation, and bearer-token redaction.
- `git-tree-goftp1` now has a profile attack fixture proving commit metadata,
  refs, tags, remotes, mode, object id, object type, object size, `tmp/`,
  sidecar, projection, recursive path, wrong-game path, duplicate entry, and
  checkout-style path surfaces do not change the accepted witness.
- `signed-hmac-goftp1` now has an injected-event fixture: an event basename with
  a valid filename event id reaches the signed profile gate, is rejected for
  `missing_signature`, and the accepted signed chain keeps the same root,
  replay, board, and SGF as the valid baseline.
- README is now a release-shaped showcase entrypoint: it opens with the hard
  GOFTP/1 contract, three-minute proof path, shrine/race demonstration, current
  implemented surfaces, proof gates, and the `v1.0/P14` release-freeze shape
  without claiming P14 is already tagged.
- `signed-hmac-goftp1` now has golden-vector fixtures for valid,
  injected-event, missing, wrong, payload-mismatched, game-descriptor-mismatched,
  untrusted, and malformed attestations.
- CLI witness covers signed-HMAC failure status, stable signature diagnostics,
  and HMAC secret redaction.
- WebDAV profile attack fixtures cover metadata poison and href traversal.
- `bad-mtime` is now a core attack fixture. The harness applies real event-file
  mtimes with `utime`, confirms they were applied, runs CLI verification, and
  confirms the mtimes remain unchanged.
- A showcase smoke gate now locks the public clean shrine, race shrine,
  source-art oracle smoke, and unsigned `local-goftp1` v1 witness path.
- v1 cross-substrate witness vectors now cover minimal, fork, fork-with-ack,
  bad-event-id, future-version, missing-parent, and wrong-player across local,
  FTP, Git-like, DNS-like, and WebDAV-like profiles.
- Unsigned v1 witness golden vectors now freeze profile consensus version,
  adapter id, raw and normalized counts, normalized events, accepted and
  rejected counts, and diagnostic count.
- The DNS profile adapter requires the TXT owner to belong to the current game
  descriptor, and `dns-owner-poison` proves wrong-owner or ownerless TXT records
  cannot smuggle events into the witness.
- Ruleset seal, v1 witness CLI, and v1 compare CLI are already implemented.

## Last Verified

After P14a release-gate dry-run integration, these passed or were recorded:

```text
P14 dry-run temporary worktree:
perl -c oracle/goban.pl
perl oracle/goban.pl --smoke
perl Makefile.PL
GOBANFTP_RULES_DISABLE_C=1 GOBANFTP_RULES_ENGINE=perl make test
GOBANFTP_RULES_ENGINE=shadow make test
prove -lr t
prove -lr t/v1-cross-substrate.t
prove -lr t/v1-attack-fixtures.t
prove -lr t/v1-golden-vectors.t
prove -lr t/v1-signed-hmac.t
prove -lr t/v1-signed-hmac-golden-vectors.t
prove -lr t/profile-registry.t t/profile-adapter.t t/witness-api.t
prove -lr t/diagnostics-contract.t
prove -lr t/rules-flow.t t/rules-superko.t
script/gobanftp v1 witness --profile local-goftp1 --fixture t/fixtures/v1/cross-substrate/minimal
script/gobanftp v1 compare-roots --fixture t/fixtures/v1/cross-substrate/minimal
script/gobanftp v1 compare-replay --fixture t/fixtures/v1/cross-substrate/minimal
make manifest
make dist
GOBANFTP_RULES_DISABLE_C=1 GOBANFTP_RULES_ENGINE=perl make disttest
make distcheck

Post-correction clean worktree at 01e460044a64ca524fa6f80fa75b4cd0b6e5ed6e:
same P14 matrix passed again
make manifest left MANIFEST and MANIFEST.SKIP unchanged
tarball included docs/P14_RELEASE_GATE.md
tarball included t/fixtures/attacks/tmp-poison/tmp/pending.part
GobanFTP-0.001.tar.gz sha256=4c26f252b4d970a801213c61d351621b212077eff8bfd29cdd66a90bdbe8579f size=279K

Main worktree after documenting the dry run:
perl -Ilib -c t/showcase-demo.t
prove -lr t/showcase-demo.t
perl -Ilib -c oracle/goban.pl
perl -Ilib oracle/goban.pl --smoke
prove -lr t/showcase-demo.t t/source-art.t t/surface-witness-view.t t/v1-cli-witness-surface.t t/v1-cli-witness-surface-golden.t
prove -lr t/witness-api.t t/v1-cli-witness.t
perl -Ilib -c lib/GobanFTP/Surface/WitnessView.pm
perl -Ilib -c lib/GobanFTP/CLI.pm
prove -lr t/surface-witness-view.t t/v1-cli-witness-surface.t t/v1-cli-witness-surface-golden.t
perl -Ilib -c t/v1-cli-witness-surface-golden.t
prove -lr t/v1-cli-witness-surface-golden.t t/v1-cli-witness-surface.t
perl -Ilib -c lib/GobanFTP/Witness.pm
perl -Ilib -c lib/GobanFTP/CLI.pm
prove -lr t/witness-api.t t/v1-cli-witness-surface.t t/v1-cli-witness.t t/surface-witness-view.t
perl -Ilib -c lib/GobanFTP/Surface/WitnessView.pm
prove -lr t/surface-witness-view.t
prove -lr t/surface-witness-view.t t/source-art.t t/witness-api.t t/v1-cli-witness.t t/showcase-demo.t
perl -Ilib -c lib/GobanFTP/Oracle/Smoke.pm
perl -Ilib oracle/goban.pl --smoke
prove -lr t/source-art.t
prove -lr t/source-art.t t/witness-api.t t/v1-cli-witness.t t/showcase-demo.t
perl -Ilib -c lib/GobanFTP/Auth/TrustReport.pm
perl -Ilib -c lib/GobanFTP/Profile/SignedHMAC.pm
perl -Ilib -c lib/GobanFTP/Witness.pm
perl -Ilib -c lib/GobanFTP/CLI.pm
perl -Ilib -c lib/GobanFTP/Diagnostics.pm
prove -lr t/profile-signed-hmac.t t/v1-cli-witness.t t/v1-signed-hmac.t t/v1-signed-hmac-golden-vectors.t t/auth-trust-report.t t/cli-auth-trust-report.t t/diagnostics-contract.t
prove -lr t/v1-signed-hmac-golden-vectors.t t/v1-signed-hmac.t t/v1-cli-witness.t t/profile-signed-hmac.t
prove -lr t/v1-signed-hmac.t t/v1-signed-hmac-golden-vectors.t t/profile-signed-hmac.t t/v1-cli-witness.t t/auth-trust-report.t t/cli-auth-trust-report.t
prove -lr t/auth-keyid.t t/cli-auth-keyid.t t/diagnostics-contract.t t/dependency-sync.t t/v1-cli-witness.t t/v1-signed-hmac.t
prove -lr t/auth-trust-report.t t/cli-auth-trust-report.t t/diagnostics-contract.t
prove -lr t/auth-keyid.t t/auth-trust-report.t t/cli-auth-keyid.t t/cli-auth-trust-report.t t/diagnostics-contract.t t/v1-cli-witness.t
prove -lr t/v1-profile-publish-fixtures.t t/webdav-cli-parity.t t/store-webdav-mock.t
prove -lr t/profile-adapter.t t/v1-profile-attack-fixtures.t t/v1-cross-substrate.t t/v1-golden-vectors.t
git diff --check
prove -lr t
```

Full test result:

```text
Files=70, Tests=943, all successful.
Live FTP tests were skipped unless GOBANFTP_FTP_TEST=1 is set.
```

## Important Invariants

- Descriptor directory basename and direct `events/` basenames are authoritative.
- Event ids come from canonical filename context, not file bytes.
- `mtime`, file bytes, listing order, entry type, size, sidecar, projections,
  and tmp entries are not replay inputs.
- `event_set_root` is a witness commitment over accepted direct event basenames.
- Signed/auth behavior is explicit profile behavior and must not change unsigned
  `GOFTP/1`.
- Source art, TUI, Web, Inline::C, and asm-like surfaces cannot own truth.

## Next Step

Immediate next implementation:

```text
after P14 release manifest and tag planning:
- use `docs/P14_RELEASE_MANIFEST_AND_TAG_PLAN.md` as the release checklist
- likely next slice is the `v0.2/0.002` release identity commit: update
  `lib/GobanFTP.pm`, `Changes`, artifact record, and final gate result
- do not tag v1.0 until the final clean-checkout P14 matrix passes
- do not let display, source art, Web assets, terminal formatting, or interactive
  input feed replay or event-set roots
- keep unsigned `GOFTP/1` and `local-goftp1` replay unchanged
- keep every change behavior-tested and update Changes plus this restore file
```

Likely files:

```text
docs/P14_RELEASE_GATE.md
docs/P14_RELEASE_MANIFEST_AND_TAG_PLAN.md
docs/V1_DOD.md
docs/ROADMAP.md
README.md
Changes
MANIFEST
MANIFEST.SKIP
lib/GobanFTP.pm
lib/GobanFTP/Auth/TrustReport.pm
lib/GobanFTP/Profile/SignedHMAC.pm
lib/GobanFTP/Witness.pm
lib/GobanFTP/CLI.pm
lib/GobanFTP/Oracle/Smoke.pm
lib/GobanFTP/Surface/WitnessView.pm
oracle/goban.pl
lib/GobanFTP/Diagnostics.pm
t/fixtures/auth/
t/fixtures/v1/signed-hmac/
t/fixtures/vectors/v1-signed-hmac-witness.jsonl
t/v1-signed-hmac.t
t/v1-signed-hmac-golden-vectors.t
t/v1-cli-witness.t
t/v1-cli-witness-surface-golden.t
t/v1-cli-witness-surface.t
t/source-art.t
t/surface-witness-view.t
t/cli-auth-trust-report.t
t/diagnostics-contract.t
docs/PROFILES.md
docs/CLI.md
docs/DIAGNOSTICS.md
docs/SOURCE_ART.md
docs/ARCHITECTURE.md
README.md
docs/SHOWCASE.md
t/showcase-demo.t
Changes
docs/SESSION_RESTORE.md
```

## Restore Procedure

When resuming:

1. Read `AGENTS.md` if present; otherwise continue with this file and the
   maintainer guide supplied in the session context.
2. Read this file.
3. Run `git status --short`.
4. Confirm HEAD includes `test: add showcase surface smoke gate`.
5. If the user asks to continue, review the next step first, then choose one
   small executable step.
