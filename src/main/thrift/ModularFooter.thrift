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
 * Modular Footer: typed Thrift modules whose array fields hold their encoded values inline.
 *
 * EncodedArray carries an array's encoded bytes inline in its values field (and, when the array is
 * not fully present, its presence structure in a second field), with only the encoding tag and the
 * logical domain size beside them as typed fields. Every other parameter -- bit widths, present
 * counts, position widths -- lives inside the encoded bytes, defined per encoding (see
 * ArrayEncoding), the way a Parquet data page carries its encoding's parameters inside the page
 * rather than in the page header. The typed field containing an EncodedArray defines the values'
 * meaning, type, and logical domain; EncodedArray defines only their physical encoding.
 *
 * Modules preserve independent read lifecycles. A reader can fetch placement without fetching
 * row-group statistics. Schema and descriptive file metadata remain ordinary Thrift data because
 * readers consume them in full.
 *
 * The outer file framing that locates ModularFooter from the end of a file is specified separately.
 */

include "parquet.thrift"

namespace cpp parquet.modular
namespace java org.apache.parquet.format.modular

/**
 * Footer array encodings.
 *
 * An EncodedArray is a homogeneous, positionally indexed column of metadata values. Every footer
 * encoding MUST satisfy: (1) positional random access -- O(1) for fixed-width, O(log P) select for
 * sparse -- so a reader reaches one position without decoding the others; (2) no compression and no
 * cross-value dependence that would prevent seeking; (3) self-delimiting from (bytes, num_values)
 * alone; (4) fully pinned bit and byte order and padding; (5) defined behaviour for the degenerate
 * cases (num_values == 0, all present, all absent, value_bit_width 0..64).
 *
 * Encoding PARAMETERS (bit widths, present counts, position widths) live INLINE in the encoded
 * bytes, defined per encoding below -- not as Thrift fields. This is the same division a Parquet
 * data page uses: the header carries the encoding and value count, the encoded bytes carry the
 * encoding's own parameters. Adding an encoding is therefore a new enum value plus a byte-layout
 * entry here; the structs below never change. A reader that meets an ArrayEncoding it does not
 * implement MUST reject the file, or skip the whole module when that module is optional -- it must
 * never guess.
 *
 * All bit-packing is fixed-width and LSB-first: the order used by Parquet's RLE/Bit-Packing Hybrid,
 * not the deprecated MSB-first BIT_PACKED encoding. It is that hybrid's bit-packing primitive
 * emitted as a single un-framed run -- no run headers and no run-length structure -- so element i is
 * always at bit i * value_bit_width. Relationship to Parquet's data-page encodings: BITSET is PLAIN
 * generalized from fixed byte widths to the minimum bit width (a PLAIN boolean is BITSET at width
 * 1), so it subsumes PLAIN; the sequential encodings (RLE, RLE_DICTIONARY, DELTA_BINARY_PACKED,
 * DELTA_BYTE_ARRAY, BYTE_STREAM_SPLIT, and PLAIN for BYTE_ARRAY) are excluded because they cannot
 * seek. Definition levels (presence) are re-encoded here as the validity bitmap or PRESENT_INDEX;
 * repetition/list structure, where it exists (dictionary pages per chunk, variable-length byte
 * values), is carried by cumulative-offset arrays rather than by Dremel level streams.
 */
enum ArrayEncoding {
  /**
   * Fixed-width bit-packed values with direct positional access.
   *   values   = [u8 value_bit_width][num_values values, value_bit_width bits each, LSB-first]
   *   presence : OMITTED         -> every position is present (dense; the common case)
   *              validity bitmap -> ceil(num_values / 8) bytes, bit i set iff position i is present;
   *                                 the value stream stays full-length and an absent slot holds an
   *                                 unspecified placeholder the reader must not use.
   * value(i) is bits [i * value_bit_width, (i + 1) * value_bit_width) of the packed region. O(1).
   * Best from fully dense to moderately sparse.
   */
  BITSET = 0,
  /**
   * Present-only values plus a sorted index of the present positions; absent positions take no slot.
   *   presence = [varint num_present][u8 position_bit_width]
   *              [num_present sorted positions, position_bit_width bits each, LSB-first]
   *   values   = [u8 value_bit_width][num_present values, value_bit_width bits each, LSB-first]
   * value(pos): binary-search presence for pos -> j; absent if not found, else read value j from the
   * packed region. O(log num_present). Smaller than BITSET only in the very-sparse tail, where
   * BITSET's full-length value stream would spend most of its slots on absent positions.
   */
  PRESENT_INDEX = 1
  // A new encoding is one new value here plus a byte-layout entry above. No struct below changes.
}

