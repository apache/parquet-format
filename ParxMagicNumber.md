# PARX Parquet Format Specification

This specification details a new magic number and associated fixed length footer metadata changes
that accompany the footer.

## Motivation

Most parts of the parquet specification lend themselves naturally to compatibility checks
when a new feature is added (e.g. encodings and compression values have an enum value added)
and fail appropriately.
However, some semantic changes or footer changes are impossible to communicate appropriately
within existing structures (e.g. changing the serialization of the footer). The motivation
for the new magic number and layout is to accomodate the latter set of changes by introducing
a new extensible mechanism for readers to detect these changes and fail accordingly.

## Design Motivations

* Provide a mechanism to only introduce a single new magic number for parquet that can
  last at least a decade.
* Provide integrity checks for the footer.
* Provide the ability for readers to have a granular understanding of structural and semantic
  backward incompatible features that are required to read a particular file.

## File Layout

A PARX file has the same overall structure as a standard Parquet file, with two differences:
the leading and trailing magic bytes are `PARX` instead of `PAR1/PARE`, and the trailing footer is
17 bytes instead of 8.

The file layout is as follows:

```
+-----------+-------------------+--------------------+-------------+
| 'PARX'    | File Data         | Footer Metadata    | Footer tail |
| (4 bytes) | (variable length) | (variable length)  | (17 bytes)  |
+-----------+----------+--------+--------------------+-------------+
```

All multi-byte integer fields are **little-endian**.


### PARX Footer Tail — 17 bytes

```
+------------------+-----------+-----------+----------+--------+
| metadata_len     | flags     | version   | crc32    | 'PARX' |
+------------------+-----------+-----------+----------+--------+
  offset 0          offset 4    offset 8    offset 9   offset 13
```

| Field          | Type    | Offset | Description                                                       |
|----------------|---------|--------|-------------------------------------------------------------------|
| `metadata_len` | u32 LE  | 0      | Byte length of the Thrift-encoded `FileMetaData` block            |
| `flags`        | u32 LE  | 4      | Feature flags (see [Feature Flags](#feature-flags))               |
| `version`      | u8      | 8      | Parquet format major version (see [Version](#version))            |
| `crc32`        | u32 LE  | 9      | CRC32 checksum (see [Integrity Check](#integrity-check))          |
| `magic`        | [u8; 4] | 13     | Always the bytes `P A R X` (0x50 0x41 0x52 0x58)                  |

## Feature Flags

The `flags` field is a 32-bit bitfield. A reader **must** reject any file whose `flags` field
contains bits that are not recognized or not supported, because unknown flags may imply structural changes
to the metadata or semantic changes to the file layout that the reader cannot properly interpret.

The PARX format is independent of the `version` field in `FileMetaData`; a file may use the PARX
magic number regardless of which specification version its metadata declares.

| Bit Index| Name                    | Description                                                                                                 |
|----------|-------------------------|-------------------------------------------------------------------------------------------------------------|
| 0        | `ENCRYPTED_FOOTER`      | The `FileMetaData` block is encrypted (equivalent to the `PARE` format).                                    |
| 1        | `PATH_IN_SCHEMA_OMITTED`   | Column `path_in_schema` fields are omitted from ColumnChunk metadata (this was a previously required field).|
| 2        | `PREVIEW_FEATURES`      | The file uses preview (experimental) features not yet part of the stable feature set of the major `version` written in the footer tail. Preview features that are not part of the major version are either detectable via additional feature flags in this bitmap or when parsing the encoded metadata. A preview feature (e.g. a new encoding) might cause thrift parsers to fail to parse the metadata, making this flag useful for providing better error messages to the user. |


The zero index is least significant bit in the field.
All other bits are reserved and must be zero.


## Version

The `version` field holds the Parquet format major version that produced the file. This is stored
outside of the Thrift footer so that a reader can always read it, even when the reader cannot parse
(or decrypt) the footer metadata itself.

The `version` field is a coarse-grained means for a reader to decide whether it can read a
file. The feature flags together with the encoded metadata provide readers a finer-grained
means to determine whether they support the feature set used to write the file, without explicitly
checking `version`. If parsing of metadata fails (e.g. because a new encoding enum that the reader
can't handle was present) version can also be used to give more informative error messages, e.g.:
`Failed to parse file written with major version 'X'; current reader fully supports up to version 'Y'.`

This is important because some Thrift parsers fail hard when they encounter a unknown enum
value for a required field. To preserve the ability of readers with custom Thrift parsers to still
read as much of the file as possible, the recommended order of operations is:

1. Verify the `crc32` checksum (see [Integrity Check](#integrity-check)).
2. Validate that the reader supports all set `flags`.
3. Attempt to parse the footer.
4. If footer parsing fails, consult `version` and the `PREVIEW_FEATURES` flag to produce an
   appropriate error message, e.g.:

```
Failed to parse footer. New version XX detected.
Failed to parse footer written with preview features enabled.
```


## Integrity Check

The `crc32` field holds a CRC-32 (ISO 3309 / ITU-T V.42 polynomial, the same used for page level CRC values)
computed over the following byte sequence, in order:

1. The raw `FileMetaData`/`Footer` bytes (i.e. the `metadata_len` bytes immediately before the 17-byte footer tail)
2. The first 9 bytes of the footer tail (metadata_len, flags bitmap, and version)

When `ENCRYPTED_FOOTER` (bit 0) is set, the CRC is computed over the footer bytes **as they appear in the
file** (i.e. the encrypted bytes). The CRC itself is always stored unencrypted in the footer tail.

