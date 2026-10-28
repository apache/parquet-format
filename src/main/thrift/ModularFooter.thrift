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

/** Modular footer supporting flexible data layouts and row-range statistics.
 *
 * C = physical columns; K_c = chunks in column c; K = sum(K_c).
 * P_k = data pages in chunk k; P = sum(P_k); D = dictionaries; G = row groups.
 * M = key/value pairs. K_c may vary, including zero, independently of G.
 * Chunk membership alone does not determine row coverage.
 *
 * StreamLocation comments specify the scalar Parquet type, value count and
 * nullability. Each stream is a primitive column with no LIST nesting.
 * Field IDs define types; no stream schema is serialized.
 * FileInfo.schema describes the source data.
 * Thrift optional controls stream presence, not value nullability.
 * Non-null streams: max RL=DL=0. Nullable streams: max RL=0, max DL=1
 * (DL=0: null; DL=1: present). No hierarchy repetition levels are stored.
 *
 * Chunk fields have K positions in column/chunk order; page fields have P
 * positions in chunk/page order. Nulls keep their positions. Shared indexes
 * address logical positions; metadata-page boundaries may differ by stream.
 * These streams need not have equal row counts or form one Parquet row group.
 * Validate counts, indexes and extents; authenticate/decrypt required streams
 * before use. An unavailable index never means an empty hierarchy.
 */
include "parquet.thrift"
namespace cpp parquet.modular
namespace java org.apache.parquet.format.modular

// Shared metadata structures.

/** PageHeader/body pairs: [optional DICTIONARY_PAGE][DATA_PAGE_V2 ...].
 * Shared streams inherit root protection, including headers and dictionaries.
 * Streams inside ColumnRowRangeStatistics are plaintext within its encrypted module.
 */
struct StreamLocation {
  /** Absolute file offset; relative to page_streams inside a column module. */
  1: required i64 offset;

  /** Stored bytes, including headers and protection. Signed streams append a
   * 28-byte signature; encrypted streams add length4 + nonce12 + GCM-tag16.
   * Column-module streams have no individual protection overhead.
   */
  2: required i64 length;

  /** Codec for dictionary bodies and V2 values when is_compressed is true.
   * Levels are uncompressed. Compress before protection; independent of data codecs.
   */
  3: required parquet.CompressionCodec codec;
}

/** Exclusive element ends, not byte offsets; non-negative signed i32 values.
 * Omit only the fixed leading zero; retain genuine zero ends (empty lists).
 * boundary(index,n) = 0 if n=0, else index[n-1], for 0<=n<=length.
 */
struct DataLayout {
  /** INT32; number of values = C; nullability: non-null.
   * C must match FileInfo.num_columns. Non-decreasing; last end is K
   * (K=0 if C=0). Column c owns [boundary(index,c), index[c]) chunks.
   */
  1: required StreamLocation column_chunk_index;

  /** INT32; number of values = K; nullability: non-null.
   * Non-decreasing; last end is P (P=0 if K=0).
   * Chunk k owns [boundary(index,k), index[k]) pages.
   * Required with PageMetadata; otherwise optional. If absent, use source
   * page headers for grouping; absence does not imply P=0.
   */
  2: optional StreamLocation page_index;
}

/** Dictionary IDs address table positions. */
struct DictionaryMetadata {
  /** INT64; number of values = D; nullability: non-null. D fits signed i32.
   * Absolute dictionary-page offsets, including headers. Store each referenced
   * dictionary once; no adjacency/order restriction. First-reference order is
   * recommended. Both streams are empty when no dictionaries are used.
   */
  1: required StreamLocation offsets;

  /** INT64; number of values = D; nullability: non-null.
   * Positive stored sizes, including headers. Dictionary d occupies
   * [offsets[d], offsets[d]+lengths[d]), disjoint from data and other dictionaries.
   */
  2: required StreamLocation lengths;
}

struct RowGroupMetadata {
  /** INT64; number of values = G; nullability: non-null.
   * Row counts in row-group order; sum equals FileInfo.num_rows.
   */
  1: required StreamLocation num_rows;

  /** INT64; number of values = G+1; nullability: non-null.
   * Non-decreasing absolute byte boundaries; optional hint for contiguous
   * row groups in file order. Omit if interleaving or shared dictionaries
   * prevent complete extents. Chunk/dictionary locations remain independent.
   */
  2: optional StreamLocation offsets;
}

/** Flat fields grouped by DataLayout.column_chunk_index. */
struct ColumnChunkMetadata {
  /** INT32; number of values = K; nullability: non-null.
   * parquet.CompressionCodec values.
   */
  1: required StreamLocation codecs;