/**
 * One encoded array, stored inline. values and, when the array is not fully present, presence are
 * opaque byte blobs whose layout is defined entirely by encoding (see ArrayEncoding). Thrift's
 * binary framing self-delimits both, so no byte-length fields are needed.
 *
 * num_values is the size of the complete logical domain, including absent positions. The containing
 * typed module field defines whether values are BOOLEAN, UINT32, UINT64, or BYTE_ARRAY and defines
 * the logical indexing domain.
 *
 * For a BYTE_ARRAY column, values is [u8 offset_bit_width][count + 1 cumulative byte offsets]
 * [concatenated bytes], where count is num_values (dense) or num_present (sparse) and element i is
 * bytes[off[i] : off[i + 1]]. Those cumulative offsets encode each value's length; they are not a
 * repetition level, because the column is one value per position, not a repeated field.
 */
struct EncodedArray {
  /** Logical domain size: number of positions, absent ones included. Encoding-independent. */
  1: required i32 num_values,
  /** Encoded values; layout defined by encoding, carrying its own width byte inline. */
  2: required binary values,
  /** BITSET when omitted. */
  3: optional ArrayEncoding encoding,
  /**
   * Definition-level structure (a validity bitmap for BITSET, the sorted present positions for
   * PRESENT_INDEX); layout per encoding. Omitted for a fully-present BITSET.
   */
  4: optional binary presence
}

/** Absolute location of one independently compact-Thrift serialized module. */
struct ModuleLocation {
  1: required i64 offset,
  2: required i64 length
}

/** Schema is tree-shaped and read in full, so it remains ordinary Thrift data. */
struct SchemaModule {
  1: required list<parquet.SchemaElement> schema,
  2: optional list<parquet.ColumnOrder> column_orders
}

/**
 * Placement for every column chunk, plus the per-row-group row counts.
 *
 * Unless noted otherwise, arrays hold num_columns * num_row_groups UINT64 values in column-major
 * chunk space: chunk (column c, row group g) is at c * num_row_groups + g. Every column chunk has a
 * value, so these required arrays use the fully-present (dense) case of BITSET. Two arrays use a
 * different logical domain, noted on the field: physical_types is one entry per leaf column, and
 * row_group_num_rows is one entry per row group.
 */
struct PlacementModule {
  /** UINT64: first data-page byte offset. */
  1: required EncodedArray data_page_offsets,
  /** UINT64: num_chunks + 1 cumulative indexes into dictionary_page_offsets. */
  2: required EncodedArray first_dictionary_pages,
  /** UINT64: flattened byte offsets of all dictionary pages. */
  3: required EncodedArray dictionary_page_offsets,
  /** UINT64: total compressed bytes in each column chunk. */
  4: required EncodedArray total_compressed_sizes,
  /** UINT64: total uncompressed bytes in each column chunk. */
  5: required EncodedArray total_uncompressed_sizes,
  /** UINT64: value count in each column chunk. */
  6: required EncodedArray num_values,
  /** UINT32: parquet.CompressionCodec value for each column chunk. */
  7: required EncodedArray codecs,
  /** UINT32: parquet.Type value; num_columns entries, one per leaf column. */
  8: required EncodedArray physical_types,
  /** BOOLEAN: true when every data page in the column chunk is dictionary encoded. */
  9: required EncodedArray is_fully_dictionary_encoded,
  /** UINT64: row count in each row group; num_row_groups entries, one per row group. */
  10: required EncodedArray row_group_num_rows
}

/**
 * Row-group statistics for one leaf column; array positions are row-group ordinals.
 *
 * A row group's min and max often share a leading run of bytes (timestamps, sorted keys). That
 * longest common prefix is stored once in minmax_prefixes, and min_suffixes / max_suffixes carry
 * only the differing tails, so a long shared prefix is never written twice. The three arrays share
 * present positions: a row group that has a min/max has an entry in all three.
 */
