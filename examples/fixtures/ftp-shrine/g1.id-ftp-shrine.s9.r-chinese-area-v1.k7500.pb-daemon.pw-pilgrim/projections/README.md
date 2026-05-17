# Shrine Projections

These files are projections, not truth.

They were rendered from:

```text
game descriptor basename
direct events/ child basenames
```

The board, SGF, graveyard, oracle verdict, and point files can be deleted and
rebuilt. Core replay must not read this directory.

`oracle/listing.txt` is also a projection. It is a readable FTP transcript that
shows the current `NLST events/` result and states which FTP operations are
outside replay. It is not a consensus file.
