<!--
  - Licensed to the Apache Software Foundation (ASF) under one
  - or more contributor license agreements.  See the NOTICE file
  - distributed with this work for additional information
  - regarding copyright ownership.  The ASF licenses this file
  - to you under the Apache License, Version 2.0 (the
  - "License"); you may not use this file except in compliance
  - with the License.  You may obtain a copy of the License at
  -
  -   http://www.apache.org/licenses/LICENSE-2.0
  -
  - Unless required by applicable law or agreed to in writing,
  - software distributed under the License is distributed on an
  - "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
  - KIND, either express or implied.  See the License for the
  - specific language governing permissions and limitations
  - under the License.
  -->

# Parquet Core Features

This document lists the core features for each parquet-format release. This
list is a subset of the features which parquet-format makes available.

## Purpose

The list of core features for a certian release makes a compliance level that
the different implementations can tied to. If an implementation claims that it
provides the functionality of a parquet-format release core features it must
implement all of the listed features according the specification (both read and
write path). This way it is easier to ensure compatibility between the
different parquet implementations.
We cannot and don't want to stop our clients to use any features that are not
on this list but it shall be highlighted that using these features might make
the written parquet files unreadable by other implementations. We can say that
the features available in a parquet-format release (and one of the
implementations of it) and not on this list are experimental.

## Versioning

This document is versioned by the parquet-format releases which follows the
scheme of semantic versioning. It means that no feature will be deleted from
this document under the same major version. (We might deprecate some, though.)
Because of the semantic versioning if one implementation supports the core
features of the parquet-format release `a.b.x` it must be able to read any
parquet files written by implementations supporting the release `a.d.y` where
`b >= d`.

If a parquet file is written according to a released version of this document
it might be a good idea to write this version into the field `compliance_level`
in the thrift object `FileMetaData`.

## Adding new features

The idea is to only include features which are specified correctly and proven
to be useful for everyone. Because of that we require to have at least two
different implementations that are released and widely tested.

## The "list"

This list is based on the [parquet thrift file](src/main/thrift/parquet.thrift)
where all the data structures we might use in a parquet file are defined.

### File structure

All of the required fields in the structure (and sub-structures) of
`FileMetaData` must be set according to the specification.
The following page types are supported:
* Data page V1 (see `DataPageHeader`)
* Dictionary page (see `DictionaryPageHeader`)

**TODO**: list optional fields that must be filled properly.

### Types

#### Primitive types

The following [primitive types](README.md#types) are supported
* `BOOLEAN`
* `INT32`
* `INT64`
* `FLOAT`
* `DOUBLE`
* `BYTE\_ARRAY`
* `FIXED\_LEN\_BYTE\_ARRAY`

NOTE: The primitive type `INT96` is deprecated so it is intentionally not listed
here.

#### Logical types

The [logical type](LogicalTypes.md)s are practically annotations helping to
understand the related primitive type (or structure). Originally we have had
the `ConvertedType` enum in the thrift file representing all the possible
logical types. After a while we realized it is hard to extend and so introduced
the `LogicalType` union. For backward compatibility reasons we allow to use the
old `ConvertedType` values according to the specified rules but we expect that
the logical types in the file schema are defined with `LogicalType` objects.

The following LogicalTypes are supported:
* `STRING`
* `MAP`
* `LIST`
* `ENUM`
* `DECIMAL` (for which primitives?)
* `DATE`
* `TIME`: **(Which unit, utc?)**
* `TIMESTAMP`: **(Which unit, utc?)**
* `INTEGER`: (all bitwidth 8, 16, 32, 64) **(unsigned?)**
* `UNKNOWN` **(?)**
* `JSON` **(?)**
* `BSON` **(?)**
* `UUID` **(?)**

NOTE: The old ConvertedType `INTERVAL` has no representation in LogicalTypes.
This is becasue `INTERVAL` is deprecated so we do not include it in this list.

### Encodings

The following encodings are supported:
* [PLAIN](Encodings.md#plain-plain--0)  
  parquet-mr: Basically all value types are written in this encoding in case of
  V1 pages
* [PLAIN\_DICTIONARY](Encodings.md#dictionary-encoding-plain_dictionary--2-and-rle_dictionary--8)
  **(?)**  
  parquet-mr: As per the spec this encoding is deprecated while we still use it
  for V1 page dictionaries.
* [RLE](Encodings.md#run-length-encoding--bit-packing-hybrid-rle--3)  
  parquet-mr: Used for both V1 and V2 pages to encode RL and DL and for BOOLEAN
  values in case of V2 pages
* [DELTA\_BINARY\_PACKED](Encodings.md#delta-encoding-delta_binary_packed--5)
  **(?)**  
  parquet-mr: Used for V2 pages to encode INT32 and INT64 values.
* [DELTA\_LENGTH\_BYTE\_ARRAY](Encodings.md#delta-length-byte-array-delta_length_byte_array--6)
  **(?)**  
  parquet-mr: Not used directly
* [DELTA\_BYTE\_ARRAY](Encodings.md#delta-strings-delta_byte_array--7)
  **(?)**  
  parquet-mr: Used for V2 pages to encode BYTE\_ARRAY and
  FIXED\_LEN\_BYTE\_ARRAY values
* [RLE\_DICTIONARY](Encodings.md#dictionary-encoding-plain_dictionary--2-and-rle_dictionary--8)
  **(?)**  
  parquet-mr: Used for V2 page dictionaries
* [BYTE\_STREAM\_SPLIT](Encodings.md#byte-stream-split-byte_stream_split--9)
  **(?)**  
  parquet-mr: Not used by default; can be used only via explicit configuration

NOTE: [BIT\_PACKED](Encodings.md#bit-packed-deprecated-bit_packed--4) is
deprecated and not used directly (boolean values are encoded with this under
PLAIN) so not included in this list.

**TODO**: In parquet-mr dictionary encoding is not enabled for
FIXED\_LEN\_BYTE\_ARRAY in case of writing V1 pages. I don't know the reason
behind. Any experience/idea about this from other implementations?

### Compression

The following compression algorithms are supported (including `UNCOMPRESSED`).
* `SNAPPY`
* `GZIP`
* `LZO` **(?)**
* `BROTLI` **(?)**
* `LZ4` **(?)**
* `ZSTD` **(?)**

### Statistics

However understanding statistics is not crucial to read the data in a file we
still list these features as wrongly specified/implemented statistics can still
cause losing data unnoticed.
The following features related to statistics are supported.
* The row group level min/max values: The fields `min\_value` and `max\_value`
  shall be used in the `Statistics` object according to the specification
* [Column Index](PageIndex.md)

NOTE: Writing page level statistics to the data page headers is not required.

The list of `column\_orders` in `FileMetaData` must be set according to the
notes. See the special handlings required for floating point numbers at
`ColumnOrder`.

