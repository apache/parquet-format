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

# Modular footer array pages

---
Author: Jiayi Wang
Created: 2026-08-28
Name: Encode modular-footer arrays as independently framed metadata pages
Issue: https://github.com/apache/parquet-format/issues/530
Status: DRAFT
---

## Description

This proposal changes the physical representation of arrays in the modular footer. Each logical
array is stored as an independently framed **metadata page**:

```text
[compact-Thrift MetadataPageHeader][raw uncompressed payload]
```

The normative Thrift definitions are in
[`ModularFooterArrayPages.thrift`](../src/main/thrift/ModularFooterArrayPages.thrift).

The payload is not a Thrift `binary` field. The header identifies its meaning, value type,
encoding, logical cardinality, and byte length. A footer directory locates metadata pages by file
offset. This is the same separation used by Parquet data pages: Thrift describes a page, while the
encoding named by the header defines its payload.

Metadata pages do not change the modular footer's logical organization. Schema, placement,
row-group statistics, offset indexes, column indexes, and file metadata remain independent modules
with their existing read lifecycles. A metadata page contains one struct-of-arrays field within one
of those modules; it never combines fields from different modules.

The initial format defines two array encodings:

* `BIT_PACKED`, for dense positional arrays.
* `SPARSE`, for arrays in which relatively few logical positions have values.

Neither encoding applies general-purpose compression.

## Rationale

Compact Thrift is well suited to schemas, small control structures, and compatible evolution, but
its lists are sequential. Finding element `i` in a `list<i64>` requires parsing elements `0` through
`i - 1`, because compact integers have variable width. The modular footer needs a projected reader
to reach column `c` without walking metadata for all preceding columns.

Encoding every array as a Thrift `binary` field solves addressability but obscures the format's
layering: most fields appear to be Thrift while their actual type and layout live in prose and
custom decoders. Metadata pages make the boundary explicit. Thrift remains the evolvable control
plane; encoded array pages are the data plane.

This design also avoids coupling placement and statistics. They are separate modules and separate
pages. A reader can locate data pages without reading, understanding, or fetching statistics.

## Logical indexing

Unless a field specifies another domain, per-column-chunk arrays use **chunk space**. For leaf
column `c` and row group `g`, the logical index is:

```text
i = c * num_row_groups + g
```

Therefore all row groups of one leaf column are contiguous. Per-column arrays use `i = c`.
Per-page arrays inside an offset-index or column-index chunk use page ordinal as `i`.

Every page declares `num_values`, the size of its logical domain. A dense page contains a value at
every position. A sparse page contains a sorted subset of positions from that domain. Absence in a
sparse page has the same meaning as absence of the corresponding optional field in the traditional
Thrift footer; it is not a zero or empty value.

## Thrift definitions

The following definitions are added to `ModularFooter.thrift`.

