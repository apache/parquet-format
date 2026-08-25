/**
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements.  See the NOTICE file
 * distributed with this work for additional information
 * regarding copyright ownership.  The ASF licenses this file
 * to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance
 * with the License.  You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

/**
 * Modular Footer: a struct-of-arrays (SoA) encoding of Parquet file metadata.
 *
 * STATUS: proposal / draft for discussion.
 *
 * The standard footer (parquet.thrift FileMetaData) is an array of structs, one ColumnChunk per
 * (row group, column). Thrift-compact has no random access into it: even a parser that skips the
 * field values it does not need must still walk every field header in order, so reaching a
 * projected column means traversing all num_columns * num_row_groups chunks. The cost scales with
 * table width, not projection. Interleaving each chunk's heterogeneous fields in one struct also
 * packs and decodes worse than storing each field as its own homogeneous array.
 *
 * The modular footer groups the metadata into independently decodable modules and stores each
 * module column-major, so a reader decodes only the columns, and only the modules, a query needs.
 *
 * Module layout. Each module is serialized as an independent Thrift-compact struct. The
 * ModularFooter index carries only the footer-level scalars and a directory locating every module
 * by absolute file offset, so any module can be placed anywhere in the file. Nothing is inlined:
 * schema and placement are always present but, like the optional modules, are reached through the
 * directory. See ModularFooterDirectoryEntry and PageIndexDirectory for the mechanics.
 *
 * This file defines only the metadata, not the file-level framing that wraps it (the magic, footer
 * location, and any checksum, the analog of Parquet's PAR1 + footer length). The framing is
 * specified separately.
 *
 * Compatibility. The modular footer is a forward-incompatible layout: an old reader cannot parse
 * it in place of FileMetaData. Parquet versioning handles this by signalling a breaking footer
 * layout change at the file level, so an unaware reader rejects the file cleanly rather than
 * misreading it.
 *
 * Adoption. The target end state is the modular footer as the sole footer, which is what delivers
 * the full footer-size and projection-scaling benefit. During migration it may instead be written
 * alongside the standard footer so an unaware reader falls back to FileMetaData; that transitional
 * coexistence is out of scope here.
 *
 * Extensibility. Optional modules are per-file presence flags in the directory, not a migration
 * state. A new module type is added as a directory entry under a version bump, and a reader treats
 * an absent or unrecognized module uniformly, so the format never sits in a partially migrated
 * state. Bloom filters are a planned future module added this way (not specified in this draft).
 *
 * Encryption. Footer encryption is unchanged in spirit: the footer key encrypts all modules.
 * Per-column encryption differs from today's whole-ColumnMetaData scheme. Because placement and
 * statistics are separate modules, and placement is a shared column-major array whose single-column
 * value cannot be encrypted under a per-column key, only the per-column statistics are encrypted
 * (under the column key) while placement stays plaintext. A column's location leaks little; its
 * min/max are the sensitive part. The full modular-encryption design is specified separately.
 *
 * Indexing. The whole-file column-major modules (placement and stats) store each per-chunk array
 * column-major: the value for (leaf column c, row group g) is at index c * num_row_groups + g, so
 * a column's per-row-group values are contiguous. The page index does not use this index; it is
 * split into one blob per column chunk (OffsetIndexChunk, ColumnIndexChunk), each holding just that
 * chunk's per-page arrays, located per chunk through a PageIndexDirectory.
 *
 * Every value array is full-length and positional: exactly one entry per chunk (or per page, for
 * the page index) at its index, addressed directly. Because a positional array cannot tell a
 * genuine 0 (or empty bytes) from an unset value, an optional field pairs its value array with a
 * presence bitset (has_null_count, has_minmax, and so on) recording which entries are actually set;
 * this restores the optional/absent semantics the array-of-structs footer gets from Thrift field
 * presence. The slot at the aligned index still exists when the bit is 0 (a zero under fixed-width
 * BITPACK, an empty element in VarLenColumn). Values
 * are never compacted to present-only, which would force a popcount over the bitset and destroy
 * O(1) random access. Arrays marked "per column" hold num_columns entries indexed by c; arrays
 * marked "per schema element" follow FileMetaData.schema pre-order. Integer arrays are stored as
 * `binary` under one encoding chosen for the whole footer (the ColumnArrayEncoding enum below);
 * variable-length byte columns (stat min/max and their prefixes) use VarLenColumn so they are
 * random-accessible too.
 */

