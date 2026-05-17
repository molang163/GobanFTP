# Sidecar Marginalia

Sidecar files are optional notes placed near event ids. They may contain
comments, signatures, stale hints, external audit notes, or cached diagnostics.

They are never GOFTP/1 consensus input.

If a sidecar file disagrees with an event filename, the filename wins. The test
suite mutates and deletes sidecar files while proving replay stays unchanged.
