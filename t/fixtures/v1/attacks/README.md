# V1 Profile Attack Fixtures

These fixtures prove that profile-specific substrate noise does not change the
`GOFTP/1` witness. Each specimen compares one hostile profile listing against a
clean baseline listing for the same game descriptor.

Every specimen contains:

```text
game.name
expected.verdict
<baseline-profile>/listing.names
<profile-under-attack>/listing.names
```

The verdict names the attacked profile, the baseline profile, the expected
accepted event set root, replay status, canonical ids, legal ids, diagnostic
classes, ignored inputs, and the public judgment for the specimen.
`webdav-metadata-poison` is also promoted into
`t/fixtures/vectors/v1-non-consensus-poison.jsonl` as a public baseline/poison
golden vector.

Current specimens:

```text
webdav-metadata-poison  metadata and shadow resources do not affect witness truth
webdav-href-traversal   dot segments and encoded traversal cannot smuggle events
dns-owner-poison        wrong or missing DNS owner labels cannot smuggle events
git-tree-path-metadata-poison Git tree metadata and paths cannot smuggle events
```