include "parquet.thrift"

namespace cpp parquet.modular
namespace java org.apache.parquet.format.modular

/**
 * Identifies a module. Every module is located through the directory by absolute file offset;
 * nothing is carried inline. SCHEMA and PLACEMENT are always present (the directory always has an
 * entry for each); ROW_GROUP_STATS, OFFSET_INDEX, COLUMN_INDEX, and FILE_METADATA are optional and
 * present only when the directory lists them. (Bloom filters are a planned future module, per the
 * extensibility note above, and get an enum value when specified.)
 */
enum ModularFooterModule {
  SCHEMA = 0;
  PLACEMENT = 1;
  ROW_GROUP_STATS = 2;
  OFFSET_INDEX = 3;
  COLUMN_INDEX = 4;
  FILE_METADATA = 5;
}

/**
 * Encoding of the footer's per-chunk and per-column integer arrays. One encoding is chosen for the
 * whole footer and named once (ModularFooter.array_encoding); every encoded array uses it, there is
 * no per-array tag, and a reader MUST reject an unknown value. The shared tag fixes the scheme, not
 * a bit width: under BITPACK each array carries its own bit_width in its payload, sized to that
 * array's values, so widths differ across arrays and per-column blobs.
 *
 * All encoded values are non-negative. An array with an "absent" case (e.g. null_count) is paired
 * with a presence bitset (e.g. has_null_count), so the value array never needs a negative sentinel
 * and BITPACK stays a clean unsigned width. Variable-length byte blobs (min/max stat bytes) and
 * boolean flag bytes are not integer arrays and are stored as-is; the schema arrays are read
 * wholesale and stay plain Thrift lists.
 *
 * Each encoded array is a self-describing `binary` payload (little-endian; varint = unsigned
 * LEB128):
 *   BITPACK (0): `u8 bit_width; varint count`, then `count` values packed bit_width bits each,
 *   LSB-first. bit_width is per payload (each array picks its own minimal width). O(1) random
 *   access: value i is the bit_width-bit field at bit offset i * bit_width.
 * Design goals for the array encoding, in priority order: (1) RANDOM ACCESS: a projection or a
 * predicate must reach one column's slice in O(1) without decoding the rest, so any encoding added
 * here must keep per-element addressability (BITPACK's fixed bit width; a checkpoint directory for a
 * delta or variable-length scheme; etc.). (2) ALIGN WITH PARQUET: prefer the encoding families
 * parquet.thrift already defines (RLE/bit-packing, DELTA_BINARY_PACKED, BYTE_STREAM_SPLIT) over
 * bespoke schemes, so readers and writers reuse existing machinery and the format stays familiar.
 * (3) MINIMAL SIZE: the footer is fetched cold on every open, so bytes matter, but never at the cost
 * of goal (1).
 *
 * BITPACK is the only encoding today: it is the simplest scheme that meets goals (1) and (2), and
 * this proposal deliberately keeps that single scheme rather than committing to a more complex one
 * before there is evidence. Real footers already show where a better encoding could help. On a
 * fleet parquet-mr footer (29,322 leaf columns, 78 row groups, ~2.29M chunks), min/max was present
 * on under 1% of chunks, yet the full-length VarLenColumn keeps an offset slot per chunk regardless,
 * so its min/max offset arrays cost ~10 MB to index ~0.44 MB of actual values; null_count, by
 * contrast, was dense and packed efficiently. Sparse gated columns like this, and numeric columns
 * whose offsets are derivable from a fixed width, are where a present-only, delta, or fixed-width
 * variant would shrink the footer at equal random-access cost.
 *
 * Rather than pick a winner now, the tag stays pluggable and we gather evidence: by replaying real
 * fleet queries we can re-encode the SAME real footers under candidate encodings and measure
 * cold-read size and decode cost across the actual workload, then propose the best-supported
 * encoding as a new enum value. Because the encoding is a self-describing tag, adopting it is
 * additive: no re-encoding of existing data and no footer-version bump.
 */
