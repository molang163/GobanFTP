# P14 Release Gate Evidence

Status: dry-run, development-freeze, and final-candidate preparation evidence
only. This is not a v1.0 tag, not P14 completion, and not a release-ready
declaration.

Dry-run date: 2026-05-18
Base commit: `2788ffa52ac8145369b66665a8b089a51ce0ae03`
Dry-run source state: base commit plus the in-worktree manifest-skip correction
described below
Worktree: `/tmp/gobanftp-p14-dryrun.Gyyf75`
Perl: `v5.42.2`

## Scope

This records the first P14a release-gate dry run against the current v1.0 proof
machine and the post-correction clean-worktree rerun. It records command
coverage, skipped gates, generated artifacts, and known release-route gaps.

The dry run uses existing commands only. It does not add a second witness
assembler, does not change `GOFTP/1`, does not publish artifacts, and does not
turn static witness surfaces into hosted Web UI. Current HEAD also has a
separate local `play --tui` input/display surface; it remains outside replay
truth and outside this historical dry-run evidence.

## Result Summary

All executed gates passed after correcting the release manifest skip rules in
`MANIFEST.SKIP`.

Two manifest issues were found during the dry run:

- a detached worktree exposes `.git` as a file, so `^\.git/` did not skip it
- the broad `*.part` skip rule excluded the intentional
  `t/fixtures/attacks/tmp-poison/tmp/pending.part` attack specimen

The fix is to skip `.git` as either a file or directory and to keep temporary
scratch-name skips from excluding files under `t/fixtures/`.

## Command Matrix

| Gate | Command | Result |
| --- | --- | --- |
| Source art syntax | `perl -c oracle/goban.pl` | PASS |
| Source art smoke | `perl oracle/goban.pl --smoke` | PASS, `inline_c=skip` |
| MakeMaker configure | `perl Makefile.PL` | PASS; generated `Makefile`, `MYMETA.*` |
| Perl rules make test | `GOBANFTP_RULES_DISABLE_C=1 GOBANFTP_RULES_ENGINE=perl make test` | PASS, `Files=70, Tests=939`; live FTP and C equivalence tests skipped |
| Shadow rules make test | `GOBANFTP_RULES_ENGINE=shadow make test` | PASS, `Files=70, Tests=943`; live FTP tests skipped |
| Full prove suite | `prove -lr t` | PASS, `Files=70, Tests=943`; live FTP tests skipped |
| v1 cross-substrate | `prove -lr t/v1-cross-substrate.t` | PASS, `Files=1, Tests=7` |
| v1 attacks | `prove -lr t/v1-attack-fixtures.t` | PASS, `Files=1, Tests=28` |
| v1 golden vectors | `prove -lr t/v1-golden-vectors.t` | PASS, `Files=1, Tests=71` |
| signed-HMAC | `prove -lr t/v1-signed-hmac.t` | PASS, `Files=1, Tests=14` |
| signed-HMAC vectors | `prove -lr t/v1-signed-hmac-golden-vectors.t` | PASS, `Files=1, Tests=25` |
| profile/witness contracts | `prove -lr t/profile-registry.t t/profile-adapter.t t/witness-api.t` | PASS, `Files=3, Tests=67` |
| diagnostics contract | `prove -lr t/diagnostics-contract.t` | PASS, `Files=1, Tests=4` |
| rules flow | `prove -lr t/rules-flow.t t/rules-superko.t` | PASS, `Files=2, Tests=7` |
| v1 witness CLI proof | `script/gobanftp v1 witness --profile local-goftp1 --fixture t/fixtures/v1/cross-substrate/minimal` | PASS, root `599c00f0614e400274a92ab1c96d09087a53d0d88bd8b0ecba481ac60a1f1461` |
| v1 root comparison | `script/gobanftp v1 compare-roots --fixture t/fixtures/v1/cross-substrate/minimal` | PASS, five fixture profiles agree, `mismatch_count=0` |
| v1 replay comparison | `script/gobanftp v1 compare-replay --fixture t/fixtures/v1/cross-substrate/minimal` | PASS, five fixture profiles agree, `mismatch_count=0` |
| Manifest refresh | `make manifest` | PASS after `MANIFEST.SKIP` correction; updated `MANIFEST` ordering |
| Distribution archive | `make dist` | PASS, created `GobanFTP-0.001.tar.gz` |
| Distribution test | `GOBANFTP_RULES_DISABLE_C=1 GOBANFTP_RULES_ENGINE=perl make disttest` | PASS, `Files=70, Tests=939`; live FTP and C equivalence tests skipped |
| Distribution check | `make distcheck` | PASS |

## Generated Artifacts

The dry run generated artifacts only inside the temporary worktree:

- `Makefile`
- `MYMETA.json`
- `MYMETA.yml`
- `blib/`
- `pm_to_blib`
- `_Inline/`
- `GobanFTP-0.001/`
- `GobanFTP-0.001.tar.gz`

The archive observed during the dry run was:

```text
GobanFTP-0.001.tar.gz
sha256=50ed4eaa3dac99be2a0f399472d7f1a6cbbb1b278fe508a0a62afb64aaff7c29
size=275K
```

The archive is not committed by this dry run. It predates this checked-in report
and is not the final release artifact manifest.

## Post-Correction Clean Worktree Check

After the manifest correction and this report were committed, the same matrix
was rerun from a fresh detached worktree:

```text
Commit: 01e460044a64ca524fa6f80fa75b4cd0b6e5ed6e
Worktree: /tmp/gobanftp-p14-clean.FmmCRF
Perl: v5.42.2
```

