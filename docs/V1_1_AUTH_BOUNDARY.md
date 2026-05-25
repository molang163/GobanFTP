# GobanFTP v1.1.0-beta.1 Auth Boundary

Status: v1.1.0-beta.1 / package 1.100_001 beta auth-boundary reference.
Date: 2026-05-25 Asia/Shanghai

This document names the auth scopes used by the v1.1.0-beta.1 beta. It is a
boundary document, not a production authorization design.

## Scopes

- `unsigned replay`: `GOFTP/1` replay is still the game descriptor basename plus
  accepted direct `events/` basenames. Auth material does not change unsigned
  replay truth.
- `advisory trust`: trust reports describe local fixture records. They do not
  authorize writers, accounts, transports, or production key lifecycle.
- `signed-HMAC witness gate`: signed-HMAC witness checks may reject fixture
  witness material for that profile. Public `k1.` key namespace selectors do
  not authorize signed-HMAC selectors.
- `fixture-preflight`: publish preflight verifies one proposed candidate
  basename against an explicit publish token and verifier-supplied HMAC key
  material. The status literal `authorized` means the fixture preflight passed;
  it is not production writer authorization.
- `transport credentials`: FTP/WebDAV credentials and tokens protect transport
  access only. They are not printed in status, JSON, diagnostics, examples, or
  release evidence.

## Public Fields

Publish preflight outputs include:

```text
publish_auth.scope=fixture-preflight
publish_auth.production_authorization=0
publish_auth.status=<authorized|denied>
```

JSON publish results carry the same scope under `publish_auth`.

## Non-Goals

- No production auth system.
- No production writer authorization.
- No account identity binding.
- No production key lifecycle.
- No transport credential management beyond redaction and HTTPS checks already
  documented for WebDAV.
- No change to unsigned `GOFTP/1` replay.