enum ColumnArrayEncoding {
  BITPACK = 0;
}

/**
 * A variable-length byte column stored for random access. A Thrift list<binary> is sequential
 * (reaching element i means walking every element before it), which breaks column-selective
 * decode. Instead `data` concatenates all elements in column-major order and `offsets` is an
 * encoded array of count+1 cumulative byte positions (offsets[0] = 0, offsets[count] =
 * length(data)); element i is data[offsets[i] : offsets[i+1]]. Because `offsets` uses
 * array_encoding, under BITPACK a reader jumps straight to element i's bounds in O(1). Used for the
 * column-major byte columns (stat min/max values and their common prefixes). The column is
 * full-length: one element per chunk or page at its column-major index, with an empty element
 * (offsets[i] == offsets[i+1]) where the gating presence bit is 0. It keeps a slot for every entry
 * rather than storing only the present ones, so element i is always at index i.
 */
struct VarLenColumn {
  /** Encoded per array_encoding: count+1 cumulative byte offsets into `data`. */
  1: required binary offsets;
  /** Concatenated element bytes, in the column's column-major order. */
  2: required binary data;
}

// Boolean columns below are packed bitsets, not list<byte>: a `binary` of ceil(count/8) bytes where
// entry i is bit i (LSB-first within each byte). One bit per entry, O(1) random-accessible, at 1/8
// the size of a byte-per-entry list. (Thrift has no bit type; the `binary` carries the packed bits,
// and the entry count comes from the module's chunk or page count.) A bitset is used two ways: as
// boolean data (e.g. null_pages, is_fully_dict_encoded), and as a presence flag gating a paired
// value array (e.g. has_null_count marks which null_counts entries are set).

/**
 * Schema module: parallel arrays, one entry per schema element in the pre-order flattened tree
 * (same order as FileMetaData.schema). Enum-valued columns use i32 with a sentinel for "absent"
 * because group nodes lack some attributes. The schema needs no random access: every reader fully
 * decodes the whole tree (it is required to interpret any projected column), so these stay plain
 * Thrift lists rather than the random-access `binary` encoding the per-chunk modules use, and keep
 * their negative "absent" sentinels.
 */
struct SchemaMatrix {
  /** Path segment name of the element. */
  1: required list<string> names;
  /** parquet.Type value for leaves; -1 for group nodes. */
  2: required list<i32> physical_types;
  /** parquet.FieldRepetitionType value; -1 if absent. */
  3: required list<i32> repetition_types;
  /** Number of children; -1 for leaves (distinguishes a leaf from a 0-child group). */
  4: required list<i32> num_children;
  /** Length for FIXED_LEN_BYTE_ARRAY; -1 otherwise. */
  5: required list<i32> type_lengths;
  /** Field id; -2147483648 (min i32) if unset. */
  6: required list<i32> field_ids;
  /** Logical type; an empty union means none. Decimals etc. carried here. */
  7: required list<parquet.LogicalType> logical_types;
  /** parquet.ColumnOrder, one per element (empty union = unset, group node, or type-defined order).
   *  Required to interpret min/max stats, e.g. float NaN and signed-zero ordering. */
  8: required list<parquet.ColumnOrder> column_orders;
}

/**
 * Placement module (always present): per-(leaf column, row group) chunk locators, column-major
 * (chunk (c, g) at index c * num_row_groups + g). Per chunk unless a field notes otherwise; every
 * numeric array is BITPACK-encoded (per array_encoding) for column-selective random access, so a
 * projection decodes only its columns' slices instead of the whole module.
 *
 * Multiple dictionary pages per chunk. Instead of one dictionary_page_offset per chunk,
 * dictionary_page_offsets is a single flattened array of every dictionary-page offset, and
 * first_dict_page is a per-chunk cumulative index into it (CSR-style). Chunk k's dictionary pages
 * are the slice dictionary_page_offsets[first_dict_page[k] : first_dict_page[k+1]], so a chunk may
 * carry zero, one, or several dictionary pages, each located in O(1). This is why the footer does
 * not bake in today's one-dictionary-per-chunk rule: a future multi-dictionary feature needs no
 * format change, only more entries in the flat array.
 */