struct ColumnStatistics {
  /** UINT64: optional null count for each row group. */
  1: optional EncodedArray null_counts,
  /** BYTE_ARRAY: longest common prefix of each row group's min and max (empty when none). */
  2: optional EncodedArray minmax_prefixes,
  /** BYTE_ARRAY: each present minimum with its minmax_prefixes entry stripped (suffix only). */
  3: optional EncodedArray min_suffixes,
  /** BYTE_ARRAY: each present maximum with its minmax_prefixes entry stripped (suffix only). */
  4: optional EncodedArray max_suffixes,
  /** BOOLEAN: 1 when the minimum is exact, 0 when it is a truncated (rounded-down) lower bound. */
  5: optional EncodedArray min_is_exact,
  /** BOOLEAN: 1 when the maximum is exact, 0 when it is a truncated (rounded-up) upper bound. */
  6: optional EncodedArray max_is_exact,
  /** UINT64: optional NaN count. */
  7: optional EncodedArray nan_counts
}

/**
 * Directory of independently serialized ColumnStatistics descriptors.
 *
 * column_offsets contains num_columns + 1 dense UINT64 absolute file offsets. Entries c and c+1
 * delimit the descriptor for leaf column c. Equal offsets mean that the column has no row-group
 * statistics. A per-column encryption envelope may cover the descriptor and its inline arrays so
 * one column key protects the column's statistics as a unit.
 */
struct RowGroupStatisticsModule {
  1: required EncodedArray column_offsets
}

// Page-index modules are not part of the initial definition. Their layout and relationship to the
// existing OffsetIndex and ColumnIndex metadata may change in a future revision.
//
// /**
//  * Per-page placement for one (leaf column, row group) column chunk. The arrays use that column
//  * chunk's data-page ordinal as their logical position.
//  */
// struct OffsetIndexChunk {
//   /** UINT64: page byte offset. */
//   1: required EncodedArray offsets,
//   /** UINT32: compressed page bytes including its page header. */
//   2: required EncodedArray compressed_page_sizes,
//   /** UINT64: first row index within the row group. */
//   3: required EncodedArray first_row_indexes
// }
//
// /**
//  * Per-page statistics for one (leaf column, row group) column chunk.
//  *
//  * Min and max reuse the same common-prefix stripping as the row-group statistics: each page's
//  * longest common prefix is stored once in minmax_prefixes, and min_suffixes / max_suffixes carry
//  * only the differing tails. The three arrays share present positions.
//  */
// struct ColumnIndexChunk {
//   1: required parquet.BoundaryOrder boundary_order,
//   /** BOOLEAN: true when the page contains only null values. */
//   2: required EncodedArray null_pages,
//   /** UINT64: optional null count. */
//   3: optional EncodedArray null_counts,
//   /** BYTE_ARRAY: longest common prefix of each page's min and max (empty when none). */
//   4: optional EncodedArray minmax_prefixes,
//   /** BYTE_ARRAY: each present minimum with its minmax_prefixes entry stripped (suffix only). */
//   5: optional EncodedArray min_suffixes,
//   /** BYTE_ARRAY: each present maximum with its minmax_prefixes entry stripped (suffix only). */
//   6: optional EncodedArray max_suffixes,
//   /** BOOLEAN: 1 when the minimum is exact, 0 when it is a truncated lower bound. */
//   7: optional EncodedArray min_is_exact,
//   /** BOOLEAN: 1 when the maximum is exact, 0 when it is a truncated upper bound. */
//   8: optional EncodedArray max_is_exact,
//   /** UINT64: optional NaN count. */
//   9: optional EncodedArray nan_counts
// }
//
// /**
//  * Directory for independently serialized per-column-chunk index descriptors.
//  *
//  * chunk_offsets contains num_columns * num_row_groups + 1 dense UINT64 absolute file offsets in
//  * column-major chunk space. Entries k and k+1 delimit one compact-Thrift OffsetIndexChunk or
//  * ColumnIndexChunk. Equal offsets mean that the chunk has no corresponding index.
//  */
// struct PageIndexModule {
//   1: required EncodedArray chunk_offsets
// }

/** Descriptive metadata is read in full, so it remains ordinary Thrift data. */
struct FileMetadataModule {
  1: optional string created_by,
  2: optional list<parquet.KeyValue> key_value_metadata
}