  /** INT32; number of values = K; nullability: nullable.
   * Null means no dictionary; otherwise an ID in [0,D). Sharing is allowed
   * only within one physical column, as determined by column_chunk_index.
   * Every dictionary must be referenced and compatible with each referencing
   * chunk, including its codec.
   */
  2: required StreamLocation dictionary_ids;

  /** BOOLEAN; number of values = K; nullability: non-null.
   * True if all data pages use the chunk's dictionary; false without one.
   */
  3: required StreamLocation is_fully_dictionary_encoded;

  /** INT64; number of values = K; nullability: non-null.
   * Page headers + uncompressed bodies, counting the dictionary once per
   * referencing chunk, even if shared. Omission means unknown sizes.
   */
  4: optional StreamLocation total_uncompressed_sizes;

  /** INT64; number of values = K; nullability: non-null.
   * Data-value counts including nulls; not row counts.
   */
  5: required StreamLocation num_values;

  /** INT64; number of values = K; nullability: non-null.
   * Absolute first rows; required for any COLUMN_CHUNK statistics, including
   * encrypted statistics. Independent of row groups and num_values; must agree
   * with the chunk's first page row when page-row metadata is present.
   */
  6: optional StreamLocation first_row_indexes;

  /** INT64; number of values = K; nullability: non-null.
   * Absolute offsets of contiguous data pages, including headers, excluding
   * dictionaries. Chunks need not be adjacent or in byte-offset order.
   */
  7: required StreamLocation offsets;

  /** INT64; number of values = K; nullability: non-null.
   * Stored data-page bytes, excluding dictionaries; non-negative, zero iff
   * no data pages. [offsets[k], offsets[k]+compressed_sizes[k]) extents are
   * disjoint when nonempty. Check file bounds and overflow; never infer size
   * from another chunk or dictionary.
   */
  8: required StreamLocation compressed_sizes;
}

/** Independently optional streams sharing DataLayout.page_index; omit if both absent. */
struct PageMetadata {
  /** INT64; number of values = P; nullability: non-null.
   * Absolute first rows; required for any PAGE statistics, including encrypted
   * statistics. If absent, obtain row positions from source-data pages.
   */
  1: optional StreamLocation first_row_indexes;

  /** INT64; number of values = P; nullability: non-null.
   * Relative to ColumnChunkMetadata.offsets[k]. Start at 0 in each nonempty
   * chunk and strictly increase below compressed_sizes[k]; last page ends at
   * the chunk end. Retain the first zero, including for single-page chunks.
   * If absent, scan source page headers to locate interior pages.
   */
  2: optional StreamLocation relative_offsets;
}

/** Source of a statistics set's row ranges. */
enum RowRangeKind {
  COLUMN_CHUNK = 0,
  PAGE = 1,
  ARBITRARY = 2
}

/** S ranges for one granularity; the containing struct defines column ownership.
 * Null values or omitted statistics streams mean unknown, including all-nullness.
 * Counts are non-negative. When known, null_count + nan_count <= num_values.
 */
struct RangeStatistics {
  /** INT64; number of values = S; nullability: non-null.
   * Absolute first rows; present iff range_kind is ARBITRARY. Per column,
   * start at 0 and strictly increase below FileInfo.num_rows. End at the next
   * start or FileInfo.num_rows; alignment with chunks/pages/row groups is optional.
   */
  1: optional StreamLocation first_row_indexes;

  /** INT64; number of values = S; nullability: nullable.
   * Number of null values per range.
   */
  2: optional StreamLocation null_count;

  /** INT64; number of values = S; nullability: nullable.
   * Number of NaN values per range. NaNs are non-null values.
   */
  3: optional StreamLocation nan_count;

  /** INT64; number of values = S; nullability: nullable.
   * Total data values per range, including nulls and NaNs; not a row count.
   */
  4: optional StreamLocation num_values;

  /** INT64; number of values = S; nullability: nullable. */
  5: optional StreamLocation distinct_counts;

  /** Bound streams: [min_0, max_0, min_1, max_1, ...]; values independently nullable.
   * Wrong physical type or unavailable bound means null. Pairs may cross
   * metadata-page boundaries.
   */
  6: optional StreamLocation min_max_boolean; // BOOLEAN; number of values = 2S.
  7: optional StreamLocation min_max_int32; // INT32; number of values = 2S.
  8: optional StreamLocation min_max_int64; // INT64; number of values = 2S.
  9: optional StreamLocation min_max_float; // FLOAT; number of values = 2S.
  10: optional StreamLocation min_max_double; // DOUBLE; number of values = 2S.
  11: optional StreamLocation min_max_byte_array; // BYTE_ARRAY; number of values = 2S.