struct ColumnChunkMatrix {
  /** First data page byte offset, per (column, row group), column-major. Encoded. */
  1: required binary data_page_offsets;
  /** Per-chunk cumulative index into dictionary_page_offsets: num_chunks+1 entries with
   *  first_dict_page[num_chunks] = total. Chunk k's dictionary pages are the slice
   *  dictionary_page_offsets[first_dict_page[k] : first_dict_page[k+1]]; the page count is the
   *  difference (0 = no dictionary), found in O(1) with no prefix sum and no sentinel.
   *  Column-major. Encoded. */
  2: required binary first_dict_page;
  /** Byte offset of every dictionary page, flattened in column-major chunk order (then page order
   *  within a chunk) and sliced per chunk by first_dict_page. Holds all of a chunk's dictionary
   *  pages, so multiple per chunk are supported without a format change. Encoded. */
  3: required binary dictionary_page_offsets;
  /** Compressed size of the column chunk. Encoded. */
  4: required binary total_compressed_sizes;
  /** Uncompressed size of the column chunk. Encoded. */
  5: required binary total_uncompressed_sizes;
  /** Number of values in the column chunk. Encoded. */
  6: required binary num_values;
  /** parquet.CompressionCodec value. Encoded. */
  7: required binary codecs;
  /** parquet.Type value; one entry per column, uniform across row groups (the noted exception to
   *  per-chunk). Encoded. */
  8: required binary physical_types;
  /** Packed bitset, one bit per chunk: 1 iff every data page in the chunk is dictionary-encoded.
   *  Replaces ColumnMetaData.encoding_stats. encoding_stats was a variable-length
   *  list<PageEncodingStats> per chunk (encoding, page type, and counts) that does not fit the
   *  fixed-width column-major layout and carries far more than readers use. The single fact the
   *  fast path needs is whether the whole chunk is dictionary-encoded -- so filters and aggregations
   *  can run directly on dictionary codes without materializing values -- and one bit captures it.
   *  Per chunk, column-major. */
  9: required binary is_fully_dict_encoded;
}

/**
 * Statistics module: per-(leaf column, row group) chunk statistics for row-group pruning,
 * column-major. Mirrors parquet.Statistics min_value/max_value/null_count with two space
 * optimizations: the longest common prefix of a chunk's min and max is stored once (min/max keep
 * only the differing suffix), and either bound may be truncated and flagged inexact (an inexact min
 * stays a valid lower bound, <= true min; an inexact max a valid upper bound, >= true max), so
 * pruning stays correct while long values do not bloat the footer.
 *
 * All-NaN chunks: a chunk whose non-null values are all NaN carries no ordering min/max. A reader
 * detects this via nan_count + null_count == num_values (num_values from ColumnChunkMatrix), and
 * such a chunk MAY set has_minmax = 0. The column index cannot use this test (it has no per-page
 * num_values), so it signals the all-NaN case differently (see ColumnIndexChunk).
 */
struct RowGroupStatsMatrix {
  /** Packed bitset: 1 iff the null count is known. Per chunk, column-major. */
  1: required binary has_null_count;
  /** Null count, non-negative; encoded. Meaningful iff has_null_count. */
  2: required binary null_counts;
  /** Packed bitset: 1 iff this chunk has min/max (min/max entries below meaningful iff 1). */
  3: required binary has_minmax;
  /** Longest common prefix of each chunk's min and max (empty if none), column-major. */
  4: required VarLenColumn minmax_prefixes;
  /** Each chunk's min with minmax_prefixes stripped (suffix only), column-major. */
  5: required VarLenColumn min_suffixes;
  /** Each chunk's max with minmax_prefixes stripped (suffix only), column-major. */
  6: required VarLenColumn max_suffixes;
  /** Packed bitset: 1 iff min is exact; 0 iff a truncated lower bound (<= true min).
   *  Meaningful iff has_minmax. */
  7: required binary min_exact;
  /** Packed bitset: 1 iff max is exact; 0 iff a truncated upper bound (>= true max).
   *  Meaningful iff has_minmax. */
  8: required binary max_exact;
  /** Packed bitset: 1 iff the NaN count is known (mandatory for float types under total order). */
  9: required binary has_nan_count;
  /** NaN count, non-negative; encoded. Meaningful iff has_nan_count. FLOAT/DOUBLE/FLOAT16 only. */
  10: required binary nan_counts;
}