```thrift
/** The semantic module to which an array page belongs. */
enum ModularFooterModule {
  SCHEMA = 0;
  PLACEMENT = 1;
  ROW_GROUP_STATS = 2;
  OFFSET_INDEX = 3;
  COLUMN_INDEX = 4;
  FILE_METADATA = 5;
}

/** Stable identifiers for arrays. Values are never reused for a different meaning. */
enum MetadataArray {
  DATA_PAGE_OFFSET = 0;
  FIRST_DICTIONARY_PAGE = 1;
  DICTIONARY_PAGE_OFFSET = 2;
  TOTAL_COMPRESSED_SIZE = 3;
  TOTAL_UNCOMPRESSED_SIZE = 4;
  NUM_VALUES = 5;
  CODEC = 6;
  PHYSICAL_TYPE = 7;
  IS_FULLY_DICTIONARY_ENCODED = 8;

  NULL_COUNT = 20;
  MIN_VALUE = 21;
  MAX_VALUE = 22;
  MIN_IS_EXACT = 23;
  MAX_IS_EXACT = 24;
  NAN_COUNT = 25;

  PAGE_OFFSET = 40;
  COMPRESSED_PAGE_SIZE = 41;
  FIRST_ROW_INDEX = 42;
  NULL_PAGE = 43;
  BOUNDARY_ORDER = 44;
  /** Cumulative absolute offsets of per-column-chunk metadata page groups. */
  PAGE_GROUP_OFFSET = 45;
}

/** The values exposed after decoding a page. */
enum MetadataValueType {
  BOOLEAN = 0;
  UINT32 = 1;
  UINT64 = 2;
  BYTE_ARRAY = 3;
}

enum MetadataArrayEncoding {
  BIT_PACKED = 0;
  SPARSE = 1;
}

/** The logical domain in which page positions are interpreted. */
enum MetadataPageScope {
  /** File-wide array: chunk space, column space, or another field-defined domain. */
  FILE = 0;
  /** Array over the data pages of one (leaf column, row group) column chunk. */
  COLUMN_CHUNK = 1;
}

/** Parameters for a dense BIT_PACKED payload. */
struct BitPackedEncodingHeader {
  /** Width of each integer, or each BYTE_ARRAY offset, in bits. */
  1: required i8 bit_width;
}

/** Parameters for a SPARSE payload. */
struct SparseEncodingHeader {
  /** Number of positions that are present. */
  1: required i32 num_present;
  /** Width of a logical position in the positions stream. */
  2: required i8 position_bit_width;
  /** Width of each integer value, or each BYTE_ARRAY offset, in bits. */
  3: required i8 value_bit_width;
}

union MetadataEncodingHeader {
  1: BitPackedEncodingHeader bit_packed;
  2: SparseEncodingHeader sparse;
}

/**
 * A MetadataPageHeader is compact-Thrift encoded. The raw payload begins immediately after the
 * struct STOP byte and occupies exactly payload_length bytes. It is not a Thrift binary value.
 */
struct MetadataPageHeader {
  1: required ModularFooterModule module;
  2: required MetadataArray array;
  3: required MetadataValueType value_type;
  4: required MetadataArrayEncoding encoding;
  /** Number of addressable positions, including absent positions in SPARSE. */
  5: required i32 num_values;
  /** Number of raw bytes following this header. */
  6: required i32 payload_length;
  7: required MetadataEncodingHeader encoding_header;
  8: required MetadataPageScope scope;
  /** Required exactly when scope is COLUMN_CHUNK. */
  9: optional i32 column_ordinal;
  /** Required exactly when scope is COLUMN_CHUNK. */
  10: optional i32 row_group_ordinal;
}

/** Locates one complete [MetadataPageHeader][payload] record. */
struct MetadataPageLocation {
  1: required ModularFooterModule module;
  2: required MetadataArray array;
  3: required i64 offset;
  /** Header plus payload bytes. */
  4: required i32 length;
  5: required MetadataPageScope scope;
  /** Required exactly when scope is COLUMN_CHUNK. */
  6: optional i32 column_ordinal;
  /** Required exactly when scope is COLUMN_CHUNK. */
  7: optional i32 row_group_ordinal;
}
```

The page identity `(module, array, scope, column_ordinal, row_group_ordinal)` is repeated in the
page header and directory deliberately. The directory can select a page without parsing it; the
page remains self-describing and can validate that the directory did not address the wrong bytes.
The two ordinals are absent for `FILE` pages. They are both present for `COLUMN_CHUNK` pages and
identify the column chunk whose page-ordinal domain the payload describes.

## Common payload conventions

All payload integers use little-endian bit order. Within each byte, the least-significant bit is
consumed first. A packed stream has no padding between values. The final byte is padded with zero
bits. Readers MUST reject a stream whose unused final bits are nonzero.

The valid width for `UINT32` is 0 through 32 and for `UINT64` is 0 through 64. Width 0 represents an
all-zero stream and consumes no payload bytes. `BOOLEAN` is equivalent to an unsigned integer of
width 1; its encoding header MUST specify width 1.

For a stream of `n` integers with width `w`, its byte length is:

```text
ceil(n * w / 8)
```

All arithmetic used to validate counts and lengths MUST be checked for overflow before allocating
memory or reading bytes.

## BIT_PACKED encoding

`BIT_PACKED` represents a dense positional array.

### Integer and boolean values

The payload is exactly one packed stream of `num_values` values using `bit_width` from
`BitPackedEncodingHeader`:

```text
[value 0][value 1] ... [value num_values-1]
```

Value `i` begins at bit offset `i * bit_width`, providing constant-time access without decoding
preceding values.

Writers MUST choose the minimum width that can represent the largest value. Readers MUST accept a
larger valid width to permit simple writers, but MUST reject a value outside the declared
`MetadataValueType` range.

### BYTE_ARRAY values

The payload has two consecutive regions:

```text
[num_values + 1 packed cumulative offsets][concatenated value bytes]
```

The offsets use `bit_width`. The first offset MUST be zero, offsets MUST be nondecreasing, and the
last offset MUST equal the length of the concatenated bytes region. Value `i` is the byte range
`offset[i] .. offset[i + 1]`.