/**
 * Optional index over the schema. Turns name -> leaf-column-ordinal resolution, and per-element
 * schema access, from O(all columns) into O(projected): a reader hashes each queried path instead
 * of parsing every SchemaElement. Written only when the schema is wide enough to earn the bytes (a
 * writer threshold); narrow footers omit it. Because it is located through the module directory, a
 * reader that does not understand SCHEMA_INDEX -- or a footer that omits it -- simply walks
 * SchemaModule, so this module is purely additive and never required for correctness.
 *
 * Resolution is O(projected) but not schema-free: confirming a hash hit reads the candidate leaf's
 * bytes from SchemaModule via element_offsets, so a hash collision can never mis-resolve. A reader
 * that projects K names parses K SchemaElements, not all of them. It rides its own module rather
 * than optional fields on SchemaModule so the hash table -- the dominant cost -- stays off the
 * always-read schema fetch.
 */
struct SchemaIndexModule {
  /**
   * Open-addressed hash table mapping a column path to its leaf-column ordinal. One dense UINT slot
   * per table position: num_values == num_slots, a fully packed BITSET with no bitmap, and num_slots
   * is a power of two. A zero slot is empty. A non-empty slot packs
   * (discriminator << ordinal_bits) | (leaf_ordinal + 1), where discriminator is the top
   * discriminator_bits of the key hash. The key is FNV-1a-64 over the leaf path lowercased (ASCII
   * case-fold), segments joined by a single NUL byte, the root element excluded. The home slot is
   * hash & (num_slots - 1); probing is linear, ascending, and wraps.
   */
  1: required EncodedArray hash_table,
  /** Count of the high key-hash bits held in the discriminator field of each slot. */
  2: required i8 discriminator_bits,
  /**
   * Count of the low slot bits holding leaf_ordinal + 1. discriminator_bits + ordinal_bits is the
   * hash_table value bit width.
   */
  3: required i8 ordinal_bits,
  /**
   * UINT64: one dense byte offset per SchemaElement, in schema tree (DFS) order, relative to the
   * start of SchemaModule's serialized bytes. Lets a reader seek to one element -- a projected leaf
   * and its ancestors -- without parsing the elements before it.
   */
  4: required EncodedArray element_offsets,
  /**
   * UINT32: one dense entry per leaf column mapping its ordinal to an index into element_offsets.
   * Absent when the schema is flat, in which case leaf ordinal c is element c + 1 (the root is
   * element 0). Bridges a hash hit to the leaf's SchemaElement.
   */
  5: optional EncodedArray leaf_element_indexes,
  /**
   * UINT32: one dense entry per SchemaElement giving the element index of its parent, with the root
   * (element 0) and every direct child of the root storing 0. A reader confirms a hash hit by
   * walking this chain up from the candidate leaf -- reading each ancestor's name through
   * element_offsets and stopping at the first element whose parent is 0 (the root is excluded from
   * the path) -- so it reconstructs the full dotted path in O(depth) and a collision on a shared
   * leaf name never mis-resolves. Absent when the schema is flat: every parent is 0 (a leaf path is
   * just its own name), so this array carries no information.
   */
  6: optional EncodedArray parent_ordinals,
  /**
   * True when any indexed path holds a non-ASCII byte, so a reader knows the hash key was built with
   * plain ASCII case-folding rather than a locale fold and matches the writer's convention.
   */
  7: required bool has_non_ascii_names
}

/** Kinds of module the directory can locate. Older readers skip kinds they do not understand. */
enum ModuleKind {
  SCHEMA = 0,
  PLACEMENT = 1,
  ROW_GROUP_STATISTICS = 2,
  // OFFSET_INDEX = 3,  // Reserved for a future page-index module.
  // COLUMN_INDEX = 4,  // Reserved for a future page-index module.
  FILE_METADATA = 5,
  SCHEMA_INDEX = 6
}

/** One directory entry: the location of the module of the given kind. */
struct ModuleDirectoryEntry {
  1: required ModuleKind kind,
  2: required ModuleLocation location
}

/**
 * The always-read root. modules is a directory mapping each present module to its independently
 * compact-Thrift serialized location. SCHEMA and PLACEMENT MUST be present; other kinds are
 * optional. A new module kind is added to ModuleKind and slotted into the directory without
 * changing this struct, and a reader ignores entries whose kind it does not understand.
 */
struct ModularFooter {
  1: required i32 version,
  2: required i32 num_row_groups,
  3: required i32 num_columns,
  4: required i64 num_rows,
  5: required list<ModuleDirectoryEntry> modules
}
