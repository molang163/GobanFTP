# GOFTP/1 Shrine Mirror

This directory is shaped like a small FTP game mirror.

Authoritative names:

```text
events/
  m1.p000001.b.play-dd.pa-genesis.by-daemon.n-altar1.h-0agr68rv1sp5qi21
  m1.p000002.w.play-ff.pa-0agr68rv1sp5qi21.by-pilgrim.n-lamp1.h-k1kalhibnvic4mno
  m1.p000003.b.play-de.pa-k1kalhibnvic4mno.by-daemon.n-bell1.h-p3ige9epnj7c6om0
  m1.p000004.w.play-ef.pa-p3ige9epnj7c6om0.by-pilgrim.n-candle1.h-tndasisr9c6ihr0j
  m1.p000005.b.play-df.pa-tndasisr9c6ihr0j.by-daemon.n-gate1.h-eqc92l6ocvbm6mgd
  m1.p000006.w.play-fe.pa-eqc92l6ocvbm6mgd.by-pilgrim.n-veil1.h-2m3u03ptk0oqdc91
  a1.t-2m3u03ptk0oqdc91.by-daemon.n-wax1.h-3vsjo1vqsend0f02
```

Readable but not authoritative:

```text
sidecar/                 comments, stale notes, signature placeholders
projections/             rebuilt board, SGF, oracle verdict, point files
projections/oracle/listing.txt  transcript projection of an FTP listing read
tmp/                     publish staging area
```

Delete `sidecar/` or rewrite every byte inside it: replay must still produce the
same six-move line. Delete `projections/` and rebuild it from `events/`: the
rendered board and SGF must come back.

`projections/oracle/listing.txt` is a display transcript. It documents that
`NLST events/` exposes the seven current event basenames. It also documents that
`RETR`, `SIZE`, and `MDTM` are not replay inputs.
