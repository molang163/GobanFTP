# V1 Publish Failure Fixtures

These fixtures prove that substrate publish ceremonies can fail without creating
hidden witness truth. Each specimen names one candidate event, the public storage
failure surface, and the event-set root that remains visible after the failure.

Publish failure fixtures are not replay fixtures by themselves. They pair with
store or CLI tests that exercise the live publish path, then compare the visible
listing against the same `GOFTP/1` witness rules used by profile fixtures.

Every specimen contains:

```text
game.name
event.name
expected.verdict
```

Current specimens:

```text
webdav-publish-failure  existing final, delayed visibility, hard MOVE failure
```