/**
 * Offset-index module (optional, per-page placement): a separate, independent module from the
 * column index. The OFFSET_INDEX directory entry locates a PageIndexDirectory (the per-chunk
 * locator), not these blobs; the reader follows that directory's per-chunk offset to fetch one
 * OffsetIndexChunk per projected (column, row group) chunk. A chunk with no offset index has an
 * empty slice in the directory.
 *
 * Each OffsetIndexChunk holds one column chunk's pages (one per (leaf column, row group)); the
 * per-page arrays are parallel and self-delimiting, so their common length is the chunk's page
 * count and no separate page-count field is stored. Equivalent to parquet.thrift OffsetIndex (SoA).
 */
struct OffsetIndexChunk {
  /** Page byte offset. Encoded. */
  1: required binary offsets;
  /** Compressed page size. Encoded. */
  2: required binary compressed_page_sizes;
  /** First row index of the page within its row group. Encoded. */
  3: required binary first_row_indexes;
}

/**
 * Column-index module (optional, per-page statistics): a separate, independent module from the
 * offset index. As with the offset index, the COLUMN_INDEX directory entry locates a
 * PageIndexDirectory (the per-chunk locator), not these blobs; a chunk with no column index has an
 * empty slice there, so a chunk may have an offset index but no column index without either module
 * referencing the other. Equivalent to parquet.thrift ColumnIndex, transposed to SoA; this version
 * omits the optional repetition/definition level histograms and unencoded_byte_array_data_bytes.
 * Per-page min/max use the same prefix + inexact scheme as RowGroupStatsMatrix (common prefix stored
 * once, truncated bounds flagged and still valid).
 *
 * null_pages is the min/max presence gate (there is no separate has_minmax): every non-null page
 * carries min/max, and where null_pages[i] = 1 the page is all-null, so its minmax_prefixes[i],
 * min_suffixes[i], and max_suffixes[i] are empty and its min_exact[i] and max_exact[i] are
 * meaningless (the per-page null and nan counts remain valid).
 *
 * All-NaN pages: with no per-page num_values, a reader cannot use the RowGroupStatsMatrix test
 * (nan_count + null_count == num_values) to spot a page whose non-null values are all NaN. Instead
 * the writer MUST record the actual NaN min/max for such a page (min/max are not dropped), and a
 * reader that sees a NaN min/max treats the page's non-null values as all NaN.
 *
 * Each ColumnIndexChunk holds one column chunk's pages; the per-page arrays are parallel and their
 * common length is the chunk's page count (no separate page-count field).
 */
struct ColumnIndexChunk {
  /** parquet.BoundaryOrder for this chunk: whether the pages are ordered, enabling binary-search
   *  page skipping. */
  1: required parquet.BoundaryOrder boundary_order;
  /** Packed bitset, one bit per page: 1 iff the page is all-null. */
  2: required binary null_pages;
  /** Packed bitset, per page: 1 iff the per-page null count is known. */
  3: required binary has_null_count;
  /** Per-page null count, non-negative; encoded. Meaningful iff has_null_count. */
  4: required binary null_counts;
  /** Longest common prefix of each page's min and max (empty if none), per page. */
  5: required VarLenColumn minmax_prefixes;
  /** Per-page min with minmax_prefixes stripped (suffix). */
  6: required VarLenColumn min_suffixes;
  /** Per-page max with minmax_prefixes stripped (suffix). */
  7: required VarLenColumn max_suffixes;
  /** Packed bitset, per page: 1 iff the min is exact; 0 iff a truncated lower bound. */
  8: required binary min_exact;
  /** Packed bitset, per page: 1 iff the max is exact; 0 iff a truncated upper bound. */
  9: required binary max_exact;
  /** Packed bitset, per page: 1 iff the per-page NaN count is known. */
  10: required binary has_nan_count;
  /** Per-page NaN count, non-negative; encoded. Meaningful iff has_nan_count. */
  11: required binary nan_counts;
}