Result: PASS.

Additional post-correction checks:

```text
make manifest left MANIFEST and MANIFEST.SKIP unchanged
tarball contained docs/P14_RELEASE_GATE.md
tarball contained t/fixtures/attacks/tmp-poison/tmp/pending.part
```

The post-correction archive observed during the clean-worktree rerun was:

```text
GobanFTP-0.001.tar.gz
sha256=4c26f252b4d970a801213c61d351621b212077eff8bfd29cdd66a90bdbe8579f
size=279K
```

The archive is still a dry-run artifact. It is not committed and is not a
publication event.

## Skipped Or Deferred

- Live FTP tests were skipped because `GOBANFTP_FTP_TEST=1` was not set.
- Inline::C was optional; source-art smoke reported `inline_c=skip`.
- v1.0 was not tagged.
- No release artifacts were published.
- Full hosted Web UI remains deferred.
- At the dry-run commits, interactive mouse/keyboard TUI was deferred. Current
  HEAD adds local `play --tui`; the final gate must run its TUI tests and smoke
  path.
- At the dry-run commits, Git-like and DNS-like profiles were
  fixture/read-normalizer proof surfaces. Current HEAD has since added
  read-only Git-tree and DNS-record runtime admission, so this dry run is
  historical evidence, not the current final clean gate.
- Production key lifecycle policy beyond verifier-local signed-HMAC key files
  remains outside the current signed-HMAC operation layer.
- Publish authentication policy remains outside the current signed-HMAC
  operation layer.

## Not Claimed

- P14 is not complete.
- v1.0 is not ready or tagged.
- Static HTML witness output is not hosted Web UI.
- `--surface terminal` is not the local `play --tui` input surface.
- `make dist` success in a dry run is not a publication event.
- `make dist` success in the `1.000_001` development freeze is not a final
  stable v1.0 publication event.

## Current Development Freeze Clean-Checkout Check

After the P14 claim-audit gate landed, the development freeze matrix from
`docs/P14_RELEASE_MANIFEST_AND_TAG_PLAN.md` passed again from a fresh clean
checkout:

```text
Date: 2026-05-19
Candidate commit: 1f5f646921f675c93e25819cb3cf3652f5d6bebe
Documentation record commit: post-run record, not tested tarball source
Worktree: /tmp/gobanftp-p14-claim-matrix.xQjVL4/worktree (removed)
Logs: /tmp/gobanftp-p14-claim-matrix.xQjVL4/logs
Perl: v5.42.2
Matrix: PASS
Dist: GobanFTP-1.000_001.tar.gz
sha256=45347dff8f9ac649ec194ab729172df25fa675556fadcb83f0964dc8d18c7e00
size=328408 bytes
tar entries=784
MANIFEST sha256=e8efd1d7c7e5ea51cd35575875606b5d4559a6e2f7c4884828ea4688da599ba5
minimal event_set_root=599c00f0614e400274a92ab1c96d09087a53d0d88bd8b0ecba481ac60a1f1461
P14 claim audit: PASS, Files=1, Tests=12
Live FTP: skipped; GOBANFTP_FTP_TEST was not set
Inline::C: source-art optional path reported inline_c=skip
```

The tarball inclusion checks confirmed the P14 release-plan docs, public
non-consensus poison vector file, minimal FTP listing fixture, intentional
`tmp-poison/tmp/pending.part` specimen, `t/p14-claim-audit.t`,
`ftp-listing-shadow-poison-public-vector`, `core-bad-signature-public-vector`,
and the comment-only `arch-gate` source-art marker. The archive exclusion checks
confirmed the restore memory, local build trees, `_Inline/`, `MYMETA.*`,
`pm_to_blib`, nested tarballs, and stale dist directories were absent.

This was the `1.000_001` development freeze matrix, not the reserved stable
`v1.0` / package `1.000` release matrix. Because this documentation record is
written after the run, it is not inside the tested tarball and is not the tested
tarball source unless the matrix is rerun from this record commit.

The earlier clean-checkout matrix at
`e1c8b4036ce9bf2260455b0aa0834df544393845` remains historical development
evidence. The record above is now historical development-freeze evidence too;
it predates the later local TUI input and verifier-local signed-HMAC operation
work, so it is not current HEAD evidence.

## Post-Matrix Claim-Audit Targeted Check

Before the refreshed full development-freeze matrix above, the release-text
claim-audit gate was first checked as a targeted post-matrix gate:

```text
Date: 2026-05-19
Source state: 1f5f646921f675c93e25819cb3cf3652f5d6bebe
Command: prove -lr t/p14-claim-audit.t
Result: PASS
Scope: release-text claim-boundary check only
```

This targeted check guards README, Changes, V1 DoD, roadmap, P14 gate,
release-manifest/tag plan, and source-checkout restore memory against accidental
final-release over-claims. It is not a refreshed full clean-checkout matrix, not
a stable `v1.0` artifact check, and not a P14/v1.0 completion claim.
The current development-freeze matrix above now includes this gate.

## Next Release-Route Step

The `1.000_001` development freeze is recorded above. The source tree has now
entered the `v1.0` / package `1.000` final-candidate identity without creating
a tag or final artifact. Current HEAD has added local TUI input and
verifier-local signed-HMAC keygen/attest operation work after that recorded
development freeze. The next release-route step is to refresh the final claim
audit from this identity, run the final stable clean-checkout matrix, and attach
the external artifact record before any `v1.0` tag.
