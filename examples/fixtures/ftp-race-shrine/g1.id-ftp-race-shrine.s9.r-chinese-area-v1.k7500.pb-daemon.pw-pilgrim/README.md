# GOFTP/1 Race Shrine Mirror

This directory is shaped like an FTP mirror after a weak-consistency race.

Authoritative names:

```text
events/
  m1.p000001.b.play-dd.pa-genesis.by-daemon.n-root1.h-hihat4p8r6gaeuts
  m1.p000002.w.play-ee.pa-hihat4p8r6gaeuts.by-pilgrim.n-raceleft.h-ps9v3kftvp5v1gl5
  m1.p000002.w.play-ff.pa-hihat4p8r6gaeuts.by-pilgrim.n-raceright.h-o00qmn6v8j683ds6
  a1.t-ps9v3kftvp5v1gl5.by-daemon.n-ackleft.h-7d3cjn514h885jq1
```

The two white move names have the same parent:

```text
pa-hihat4p8r6gaeuts
```

Conservative replay stops there and reports a fork. The ack event targets
`ps9v3kftvp5v1gl5`, but that matters only when the caller explicitly asks for
ack-assisted replay.

Readable but not authoritative:

```text
sidecar/      notes only
projections/  conservative board, SGF, verdict, and listing transcript
tmp/          publish staging residue
```

Delete `sidecar/` or rewrite event file bytes: replay must still see the same
fork. Delete `projections/` and rebuild it from `events/`: the fork must come
back.
