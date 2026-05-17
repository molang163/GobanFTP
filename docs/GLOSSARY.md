# Glossary

## Ack

An acknowledgement event name. It says a player has seen a target event.

## Authoritative Event

An event name under `events/` whose grammar and event id validate.
Authoritative events are the replay input.

## Canonical Filename Grammar

The exact grammar used for game descriptor and event basenames. GOFTP/1 core
replay depends on names, not file contents.

## Canonical Line

The line of play selected from the DAG for current gameplay and projection
output.

## DAG

Directed acyclic graph. In GobanFTP, every move points to a parent event id. Multiple
moves may point to the same parent, creating forks.

## Fork

Two or more valid events competing after the same parent. Forks are preserved
and displayed, not deleted.

## GOFTP/1

The GobanFTP storage protocol version.

## Game Descriptor

The game root directory name. It binds board size, rules, players, and game id.

## Listing-First

The core GOFTP/1 premise: `NLST` or `MLSD` output is enough to replay the game.
File contents are optional sidecars.

## Merkle DAG

A DAG where event ids cover parent ids through filename hash input. This makes
history tamper-evident within the limits of short event ids.

## Projection

A generated view of the authoritative state, such as SGF, board directories, or
`projections/oracle/board.txt`.

## Ref

An advisory pointer file. Refs speed up discovery but do not determine
consensus.

## Ritual Layer

The human-facing weirdness: FTP command names, source art, decorative projection
paths, and spell text.

## Source Art

Code arranged to look like a picture. In this project, `oracle/goban.pl` may look
like a Go board, but protocol bytes must not depend on that layout.

## State Hash

The hash of deterministic state bytes after applying a move.

## Sidecar

Optional file content associated with an event id. Sidecars can help humans and
debuggers, but core replay must ignore them.