  /** BOOLEAN; number of values = 2S; nullability: nullable.
   * Aligned with paired bounds: true=exact, false=inexact, null=unknown.
   * An unavailable bound requires null exactness.
   */
  12: optional StreamLocation min_max_is_exact;

  /** Writers emit the tag; absent means ARBITRARY. Unknown tags are unsupported.
   * COLUMN_CHUNK: one range per chunk; requires ColumnChunkMetadata.first_row_indexes.
   * PAGE: one range per page; requires PageMetadata.first_row_indexes and both
   * DataLayout indexes. Each participating chunk must have at least one page.
   * ARBITRARY: explicit first_row_indexes; used when positional coverage is unsuitable.
   *
   * For each participating column, ranges must be nonempty, row-aligned and
   * partition [0, FileInfo.num_rows). Starts begin at 0 and strictly increase;
   * each end is the next start or num_rows. Starts alone do not prove gap coverage.
   * These rules also apply to encrypted statistics. Authenticate/decrypt the
   * referenced hierarchy and row streams under their own policy before use.
   */
  13: optional RowRangeKind range_kind = RowRangeKind.ARBITRARY;
}

/** One shared granularity across C columns; streams inherit root protection.
 * COLUMN_CHUNK (S=K) and PAGE (S=P) retain every position, using unknown slots
 * for unavailable or independently encrypted statistics. ARBITRARY permits
 * zero ranges per column via equal column_range_starts.
 */
struct SharedRangeStatistics {
  /** INT64; number of values = C+1; nullability: non-null.
   * Present iff statistics.range_kind is ARBITRARY. Non-decreasing, from 0 to S.
   * Column c owns [index[c], index[c+1]); equal ends mean no ranges.
   */
  1: optional StreamLocation column_range_starts;

  /** For column c, let a=boundary(column_chunk_index,c), b=column_chunk_index[c].
   * COLUMN_CHUNK: [a,b). PAGE: [boundary(page_index,a),boundary(page_index,b)).
   * ARBITRARY: use column_range_starts. boundary() is defined in DataLayout.
   */
  2: required RangeStatistics statistics;

  /** INT32; number of values = C; nullability: non-null.
   * parquet.BoundaryOrder per column. Columns without shared statistics must
   * be UNORDERED; omission means all UNORDERED.
   */
  3: optional StreamLocation boundary_orders;
}

/** Inline file metadata, plaintext or encrypted with the footer key. */
struct FileInfo {
  1: required i32 num_columns; // Physical columns.
  2: required i64 num_rows;
  3: required list<parquet.SchemaElement> schema;
  4: optional string created_by;
}

// Parquet Modular Encryption (PME) structures.

/** Metadata uses AES-GCM under both PME algorithms. Use a fresh nonce per key
 * for every invocation. Sign the exact serialized root (nonce12 + GCM-tag16;
 * discard ciphertext); authenticate before trusting it or decrypting FileInfo.
 * Verify each stream before parsing pages. Enforce the caller's protection
 * policy; removed crypto metadata must not downgrade protection.
 *
 * AAD = PME file AAD (prefix + aad_file_unique) followed by:
 *   directory: NEW_FOOTER_DIRECTORY_TYPE + LE32(version).
 *   FileInfo: NEW_FILE_INFO_TYPE + LE32(version).
 *   stream: NEW_METADATA_STREAM_TYPE + LE32(version) + LE32(path length)
 *           + LE32(each path component) + LE64(offset) + LE64(length) + LE32(codec).
 *   column stats: NEW_ROW_RANGE_STATISTICS_TYPE + LE32(version) + LE32(column ordinal).
 * Paths use Thrift field IDs and zero-based list positions from the root;
 * e.g. [8,g,2,7] identifies granularity g's min_max_int32. Component kinds
 * follow the schema. Module-type allocations are pending; do not reuse PME IDs.
 */

/** Compact-Thrift plaintext for one column-statistics module.
 * All ranges belong to the enclosing column_ordinal. COLUMN_CHUNK uses S=K_c;
 * PAGE uses this column's page count. Both reuse authenticated shared hierarchy
 * and row metadata; ARBITRARY stores local row starts, without column_range_starts.
 * Only the column's physical-type bound stream may be present (2S values).
 * All StreamLocation offsets are relative to page_streams.
 */
