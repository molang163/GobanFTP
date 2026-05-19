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
- feat: add hmac publish token semantics
- feat: add signed hmac substrate overlay
- feat: add signed hmac operation layer
- release: enter v1.0 final candidate identity
- docs: record P14 claim-audit matrix
- test: add P14 claim audit gate
- docs: record current P14 development matrix
- test: add source art arch gate
- test: add bad signature vector and dist hygiene gate
- docs: record P14 development freeze matrix
- chore: normalize manifest order
- docs: refresh P14 claim audit gates
- test: add FTP public poison vector
- test: freeze signed public trust vectors
- test: add core poison public vectors
- chore: enter v1.0 development
- release: prepare v0.2 identity
- docs: clarify active P14 release plan
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

Current state after the v1.0 final-candidate identity switch:

- The source tree is now a `v1.0` / package `1.000` final candidate:
  `lib/GobanFTP.pm` declares `1.000`, `Changes` starts with
  `1.000  2026-05-19`, and no `v1.0` tag or final artifact is claimed yet.
- A fresh clean-checkout matrix passed at commit
  `1f5f646921f675c93e25819cb3cf3652f5d6bebe`.
- The development tarball was `GobanFTP-1.000_001.tar.gz` with
  `sha256=45347dff8f9ac649ec194ab729172df25fa675556fadcb83f0964dc8d18c7e00`,
  `size=328408`, `tar_entries=784`, and
  `MANIFEST_sha256=e8efd1d7c7e5ea51cd35575875606b5d4559a6e2f7c4884828ea4688da599ba5`.
- That matrix is still `1.000_001` development-freeze evidence only: no v1.0
  tag, P14 completion, publication event, or final stable v1.0 artifact is
  claimed.
- `t/p14-claim-audit.t` now guards release-facing text against accidental
  final-release over-claims and is included in the latest full development
  matrix. Passing it is still not a P14/v1.0 completion claim.
- `oracle/goban.pl` now carries a comment-only ASCII `arch-gate` source-art
  easter egg beside the smoke wrapper.
- `t/source-art.t` now asserts the arch-gate marker exists, stays ASCII, the
  wrapper contains no obvious Arch Linux, official, or endorsement wording, and
  the motif is not emitted as witness truth.
- `docs/SOURCE_ART.md`, `docs/ROADMAP.md`, and `Changes` record the arch-gate as
  non-consensus source/display art.
- P17 adds local `gobanftp play --tui` as a separate terminal input/display
  surface. It uses keyboard and SGR mouse input, publishes through the existing
  play path, exits after one successful publish, and does not own replay truth.
- The P17b worktree adds readable TUI status lines, malformed escape recovery,
  pty smoke coverage for `q`, keyboard publish, and mouse publish, and
  release-text updates separating local TUI input from hosted Web UI and
  cross-terminal compatibility completion claims.
- P18 adds verifier-local signed-HMAC operation support:
  `gobanftp v1 keygen --profile signed-hmac-goftp1 --out ...`,
  `gobanftp v1 attest --profile signed-hmac-goftp1 --key ... --out ...`, and
  `gobanftp v1 witness --trusted-hmac-key-file ...`. This creates private
  `GOFTP-HMAC-KEY/1` key files, writes public attestation JSONL, and verifies
  through the existing signed profile gate without changing unsigned replay.
- P18 is not production key lifecycle completion and is not publish auth
  completion. It does not define account identity binding, public-key signing
  suites, revocation publication, key loss recovery, automatic sidecar
  discovery, or publish-time authorization.
- P19 adds the read-only signed-HMAC substrate overlay:
  `gobanftp v1 witness --profile signed-hmac-goftp1 --substrate-profile ...`
  reads local, FTP, Git-tree, DNS-record, or WebDAV fixture listings through
  their base normalizers, then applies explicit verifier-local HMAC
  attestations/trust input. The overlay proves signed-accepted root/replay
  invariance across admitted read substrates and still does not define
  production identity lifecycle, automatic sidecar discovery, or publish auth.