The offset stream length is derived from `num_values` and `bit_width`; it is not stored separately.

## SPARSE encoding

`SPARSE` represents values at `num_present` positions out of a logical domain of `num_values`.
The payload starts with a packed positions stream:

```text
[num_present positions][num_present values]
```

Positions use `position_bit_width`. They MUST be strictly increasing and each position MUST be less
than `num_values`. Writers MUST use the minimum width capable of representing
`num_values - 1`; when `num_values` is zero, `num_present` MUST also be zero and the width MUST be
zero.

A reader finds logical position `i` by binary-searching the packed positions stream. Fixed-width
packing allows the reader to inspect any position entry without decoding preceding entries. If the
position is absent, the logical value is absent. If it is the `k`th present position, its value is
entry `k` in the values region.

For `UINT32`, `UINT64`, and `BOOLEAN`, the values region is a packed stream of `num_present` values
using `value_bit_width`.

For `BYTE_ARRAY`, the values region is:

```text
[num_present + 1 packed cumulative offsets][concatenated value bytes]
```

The offsets use `value_bit_width` and follow the same validity rules as dense BYTE_ARRAY offsets.
Consequently, after the positions search, both integer and byte-array values are directly
addressable without a prefix scan or rank operation.

`SPARSE` MUST NOT be used merely to encode zero values compactly. A missing position means the
source field was absent; a present value of zero remains present and is encoded in the values
stream.

## Modules and required pages

The modular footer retains its semantic module boundaries:

* `SCHEMA` is required and is read in full. Its tree-shaped fields MAY remain an ordinary compact-
  Thrift `SchemaMatrix`; this proposal does not force non-scalar logical types into array pages.
* `PLACEMENT` is required. Its scalar arrays are metadata pages and normally use `BIT_PACKED`.
  Placement pages are independently locatable from statistics pages.
* `ROW_GROUP_STATS` is optional. `NULL_COUNT`, `MIN_VALUE`, `MAX_VALUE`, and `NAN_COUNT` SHOULD use
  `SPARSE` when their Thrift source fields are not present at every logical position. Exactness
  flags describe present min/max entries and MAY use dense `BIT_PACKED` when that is smaller.
* `OFFSET_INDEX` and `COLUMN_INDEX` are optional and remain independently addressable per column
  chunk. Each array has `COLUMN_CHUNK` scope and uses that chunk's data-page ordinals as its logical
  positions. Their many per-chunk pages are located through the two-level directory described
  below; they are not expanded into the root directory.
* `FILE_METADATA` is read in full and MAY remain an ordinary compact-Thrift structure.

The exact required placement arrays and their semantics remain those specified by the modular
footer data model. This proposal changes their framing and encoding, not their meaning.

The `MIN_VALUE` and `MAX_VALUE` pages for one statistics domain MUST use identical sparse positions.
`MIN_IS_EXACT` and `MAX_IS_EXACT` are defined only at those positions. A writer MUST NOT encode one
bound without the other.

## Directory and footer framing

`ModularFooter` contains the file-level scalars, locations of ordinary Thrift modules, and locations
of file-scoped metadata pages. The root directory is small and is decoded in full. It MUST NOT
contain one entry per column chunk.

```thrift
struct ModularFooter {
  1: required i32 version;
  2: required i32 num_row_groups;
  3: required i32 num_columns;
  4: required i64 num_rows;
  5: required list<i64> row_group_num_rows;
  /** File-scoped pages, including placement, row-group stats, and page-group offset pages. */
  6: required list<MetadataPageLocation> pages;
  7: optional list<ModularFooterDirectoryEntry> thrift_modules;
}
```

### Two-level directory for page indexes

Expanding every offset-index and column-index array page into `ModularFooter.pages` would make the
root proportional to `num_columns * num_row_groups`. Instead, each optional page-index module has
one file-scoped `PAGE_GROUP_OFFSET` page in the root directory. Its dense `UINT64` payload contains
`num_columns * num_row_groups + 1` cumulative absolute file offsets in chunk-space order.

For chunk index `k`, the half-open byte range

```text
page_group_offset[k] .. page_group_offset[k + 1]
```

contains that chunk's `COLUMN_CHUNK`-scoped metadata pages. Equal offsets mean that the chunk has no
index. Within a nonempty group, pages are concatenated in ascending `MetadataArray` order. A reader
parses a page header, uses `payload_length` to skip or consume its payload, and continues until the
group end. Because each group has only the fields of one offset index or column index, this scan is
bounded by the module schema rather than table width.

