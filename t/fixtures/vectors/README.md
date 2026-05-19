# Vector Fixtures

This directory contains public golden vectors for protocol calculations that
other implementations should be able to reproduce without importing Perl code.

`event-set-root.jsonl` covers the draft `GOFTP-EVENT-SET/1` witness root. The
root accepts only direct GOFTP/1 `m1` and `a1` event basenames that parse and
verify their filename event ids for the given game descriptor. DAG-invalid and
rule-invalid packets are still accepted into the root when their filename
grammar and event id are valid. Malformed names, unknown versions, bad event
ids, recursive children, and ignored surfaces stay outside the root.

`v1-witness.jsonl` freezes the v1 witness fields computed from
`t/fixtures/v1/cross-substrate/` for `local-goftp1`, `ftp-goftp1`,
`git-tree-goftp1`, `dns-record-goftp1`, and `webdav-goftp1`. Each row names the
input listing fixture, embeds the raw input names, and records the accepted
events, rejected diagnostics, replay diagnostics, event set root, replay status,
canonical and legal ids, projection hashes, rendered board/verdict/listing/SGF
text, and ruleset seal fields produced by `GobanFTP::Witness`.
These rows are public witness evidence for read admission. They do not claim Git
publish support, live DNS, AXFR, DNSSEC trust, provider APIs, dynamic update, or
DNS record publishing.

`v1-replay-invariants.jsonl` freezes compact core replay outcomes that are not
cross-substrate listing cases: an illegal sibling does not block the sole legal
line, invalid root move metadata stays out of canonical replay, and an ACK by a
non-player is rejected without changing the canonical move line. It also covers
capture, suicide rejection, bounds parse rejection, single pass, two-pass
terminal play, resign terminal play, simple-ko superko rejection, ack-assisted
fork choice, malformed basenames, parent-is-ACK rejection, dangling ACK targets,
and ACK targets that are themselves ACKs.

`v1-non-consensus-poison.jsonl` freezes compact baseline/poison witness pairs
for non-consensus evidence. Each row declares its own `ignored_inputs`,
`evidence_markers`, optional `poisoned_order`, and optional
`poisoned.evidence_artifacts`, then binds the embedded `input_names` back to
real fixture listings. Evidence artifacts name ignored fixture files such as
mtime tables, event bytes, sidecar JSON, projection files, or temporary publish
debris, and embed their exact text when the poison is deliberately outside the
listing names. Current rows promote
core/local bad-mtime, bad-payload, bad-list-order, bad-signature,
poisoned-sidecar, projection-poison, and tmp-poison specimens, plus the WebDAV
metadata-poison, WebDAV href-traversal, DNS owner-poison, and Git-tree
path/metadata-poison fixtures, and the FTP listing-shadow cross-substrate
fixture. They prove
accepted events, event-set preimage, event-set root, canonical ids, board hash,
projection text, and SGF hashes stay identical when only ignored evidence
changes. These rows prove the evidence stays outside truth; they do not make
content, mtime, sidecar, sidecar signature, projection, tmp, WebDAV dot
segments, encoded slash/backslash href rows, TTL/order rows,
Git commit/ref/object metadata, FTP sidecar/tmp/projection/recursive/list-order
rows, or transport metadata replay inputs. DNS owner labels are used only for
current-game record scoping, not as replay truth. These vectors do not claim
Git publish or remote fetch support,
live DNS, AXFR, DNSSEC trust, provider APIs, dynamic update, DNS record
publishing, live FTP, or FTP publish behavior.

`v1-dag-invariants.jsonl` freezes DAG-boundary outcomes that cannot accurately be
expressed as ordinary public replay basenames. Its event-id collision row uses
synthetic DAG `input_items` with distinct synthetic names and the same
`event_id`, and explicitly records that it is not an ordinary basename
collision. Replay reparses ordinary event basenames against the game descriptor
before DAG construction, so a fabricated ordinary basename collision would
become an event-id mismatch unless a real hash collision exists.

`v1-signed-hmac-witness.jsonl` freezes the signed-HMAC profile witness fields
for valid, injected-event, missing, wrong, payload-mismatched,
game-descriptor-mismatched, untrusted, and malformed event attestations. It
also freezes lifecycle rows for trusted, rotated, revoked, and expired HMAC
selectors, plus public-trust bridge rows proving advisory `k1.` key/trust
material cannot authorize `signed-hmac-goftp1` HMAC selectors or revoke an
explicit fixture HMAC selector. Rows name both the listing fixture and the
public attestation fixture. Public-trust bridge rows also bind the public key
and trust TSV fixture text and its parsed advisory summary. The vector records
the public trust selector, lifecycle status, accepted/rejected events, rejected
diagnostics, replay diagnostics, raw input names, and rendered projection text,
but not the HMAC secret used by the verifier test.

`v1-publish-auth.jsonl` freezes public publish-auth evidence for a mismatched
publish token. The current row binds a public `GOFTP-HMAC-PUBLISH/1` token
signed for one event to a different candidate event, proving the verifier
denies it with stable `wrong_signature` / `event_basename.mismatch` evidence.
The same row also pins the unsigned `local-goftp1` witness for the fixture
listing, proving publish-auth token material and the denied candidate do not
change unsigned `GOFTP/1` truth.

`ruleset-seal.jsonl` freezes the `chinese-area-v1` ruleset seal, fixture digest
manifest, and byte-level preimage hex for `GOFTP-RULESET-SEAL/1`.
