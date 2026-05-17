# Rebuildable Projections

All files under this directory are rebuildable projections. They are derived
from the game descriptor basename and the direct `events/` child basenames.

They are not consensus inputs. Delete and rebuild them with:

```sh
perl -Ilib script/gobanftp project examples/fixtures/minimal-game/g1.id-minimal.s9.r-chinese-area-v1.k7500.pb-alice.pw-bob
```

`oracle/listing.txt` is a projection transcript of the `NLST events/` read. It
is not a replay input.
