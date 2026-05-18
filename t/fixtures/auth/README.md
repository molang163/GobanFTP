# Auth Fixture Contract

This directory is reserved for public auth and trust fixtures. It must not
contain real private keys, signing seeds, passwords, tokens, HMAC secrets, or
credential URLs.

Fixtures exercise `gobanftp v1 keyid --fixture` plus future `attest` and
`trust-report` plumbing without creating a real private key system. All fixture
key material is public and non-authoritative unless a future signed profile
explicitly says otherwise.

The `hmac/` vectors use public test keys to lock down deterministic
HMAC-SHA256 framing. They are test vectors, not credentials, and must not be
reused for production games.

## Public Key Records

Fixture public key files use:

```text
gobanftp-public-key-v1
suite=fixture-ed25519-v1
public_hex=<64 lowercase hex chars>
```

`fixture-ed25519-v1` is a parser fixture suite, not a cryptographic signing
suite. It has no private key file and no valid production signature operation.

Key id preimage:

```text
"GOFTP-KEY/1\0" ||
suite || "\0" ||
public_key_bytes || "\0"
```

Key id:

```text
"k1." || first 32 chars of lowercase base32hex(SHA256(preimage))
```

Example:

```text
gobanftp-public-key-v1
suite=fixture-ed25519-v1
public_hex=000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f
```

Expected key id:

```text
k1.jk4bs0r77srdlpds260hka9fpp49clpg
```

## Suggested Case Layout

```text
t/fixtures/auth/<case>/
  game.name
  listing.names
  keys/
    <key_id>.pub
  trust.tsv
  attestations.tsv
  expected.trust-report
```

`game.name` and `listing.names` describe the unsigned GOFTP/1 replay input.
`keys/`, `trust.tsv`, and `attestations.tsv` are advisory inputs for auth tests
and must not change the unsigned replay result.

## Trust TSV

Trust files are public TSV:

```text
GOFTP-TRUST/1
key_id	suite	principal	role	status	not_before	not_after	revoked_at	reason
k1.example	fixture-ed25519-v1	player:alice	player	trusted	2026-01-01	-	-	fixture
```

Rules:

- `key_id` must match the key id derived from the referenced public key record.
- `principal` is public, for example `player:alice` or `observer:referee`.
- `status` is `trusted`, `revoked`, `expired`, or `unknown`.
- `-` means absent for date and reason fields.
- Trust records are not replay inputs for unsigned profiles.

## Attestations TSV

Attestation files are public TSV:

```text
GOFTP-ATTEST/1
scope	profile_id	game	event_set_root_version	event_set_root	event	key_id	claimed_at	signature
event-set	local-goftp1	g1.id-demo.s9.r-chinese-area-v1.k7500.pb-alice.pw-bob	GOFTP-EVENT-SET/1	<sha256-hex>	-	k1.example	2026-01-01T00:00:00Z	fixture:<hex>
event	local-goftp1	g1.id-demo.s9.r-chinese-area-v1.k7500.pb-alice.pw-bob	-	-	<event-basename>	k1.example	2026-01-01T00:00:00Z	fixture:<hex>
```

Fixture signatures are placeholders. A real signed profile must define its
signature suite, preimage, verification algorithm, required signers, and failure
diagnostics before fixture signatures can become consensus.

## Old Game Verification

Old unsigned games remain valid GOFTP/1 games. Verify them with:

```sh
script/gobanftp verify <game-root|game-descriptor>
```

Future trust reports may say `unsigned`, `untrusted`, or `no_attestation` for
these games, but unsigned replay must still use only the game descriptor
basename and direct accepted `events/` basenames.