struct ColumnRowRangeStatistics {
  /** Nonempty list of independent granularities, with RangeStatistics semantics.
   * Positions are local to this module; all entries are encrypted together.
   */
  1: required list<RangeStatistics> statistics;

  /** All located streams, concatenated and encoded/compressed before encryption;
   * each uses the PageHeader/body format defined by StreamLocation.
   */
  2: required binary page_streams;

  /** One order per statistics entry; omitted or unavailable orders mean UNORDERED. */
  3: optional list<parquet.BoundaryOrder> boundary_orders;
}

/** One independently encrypted module per physical column. */
struct EncryptedColumnRowRangeStatistics {
  /** Physical leaf ordinal in FileInfo.schema; 0 <= column_ordinal < C. */
  1: required i32 column_ordinal;

  /** Exactly one PME key selector, no raw key; applies to the entire column.
   * ENCRYPTION_WITH_COLUMN_KEY: path_in_schema must match column_ordinal;
   * resolve the column DEK using its key metadata.
   * ENCRYPTION_WITH_FOOTER_KEY: use the footer DEK from root crypto_metadata.
   */
  2: required parquet.ColumnCryptoMetaData crypto_metadata;

  /** Absolute offset of the module's length prefix, before the root. */
  3: required i64 offset;

  /** Total bytes: LE length4 (excludes itself) + nonce12 + ciphertext + GCM-tag16.
   * Plaintext type: ColumnRowRangeStatistics.
   */
  4: required i64 length;
}

/** Omit when no encrypted modules exist. Listed columns have zero shared
 * ARBITRARY ranges or unknown shared COLUMN_CHUNK/PAGE slots; keep positions.
 * Footer-key statistics may use encrypted shared streams; separate column keys
 * require independent blocks. With signed streams, protected statistics also
 * require blocks. Missing keys mean unavailable statistics; authentication
 * failure or malformed plaintext is an error.
 */
struct EncryptedRowRangeStatistics {
  /** Sorted by column_ordinal; no duplicate columns or overlapping blocks. */
  1: required list<EncryptedColumnRowRangeStatistics> columns;
}

// Footer directory.

/** Visible stream directory, including column-key descriptors.
 * Layout: [source data][metadata streams and column-statistics blocks]
 * [Compact-Thrift root][28-byte signature if crypto_metadata is present]
 * [u32 LE directory length][PAR3]. Length includes the root and optional
 * signature, excluding the 8-byte trailer. The root starts at
 * file_size - 8 - directory_length; validate bounds before subtraction.
 * Streams/blocks precede the root and must not overlap.
 * See the PME section for authentication and AAD rules.
 */
struct ModularFooter {
  1: required i32 version; // Allocation pending.

  /** Exactly one of file_info and encrypted_file_info must be present. */
  2: optional FileInfo file_info;
  3: required DataLayout data_layout;
  4: required DictionaryMetadata dictionary_metadata;
  5: optional RowGroupMetadata row_group_metadata;
  6: required ColumnChunkMetadata column_chunk_metadata;
  7: optional PageMetadata page_metadata;

  /** Any number of independent granularities, preferably coarse to fine.
   * Boundaries need not nest; match by row interval, not list position.
   * Do not sum overlapping counts. Omit sets with no available statistics;
   * omit the list when none remain.
   */
  8: optional list<SharedRangeStatistics> row_range_statistics;

  /** BYTE_ARRAY; number of values = M; nullability: non-null. */
  9: optional StreamLocation key_value_metadata_keys;

  /** BYTE_ARRAY; number of values = M; nullability: nullable. Aligned with keys. */
  10: optional StreamLocation key_value_metadata_values;

  /** Algorithm/AAD parameters and opaque footer-key metadata.
   * Absent: plaintext file_info/streams, no signature.
   * With file_info: individually signed streams; with encrypted_file_info:
   * individually footer-key-encrypted streams. Both modes sign the root.
   * aad_file_unique is required; supply any requested external AAD prefix.
   * Missing key_metadata requires external key resolution.
   */
  11: optional parquet.FileCryptoMetaData crypto_metadata;

  /** Serialized FileInfo, encrypted with the footer key; requires crypto_metadata.
   * PME framing: LE length4 (excludes itself), nonce12, ciphertext, GCM-tag16.
   */
  12: optional binary encrypted_file_info;

  /** Independently encrypted statistics; disjoint from shared row_range_statistics. */
  13: optional EncryptedRowRangeStatistics encrypted_row_range_statistics;
}
