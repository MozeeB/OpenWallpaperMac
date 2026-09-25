# PKG container (`scene.pkg`)

A flat archive of a scene's files. All integers are little-endian `Int32`.

| Field | Type | Notes |
|---|---|---|
| magic | Int32 length + ASCII | `PKGV` followed by four digits (e.g. `PKGV0019`); ≤ 32 bytes |
| entry count | Int32 | ≤ 65 536 (our limit) |
| entries | repeated | see below |
| data | bytes | concatenated file contents |

Each entry: Int32-prefixed UTF-8 path (≤ 1024 bytes), Int32 `offset`, Int32 `length`.
`offset` is relative to the **end of the header** (the first byte after the last entry).

## Validation (`PKGParser`)

- magic format checked; negative/oversized counts and lengths rejected
- `offset + length` computed with overflow detection and must lie within the file
- paths go through `SanitizedPath` (no absolute paths, no `..`, backslashes normalised); duplicates
  (case-insensitive) rejected
- files are memory-mapped; entry data is sliced lazily

Sources: public descriptions of the container, including the RePKG project's documentation (MIT).