- P20a adds verifier-local publish-purpose HMAC tokens:
  `gobanftp v1 publish-token` writes one public `GOFTP-HMAC-PUBLISH/1` token
  for one proposed event basename, and `gobanftp v1 publish-auth` verifies it
  with explicit verifier-local HMAC trust input. Only `trusted` selectors may
  authorize new publish material; `rotated`, `revoked`, and `expired` fail
  closed. This is fixture publish-auth semantics, not real writer access,
  transport authentication, production key lifecycle completion, automatic
  sidecar discovery, or publish-auth completion.
- Previous HEAD `test: add bad signature vector and dist hygiene gate` added
  the `bad-signature` public poison vector and dist manifest hygiene gate.

## Recent Completed Work

```text
HEAD feat: add hmac publish token semantics
HEAD feat: add signed hmac substrate overlay
HEAD release: enter v1.0 final candidate identity
HEAD feat: add signed hmac operation layer
HEAD docs: record P14 claim-audit matrix
HEAD test: add P14 claim audit gate
HEAD docs: record current P14 development matrix
HEAD test: add source art arch gate
HEAD test: add bad signature vector and dist hygiene gate
HEAD docs: record P14 development freeze matrix
HEAD chore: normalize manifest order
HEAD docs: refresh P14 claim audit gates
HEAD test: add FTP public poison vector
HEAD test: freeze signed public trust vectors
HEAD test: add core poison public vectors
HEAD chore: enter v1.0 development
HEAD release: prepare v0.2 identity
HEAD docs: clarify active P14 release plan
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
  `docs/P14_RELEASE_MANIFEST_AND_TAG_PLAN.md` as the active v1.0/P14
  development release plan. The old local v0.2 candidate used tag `v0.2`, Perl
  version `0.002`, and `Changes` heading `0.002  YYYY-MM-DD`, explicitly as a
  pre-v1.0/P14 checkpoint. That candidate is superseded and is no longer the
  active release path. The plan separates the `1.000_001` development freeze
  matrix and development tarball from the reserved final `v1.0` / package
  `1.000` identity.
- The v0.2 release identity was prepared locally and then skipped before public
  release. Do not reuse that identity as the current development state.
- The public v0.2 release path was skipped. Do not push or publish a `v0.2` tag
  or `GobanFTP-0.002.tar.gz`. The active final-candidate identity is now
  `1.000  2026-05-19`, `lib/GobanFTP.pm` declares `1.000`, and README names
  the current line as `v1.0/P14` final candidate. If a local `v0.2` tag exists
  after restore, delete it before continuing.
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
  supplied by `--trusted-hmac-key` or `--trusted-hmac-key-file`; omitted status
  remains `trusted`; `rotated` verifies old material; `revoked` and `expired`
  reject inside the signed profile gate with `untrusted_signature` lifecycle
  reasons. Unsigned profiles ignore the lifecycle input.
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
- P12e public-trust bridge golden vectors are frozen:
  `t/fixtures/vectors/v1-signed-hmac-witness.jsonl` now binds the public key
  and trust TSV fixture text for `public-trust-bridge-poison`, with one row
  proving the trusted public `k1.` selector is rejected before HMAC verification
  and one row proving public revoked/expired `k1.` rows cannot revoke the
  explicit `fixture-key-1` HMAC selector. The fixture HMAC secret remains absent
  from public vector data.
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
  This is a static inspection-surface gate, not a hosted Web UI or local TUI
  input release.
- P13e terminal witness observatory is implemented:
  `v1 witness --surface terminal` renders a deterministic ASCII/stdout status
  panel from the existing `GobanFTP::Witness` result and opt-in projection
  text. It freezes the minimal terminal digest, preserves fork and validation
  exit behavior, redacts signed-HMAC secrets, and remains a static terminal
  inspection surface rather than the local `play --tui` input surface.
- P13f showcase surface smoke is implemented:
  `t/showcase-demo.t` now runs the shrine replay, race fork, source-art oracle,
  default unsigned `local-goftp1` witness, and the text/static HTML/static
  terminal witness surfaces. The surface checks prove the public demonstration
  path exposes the same `event_set_root` without adding hosted Web UI, local
  TUI input, or another witness assembler.
- WebDAV publish failure now has a fixture and CLI parity gate proving
  existing-final idempotence, delayed `MOVE` visibility, hard `HTTP 423 Locked`
  failure, bounded retries, zero-byte temporary resources, tmp debris exclusion,
  listing-first confirmation, and bearer-token redaction.
- `git-tree-goftp1` now has a profile attack fixture proving commit metadata,
  refs, tags, remotes, mode, object id, object type, object size, `tmp/`,
  sidecar, projection, recursive path, wrong-game path, duplicate entry, and
  checkout-style path surfaces do not change the accepted witness.
- `git-tree-path-metadata-poison` is now promoted into
  `t/fixtures/vectors/v1-non-consensus-poison.jsonl` as a public poison vector,
  binding the real fixture input names to unchanged event-set preimage, root,
  replay, board, projection text, and SGF truth without claiming Git publish,
  remote fetch, or provider APIs.
- Core/local `bad-mtime`, `bad-payload`, `bad-list-order`,
  `poisoned-sidecar`, `projection-poison`, and `tmp-poison` are now promoted
  into `t/fixtures/vectors/v1-non-consensus-poison.jsonl` as public
  baseline/poison vectors. Ignored files are bound with
  `poisoned.evidence_artifacts`, including exact fixture text, and listing
  order poison is bound with `poisoned_order`.
- `git-tree-goftp1` now has read-only runtime store admission through
  `GOBANFTP_STORE=git-tree`: CLI verify/replay/SGF read direct
  `<treeish>:<game>/events` children from a real Git tree and prove the same
  event-set root and canonical replay while blob bytes, commit metadata,
  sidecars, projections, tmp entries, and Git publish remain outside consensus.
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
- Unsigned and signed-HMAC witness golden vectors now carry self-contained
  `input_names`, `rejected_diagnostics`, `replay_diagnostics`, and rendered
  `projection_text` for board, verdict, listing transcript, main SGF, and
  variations SGF. Signed-HMAC vectors still read public attestation fixtures and
  explicitly keep the HMAC secret out of public vector data.
- `t/fixtures/vectors/v1-replay-invariants.jsonl` freezes compact replay
  invariants outside the cross-substrate listing matrix: illegal sibling
  isolation, invalid root preflight diagnostics, and outsider ACK rejection
  without changing the canonical move line. It now also covers capture, suicide
  rejection, bounds parse rejection, single pass, two-pass terminal play, resign
  terminal play, simple-ko superko rejection, ack-assisted fork choice,
  malformed basenames, parent-is-ACK rejection, dangling ACK targets, and ACK
  targets that are themselves ACKs.
- Event-id collision is not claimed as an ordinary public replay basename
  vector. `Replay` verifies names against the game descriptor before DAG
  construction, so fake same-id names are rejected as event-id mismatches unless
  a real hash collision exists. A future collision proof should be a DAG-level
  vector or a deliberately scoped synthetic fixture.
- `dns-record-goftp1` is documented as read-only runtime admission over local or
  otherwise declared record files via `GOBANFTP_STORE=dns-record` and
  `GOBANFTP_DNS_RECORD_FILE`. The DNS profile adapter requires the TXT owner to
  belong to the current game descriptor, and `dns-owner-poison` proves
  wrong-owner or ownerless TXT records cannot smuggle events into the witness.
  The boundary does not include live DNS, AXFR, DNSSEC trust, provider APIs,
  dynamic update, record publishing, or consensus use of TTL, order, cache age,
  DNSSEC status, or provider metadata.
- `dns-owner-poison` is now promoted into
  `t/fixtures/vectors/v1-non-consensus-poison.jsonl` as
  `dns-owner-poison-public-vector`, binding the real fixture input names to
  unchanged event-set preimage, root, replay, board, projection text, and SGF
  truth.
- `webdav-href-traversal` is now promoted into
  `t/fixtures/vectors/v1-non-consensus-poison.jsonl` as
  `webdav-href-traversal-public-vector`, binding raw and percent-encoded
  traversal href fixture input names to unchanged one-event event-set preimage,
  root, replay, board, projection text, and SGF truth. This is WebDAV
  read/listing href-normalization evidence only.
- `ftp-listing-shadow-poison` is now promoted into
  `t/fixtures/vectors/v1-non-consensus-poison.jsonl` as
  `ftp-listing-shadow-poison-public-vector`, binding the existing hostile
  `ftp-goftp1` cross-substrate listing to unchanged three-event event-set
  preimage, root, replay, board, projection text, and SGF truth. This proves
  FTP-shaped sidecar, tmp, projection, recursive descendant, and list-order rows
  stay outside witness truth without claiming live FTP, `RETR`, `SIZE`, `MDTM`,
  auth, integrity, or publish behavior.
- The P14a release-gate dry run predates the later Git-tree and DNS-record
  runtime read admissions. Treat it as historical evidence, not as the final
  release matrix for the current HEAD. The next release-route proof slice must
  refresh the claim audit for the admitted read boundaries before any final P14
  artifact or tag decision.
- The P14 clean-gate plan now explicitly names `t/v1-profile-attack-fixtures.t`
  and `t/v1-profile-publish-fixtures.t`, tarball checks for
  `t/fixtures/vectors/v1-non-consensus-poison.jsonl`, the minimal FTP listing
  fixture, and the `ftp-listing-shadow-poison-public-vector` row, and expands
  final claim-audit scanning to README, Changes, ROADMAP, V1_DOD, P14 gate and
  manifest-plan docs, this restore file, tag text, and the external artifact
  record.
- `MANIFEST` ordering was normalized after the first clean-checkout matrix run
  found that `make manifest` would otherwise leave a tracked diff.
- The latest clean-checkout `1.000_001` development freeze matrix passed at
  `1f5f646921f675c93e25819cb3cf3652f5d6bebe` and generated
  `GobanFTP-1.000_001.tar.gz`
  (`sha256=45347dff8f9ac649ec194ab729172df25fa675556fadcb83f0964dc8d18c7e00`,
  `size=328408`, `tar_entries=784`,
  `MANIFEST_sha256=e8efd1d7c7e5ea51cd35575875606b5d4559a6e2f7c4884828ea4688da599ba5`).
  It includes the source-art arch-gate, bad-signature public poison vector, and
  P14 claim-audit gate. This is development-freeze evidence only: no v1.0 tag,
  P14 completion, publication event, or final stable v1.0 artifact is claimed.
  This restore-file record is post-run documentation, not the tested tarball
  source unless the matrix is rerun from this record commit.
- `t/p14-claim-audit.t` is now an executable release-text boundary gate. It
  scans README, Changes, roadmap, V1 DoD, P14 gate, P14 manifest/tag plan, and
  source-checkout restore memory for unguarded final-release claims while
  allowing explicit forbidden-claim registries and negative/deferred contexts.
  It is included in the latest clean-checkout development matrix.
- Ruleset seal, v1 witness CLI, and v1 compare CLI are already implemented.

## Last Verified

Latest local verification after P20a HMAC publish token semantics:

```text
perl -Ilib -c lib/GobanFTP/Auth/PublishToken.pm
perl -Ilib -c lib/GobanFTP/CLI.pm
prove -lr t/auth-publish-token.t t/cli-auth-publish-token.t
prove -lr t/auth-publish-token.t t/cli-auth-publish-token.t t/diagnostics-contract.t t/p14-claim-audit.t
prove -lr t/cli-auth-hmac.t t/v1-cli-witness.t t/v1-signed-hmac.t t/v1-signed-hmac-overlay.t t/profile-signed-hmac.t t/hmac-auth.t
prove -lr t
git diff --check
perl -MExtUtils::Manifest=fullcheck -e 'fullcheck()'
```

Result:

```text
P20a targeted checks: PASS.
Full prove: Files=81, Tests=1086, all successful.
Live FTP tests were skipped unless GOBANFTP_FTP_TEST=1 is set.
```

Latest local verification after P19 signed-HMAC substrate overlay:

```text
perl -Ilib -c lib/GobanFTP/Witness.pm
perl -Ilib -c lib/GobanFTP/CLI.pm
prove -lr t/v1-signed-hmac-overlay.t
prove -lr t/v1-signed-hmac-overlay.t t/v1-cli-witness.t t/diagnostics-contract.t t/p14-claim-audit.t
prove -lr t/v1-signed-hmac.t t/profile-adapter.t t/witness-api.t t/v1-cross-substrate.t
prove -lr t
git diff --check
perl -MExtUtils::Manifest=fullcheck -e 'fullcheck()'
script/gobanftp v1 witness --profile signed-hmac-goftp1 --substrate-profile ftp-goftp1 --fixture t/fixtures/v1/cross-substrate/minimal --attestations t/fixtures/v1/signed-hmac/valid/signed-hmac-goftp1/attestations.jsonl --trusted-hmac-key 'fixture-key-1=gobanftp signed hmac fixture key 1'
```

Result:

```text
P19 local checks: PASS.
Full prove: Files=79, Tests=1079, all successful.
Live FTP tests were skipped unless GOBANFTP_FTP_TEST=1 is set.
Overlay CLI smoke: PASS, signature.status=ok,
event_set_root=599c00f0614e400274a92ab1c96d09087a53d0d88bd8b0ecba481ac60a1f1461.
```

Latest verification after the successful `1.000_001` clean-checkout development
freeze:

```text
clean worktree matrix from docs/P14_RELEASE_MANIFEST_AND_TAG_PLAN.md
candidate commit 1f5f646921f675c93e25819cb3cf3652f5d6bebe
worktree /tmp/gobanftp-p14-claim-matrix.xQjVL4/worktree, removed after the run
logs /tmp/gobanftp-p14-claim-matrix.xQjVL4/logs
```

Result:

```text
Matrix: PASS.
perl -c oracle/goban.pl: PASS.
perl oracle/goban.pl --smoke: PASS, source-art inline_c=skip.
GOBANFTP_RULES_DISABLE_C=1 GOBANFTP_RULES_ENGINE=perl make test:
  Files=75, Tests=1042, all successful.
