# Filename Grammar Fixtures

These fixtures lock down the GOFTP/1 listing-first protocol.

Core replay must be able to use only:

```text
game.name
valid.names
```

No fixture in this directory requires reading event file contents.

## Files

```text
game.name          one game descriptor basename
valid.names        valid full event basenames, including h-<event_id>
expected_ids.tsv   event-name-without-hash to expected event id
invalid.names      invalid event basenames with expected rejection reasons
valid-events.jsonl machine-readable valid parser cases
invalid-events.jsonl machine-readable invalid parser cases
```

Future tests should prefer the JSONL files. The `.names` and `.tsv` files are
kept as compact human-readable mirrors.

`expected_ids.tsv` uses this event id rule:

```text
first16(base32hex_lower_no_padding(
  sha256("GOFTP-EVENT/1\0" || game_descriptor || "\0" || event_without_hash)
))
```