The `OFFSET_INDEX/PAGE_GROUP_OFFSET` and `COLUMN_INDEX/PAGE_GROUP_OFFSET` pages are distinct because
their `module` values differ. Their own locations are ordinary entries in `ModularFooter.pages`.

This document does not change the outer mechanism that locates `ModularFooter` from the end of the
file. Page and page-group offsets are absolute file offsets, allowing optional modules or large
page-index groups to be stored outside the always-fetched footer tail.

Each `MetadataPageLocation.length` MUST equal the number of bytes consumed while compact-Thrift
decoding its header plus `MetadataPageHeader.payload_length`. Page ranges MUST be within the file
and MUST NOT overlap unless a future version explicitly defines shared pages.

## Reading

To obtain placement for projected leaf column `c`, a reader:

1. Reads the footer index and locates the required placement array pages.
2. Computes the chunk-space range
   `[c * num_row_groups, (c + 1) * num_row_groups)`.
3. Parses each selected page header.
4. Uses the encoding-specific random-access operation for only that range.

No statistics page is required for this operation. A reader that performs row-group pruning locates
the relevant statistics pages separately and looks up the same chunk-space positions.

For a sparse page, lookup is `O(log num_present)` due to the positions search. For a bit-packed
page, lookup is `O(1)`. Neither lookup decodes values belonging to preceding columns.

## Evolution and compatibility

The evolution model is the same as for Parquet data pages:

* Optional additions to `MetadataPageHeader` use normal Thrift field evolution.
* A new logical array receives a new `MetadataArray` value.
* A new payload representation receives a new `MetadataArrayEncoding` value and a corresponding
  `MetadataEncodingHeader` union member.
* Existing encoding values and payload definitions never change meaning.

An implementation that does not recognize a page type or encoding can skip it using the directory
length. If the page belongs to an optional optimization module, the implementation proceeds without
that optimization. If a required schema or placement page is unsupported, the modular footer is
unusable. During a compatibility transition, the reader falls back to the traditional
`FileMetaData`; in a modular-footer-only file, it reports an unsupported-format error.

The modular footer itself is a forward-incompatible footer layout when used as the sole footer.
Metadata-page framing does not add a separate compatibility break beyond that layout change.

## Validation requirements

A conforming reader MUST reject a modular footer when any of the following holds:

* A required schema or placement array page is missing or duplicated.
* A page's directory identity differs from its header identity.
* A page's scope and optional ordinals are inconsistent, or an ordinal is outside the file shape.
* A page-group offset array has the wrong cardinality, is decreasing, or addresses bytes outside
  the file.
* Paired min/max pages have different sparse positions or only one of the pair is present.
* A count, width, or derived length is invalid or overflows.
* A page extends outside its directory range or the file.
* Sparse positions are not strictly increasing or are outside the logical domain.
* BYTE_ARRAY offsets are not nondecreasing or do not terminate at the data length.
* Packed padding bits are nonzero.
* Parallel arrays required by the data model have inconsistent logical cardinalities.

Readers SHOULD impose implementation limits on page count, logical cardinality, and payload length
before allocation. Writers MUST emit pages in canonical `(module, array)` order, although readers
MUST use the directory and MUST NOT depend on physical order.

## Evaluation

The proposal should be evaluated against the current all-`binary` modular-footer representation and
the traditional footer using real files, including very wide files with few row groups and files
with sparse statistics.

The minimum evaluation reports:

* Total footer bytes and always-fetched tail bytes.
* Directory and Thrift-header overhead.
* Time to read placement for 1, 5, and all projected columns.
* Time to read sparse row-group statistics for the same projections.
* Size and lookup cost of `BIT_PACKED` versus `SPARSE` for every eligible array.
* Malformed-input and cross-implementation round-trip tests.

Success means that array pages retain projection-scaled access and approximately the same encoded
size as the current specialized representation, while leaving page identity, encoding selection,
and future extension in explicit Thrift headers rather than implicit `binary` fields.

## Open questions

1. Should page locations be one flat list or grouped into per-module directories?
2. Should `MetadataArray` be one global enum or a module-specific field id namespace?
3. Should writers choose `BIT_PACKED` versus `SPARSE` independently for every page, or should the
   specification prescribe a deterministic size threshold?
4. Should optional exactness flags share the sparse position stream of their min/max values, or be
   independent pages?
5. What limits on page count and payload size should be normative rather than implementation
   guidance?