GOBANFTP_RULES_ENGINE=shadow make test:
  Files=75, Tests=1046, all successful.
prove -lr t:
  Files=75, Tests=1046, all successful.
Targeted v1/profile/rules gates:
  v1-cross-substrate 1/7, v1-attack-fixtures 1/30,
  v1-profile-attack-fixtures 1/10, v1-profile-publish-fixtures 1/9,
  v1-golden-vectors 1/130, v1-signed-hmac 1/14,
  v1-signed-hmac-golden-vectors 1/29, profile/witness 3/67,
  diagnostics 1/4, rules-flow+superko 2/7, p14-claim-audit 1/12.
v1 witness, compare-roots, and compare-replay fixture commands: PASS.
make manifest plus MANIFEST/MANIFEST.SKIP diff gate: PASS.
make dist: PASS, GobanFTP-1.000_001.tar.gz.
tarball evidence checks: P14 docs, non-consensus poison vector, minimal FTP
  listing fixture, tmp-poison pending.part, and
  ftp-listing-shadow-poison-public-vector, core-bad-signature-public-vector,
  t/p14-claim-audit.t, and arch-gate marker present.
tarball hygiene checks: SESSION_RESTORE, build trees, _Inline, MYMETA,
  pm_to_blib, nested tarballs, and stale distdirs absent.