/**
 * File-level metadata module (optional): descriptive metadata a reader does not need to navigate
 * the footer, namely the writer identity and the arbitrary key/value pairs (Arrow, Spark, or Delta
 * schema, geo metadata, and so on). Read wholesale (small, never projected) and located via the
 * directory.
 */
struct FileMetadataMatrix {
  /** Writer identity (like FileMetaData.created_by); lets readers gate on known-bad stats. */
  1: optional string created_by;
  /** Arbitrary key/value metadata (as FileMetaData.key_value_metadata). Read wholesale, so it stays
   *  a plain list rather than a column-major SoA structure. */
  2: optional list<parquet.KeyValue> key_value_metadata;
}

/**
 * Per-chunk locator at the base of a page-index region (offset index or column index). The module's
 * directory entry addresses this locator, and its (offset, length) spans the whole region (this
 * directory followed by the per-chunk blobs). A reader fetches it once, then uses chunk_offsets to
 * fetch only the projected chunks' OffsetIndexChunk or ColumnIndexChunk blobs.
 *
 * chunk_offsets holds num_chunks+1 cumulative byte offsets relative to the region base,
 * column-major (chunk (c, g) at index c * num_row_groups + g), so that chunk's blob is
 * [region_base + chunk_offsets[k], region_base + chunk_offsets[k+1]): one integer per chunk, no
 * separate length, and an empty slice for a chunk absent from the module. A whole column's chunks
 * are contiguous, so a reader can also range-fetch a column in one read.
 */
struct PageIndexDirectory {
  /** Encoded per array_encoding (see above). */
  1: required binary chunk_offsets;
}

/**
 * One entry of the footer directory, locating a module's serialized bytes by absolute file offset.
 * For OFFSET_INDEX and COLUMN_INDEX the offset points to the module's PageIndexDirectory (the
 * per-chunk locator), not the page data.
 */
struct ModularFooterDirectoryEntry {
  1: required ModularFooterModule module;
  /** Absolute byte offset of the module in the file. For OFFSET_INDEX and COLUMN_INDEX it is the
   *  page-index region base that PageIndexDirectory.chunk_offsets are relative to. */
  2: required i64 offset;
  /** Byte length of the module (for the page index, the region: PageIndexDirectory + blobs). */
  3: required i64 length;
}

/**
 * Top-level footer index (the always-read skeleton): the footer-level scalars plus a directory
 * locating every module. No module is carried inline. SchemaMatrix and ColumnChunkMatrix
 * (placement) are always present, so `directory` always has an entry for each; the remaining
 * modules (RowGroupStatsMatrix, the page index, file metadata) are listed only when present. Each
 * module is serialized independently and reached through `directory`, so a reader decodes only the
 * modules it needs, and every module's column-major arrays stay independently walkable so a
 * projection touches only its columns' slices. version identifies the metadata layout (like
 * FileMetaData.version); which modules are present is given by `directory`.
 */
struct ModularFooter {
  /** Metadata layout version (analogous to FileMetaData.version). */
  1: required i32 version;
  2: required i32 num_row_groups;
  3: required i32 num_columns;            // leaf columns
  4: required i64 num_rows;               // file total
  5: required list<i64> row_group_num_rows;
  /** Encoding shared by every encoded array in this footer. BITPACK is the only value today. */
  6: required ColumnArrayEncoding array_encoding;
  /** Locates every module by absolute file offset. Always includes SCHEMA and PLACEMENT (both
   *  always present); the other modules appear only when present. Nothing is inlined. */
  7: required list<ModularFooterDirectoryEntry> directory;
}
