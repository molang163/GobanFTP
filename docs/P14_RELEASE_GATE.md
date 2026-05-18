# P14 Release Gate Dry Run

Status: dry run only. This is not a v1.0 tag, not P14 completion, and not a
release-ready declaration.

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
turn static witness surfaces into hosted Web UI or interactive TUI.

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
- Interactive mouse/keyboard TUI remains deferred.
- Git-like and DNS-like profiles remain fixture/read-normalizer proof surfaces
  unless runtime support is explicitly implemented later.
- Production key lifecycle policy remains outside the current signed-HMAC
  fixture verifier.

## Not Claimed

- P14 is not complete.
- v1.0 is not ready or tagged.
- Static HTML witness output is not hosted Web UI.
- `--surface terminal` is not an interactive TUI.
- `make dist` success in a dry run is not a publication event.

## Next Release-Route Step

The post-correction clean-worktree rerun is recorded above. The next
release-route step is to decide whether to create a final release artifact
manifest and tag plan, while keeping every deferred runtime surface or profile
claim explicit. Do not tag v1.0 until the final intended release matrix, not just
this dry run, has passed. The artifact and tag plan lives in
`docs/P14_RELEASE_MANIFEST_AND_TAG_PLAN.md`.