disttest no-C: Files=75, Tests=1042, all successful.
make distcheck: PASS.
dist_sha256=45347dff8f9ac649ec194ab729172df25fa675556fadcb83f0964dc8d18c7e00
dist_size_bytes=328408
tar_entries=784
MANIFEST_sha256=e8efd1d7c7e5ea51cd35575875606b5d4559a6e2f7c4884828ea4688da599ba5
minimal_event_set_root=599c00f0614e400274a92ab1c96d09087a53d0d88bd8b0ecba481ac60a1f1461
Live FTP: skipped; GOBANFTP_FTP_TEST was not set.
This is not the final stable v1.0 matrix.
```

Earlier verification after clarifying the active P14 release plan and separating
the `1.000_001` development freeze matrix from the reserved final `v1.0`
identity:

```text
git diff --check
perl -MExtUtils::Manifest=fullcheck -e 'fullcheck()'
prove -lr t/v1-golden-vectors.t
prove -lr t/replay.t t/replay-ack-assisted.t t/dag.t t/replay-input-boundary.t
prove -lr t/rules-play.t t/rules-flow.t t/rules-superko.t t/rules-engine.t t/ruleset-seal.t
prove -lr t/witness-api.t t/profile-adapter.t t/profile-signed-hmac.t t/v1-cross-substrate.t t/v1-signed-hmac.t
script/gobanftp v1 compare-replay --fixture t/fixtures/v1/cross-substrate/minimal
prove -lr t
```

Full test result:

```text
Files=73, Tests=981, all successful.
Live FTP tests were skipped unless GOBANFTP_FTP_TEST=1 is set.
```

Earlier P14a release-gate dry-run integration passed or recorded:

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

Earlier full test result:

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
after P20a HMAC publish token semantics:
- keep `GOFTP-HMAC-PUBLISH/1` as verifier-local fixture publish-auth semantics;
  it is not real writer access, transport auth, or production key lifecycle
- unsigned `GOFTP/1`, existing `publish-move`, `publish-ack`, and `play` default
  paths still do not read auth material
- likely next v1.0-completeness slice is P20b: decide whether to add an
  explicit default-off publish preflight auth gate to `publish-move`,
  `publish-ack`, and `play`, or proceed to the final stable clean-checkout
  matrix if no more features are accepted before release
- do not tag v1.0 until the final claim audit passes, the final stable
  clean-checkout matrix passes, and the external artifact record is attached
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
lib/GobanFTP/Auth/HMACKey.pm
lib/GobanFTP/Auth/PublishToken.pm
lib/GobanFTP/Profile/SignedHMAC.pm
lib/GobanFTP/Witness.pm
lib/GobanFTP/CLI.pm
lib/GobanFTP/Oracle/Smoke.pm
lib/GobanFTP/Surface/WitnessView.pm
lib/GobanFTP/TUI/Play.pm
oracle/goban.pl
lib/GobanFTP/Diagnostics.pm
t/fixtures/auth/
t/fixtures/v1/signed-hmac/
t/fixtures/vectors/v1-signed-hmac-witness.jsonl
t/fixtures/vectors/v1-non-consensus-poison.jsonl
t/v1-signed-hmac.t
t/v1-signed-hmac-overlay.t
t/auth-hmac-key.t
t/cli-auth-hmac.t
t/auth-publish-token.t
t/cli-auth-publish-token.t
t/v1-signed-hmac-golden-vectors.t
t/v1-golden-vectors.t
t/v1-cli-witness.t
t/v1-cli-witness-surface-golden.t
t/v1-cli-witness-surface.t
t/source-art.t
t/p14-claim-audit.t
t/surface-witness-view.t
t/tui-play.t
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
4. Confirm HEAD includes `release: enter v1.0 final candidate identity`.
5. If the user asks to continue, review the next step first, then choose one
   small executable step.
