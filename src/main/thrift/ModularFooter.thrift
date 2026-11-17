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
 * Modular footer: Parquet file metadata stored as independently readable
 * metadata streams. A small root struct, ModularFooter (defined at the end of
 * this file), sits at the end of the file and records where each stream is.
 *
 * The modular footer uses these counts:
 *   num_columns         = |physical (leaf) columns| = FileInfo.num_columns
 *   chunks_in_column(c) = |chunks of column c|, where a chunk is one
 *                         contiguous run of data pages
 *   num_chunks          = |chunks| = sum of chunks_in_column(c)
 *   pages_in_chunk(k)   = |data pages of chunk k|
 *   num_pages           = |data pages| = sum of pages_in_chunk(k)
 *   num_dictionaries    = |dictionary pages|
 *   num_row_groups      = |row groups|
 *   num_ranges          = |row ranges in one RangeStatistics|
 *
 * The doc of each stream field starts with the stream's type and how many
 * values it has, e.g. "INT64, one value per chunk". Values are never null
 * unless the doc says "nullable".
 *
 * Reader requirements: before using a stream, check its value count, the
 * positions it refers to, and the byte ranges it points to. When the file is
 * signed or encrypted, authenticate or decrypt every stream a read depends on
 * before using it.
 */
include "parquet.thrift"
namespace cpp parquet.modular
namespace java org.apache.parquet.format.modular

// Shared metadata structures.

/**
 * Location of a metadata stream. A stream is a sequence of Parquet pages that
 * encodes one flat column of footer metadata, for example the byte offset of
 * every column chunk. Its layout matches a non-nested column chunk:
 *   [optional DICTIONARY_PAGE][DATA_PAGE_V2 ...]
 * where each page is a PageHeader followed by its body. Data pages must be
 * DATA_PAGE_V2; DATA_PAGE (V1) and other page types are not allowed.
 * Allowing more page types requires a new ModularFooter.version.
 *
 * The stream's schema is not written to the file. Instead, the doc of the
 * field that holds the StreamLocation says the stream's type, how many values
 * it has, and whether values can be null.
 *
 * Streams are independent of each other: they need not have the same number
 * of values, their page boundaries need not line up, and together they do not
 * form a Parquet row group.
 *
 * When the footer is signed or encrypted, each shared stream is protected the
 * same way as the footer, including its page headers and dictionary page; see
 * the PME section. Streams in a column's encrypted statistics are the
 * exception: they are encrypted together with the rest of that column's
 * statistics.
 */
struct StreamLocation {
  /** Byte offset of the stream's first page header, from the start of the
   * file. Streams in a column's encrypted statistics are the exception: they
   * are stored inside the encrypted statistics, so their offset is counted
   * from the start of the decrypted stream bytes
   * (ColumnRowRangeStatistics.stream_data).
   */
  1: required i64 offset;

  /** Number of bytes the stream takes up in the file, including page headers
   * and any signature or encryption bytes described in the PME section.
   */
  2: required i64 length;

  /** Compression codec of the stream's pages, used as in any Parquet column
   * chunk. Metadata stream compression is independent of column data
   * compression. Pages are compressed before they are signed or encrypted.
   */
  3: required parquet.CompressionCodec codec;
}

/**
 * Maps columns to their chunks, and chunks to their pages.
 *
 * Chunks are numbered in column order: column 0's chunks first, then column
 * 1's, and so on. Pages are numbered the same way, in chunk order.
 *
 * Both fields store running totals. column_chunk_index[c] is the number of
 * chunks in columns 0 through c, and page_index[k] is the number of pages in
 * chunks 0 through k. So item i owns the range [start(index, i), index[i]),
 * where start(index, i) is 0 for i = 0 and index[i-1] otherwise. With n
 * entries, start(index, n) is the last entry: the total number of chunks or
 * pages. An item with no chunks or pages repeats the previous total.
 *
 * Example: three columns with 2, 1 and 3 chunks give
 *   column_chunk_index = [2, 3, 6]
 * Column 0 owns chunks [0, 2), column 1 owns chunk [2, 3), and column 2 owns
 * chunks [3, 6).
 *
 * column_chunk_index must have exactly num_columns values, and page_index,
 * when present, must have exactly num_chunks values.
 */
struct DataLayout {
  /** INT32, one value per column: the inclusive prefix sum of
   * chunks_in_column(c).
   */
  1: required StreamLocation column_chunk_index;

  /** INT32, one value per chunk: the inclusive prefix sum of
   * pages_in_chunk(k).
   *
   * Required when page_metadata is present. Without it, readers find pages by
   * reading the page headers in the column data; a missing page_index does not
   * mean the chunks have no pages.
   */
  2: optional StreamLocation page_index;
}

/**
 * Locations of the file's dictionary pages. A dictionary ID
 * (ColumnChunkMetadata.dictionary_ids) is a position in these streams. Each
 * dictionary is stored once, even when chunks share it. Dictionary pages can
 * be stored anywhere in the file, not necessarily next to the chunks that use
 * them.
 */
struct DictionaryMetadata {
  /** INT64, one value per dictionary: the byte offset of the dictionary page
   * header from the start of the file.
   */
  1: required StreamLocation offsets;

  /** INT64, one value per dictionary: the size in bytes of the dictionary
   * page, including its header. Dictionary pages must not overlap each other
   * or any data pages.
   */
  2: required StreamLocation lengths;

  /** INT32, one value per dictionary: the codec of the dictionary page, as a
   * parquet.CompressionCodec value. This is the only source of a dictionary
   * page's codec; the codecs of the chunks that use it do not apply.
   */
  3: required StreamLocation codecs;
}

/**
 * Optional row-group boundaries, kept for compatibility. If present, the data
 * is laid out in row groups, each stored as one contiguous byte range in file
 * order. If absent, the file does not record row groups, though its data may
 * still be laid out in them.
 */
struct RowGroupMetadata {
  /** INT64, one value per row group: the number of rows in the row group. The
   * values sum to FileInfo.num_rows.
   */
  1: required StreamLocation num_rows;

  /** INT64, one value per row group plus one: the byte boundaries of the row
   * groups. Row group g occupies bytes [offsets[g], offsets[g+1]).
   */
  2: required StreamLocation offsets;
}

/**
 * Per-chunk metadata. Each stream has one value per chunk, in the chunk order
 * defined by DataLayout.column_chunk_index. Chunk boundaries are not tied to
 * row groups.
 */
struct ColumnChunkMetadata {
  /** INT32, one value per chunk: the codec of the chunk's data pages, as a
   * parquet.CompressionCodec value. Dictionary pages use
   * DictionaryMetadata.codecs instead.
   */
  1: required StreamLocation codecs;

  /** INT32, one nullable value per chunk: the chunk's dictionary ID, which is
   * its position in DictionaryMetadata, or null if the chunk has no dictionary.
   *
   * Several chunks can share one dictionary, with these rules:
   * - The chunks must belong to the same column.
   * - Every dictionary must be used by at least one chunk.
   */
  2: required StreamLocation dictionary_ids;

  /** BOOLEAN, one value per chunk: true if every data page in the chunk is
   * encoded with the chunk's dictionary. Always false for a chunk without a
   * dictionary.
   */
  3: required StreamLocation is_fully_dictionary_encoded;

  /** INT64, one value per chunk: the size of the chunk's data pages after
   * encoding but before compression, i.e. page headers plus uncompressed page
   * bodies. The dictionary page is not included. If this stream is absent, the
   * sizes are unknown.
   */
  4: optional StreamLocation total_uncompressed_sizes;

  /** INT64, one value per chunk: the number of values in the chunk, as in
   * ColumnMetaData.num_values. This includes nulls and equals the number of
   * definition/repetition levels written for the chunk. It is not a row count:
   * a nested column can have more values than rows.
   */
  5: required StreamLocation num_values;

  /** INT64, one value per chunk: the row number, within the file, of the
   * chunk's first row.
   *
   * Required if any statistics, including encrypted statistics, use
   * COLUMN_CHUNK ranges. When PageMetadata.first_row_indexes is present, each
   * chunk's value must equal the first row of its first page.
   */
  6: optional StreamLocation first_row_indexes;

  /** INT64, one value per chunk: the byte offset of the chunk's first data
   * page header from the start of the file. A chunk's data pages are stored
   * contiguously.
   */
  7: required StreamLocation offsets;

  /** INT64, one value per chunk: the size in bytes of the chunk's data pages as
   * stored, i.e. compressed and including page headers. The dictionary page is
   * not included. Chunks must not overlap.
   */
  8: required StreamLocation compressed_sizes;
}

/**
 * Per-page metadata. Each stream has one value per data page, in the page
 * order defined by DataLayout.page_index.
 */
struct PageMetadata {
  /** INT64, one value per page: the row number, within the file, of the page's
   * first row. Required if any statistics, including encrypted statistics, use
   * PAGE ranges. If absent, readers get row positions from the data pages.
   */
  1: optional StreamLocation first_row_indexes;

  /** INT64, one value per page: the byte offset of the page header from the
   * start of its chunk (ColumnChunkMetadata.offsets), so each chunk's first
   * page is at 0. If absent, readers find pages by reading page headers.
   */
  2: optional StreamLocation relative_offsets;
}

/** How a statistics set divides each column's rows into ranges; see
 * RangeStatistics.range_kind.
 */
enum RowRangeKind {
  COLUMN_CHUNK = 0,
  PAGE = 1,
  ARBITRARY = 2
}

/**
 * Statistics for a list of row ranges. Each stream has one value per range
 * (num_ranges in total). In SharedRangeStatistics the list holds the ranges of
 * all columns, one column after another; in ColumnRowRangeStatistics it holds
 * the ranges of a single column.
 *
 * A column can lack statistics. With COLUMN_CHUNK or PAGE ranges it keeps its
 * positions and its values are null; with ARBITRARY ranges it has no ranges.
 *
 * A null value or a missing stream means the statistic is unknown for that
 * range. In particular, null min/max values do not mean that every value in
 * the range is null; use null_count and num_values for that. Counts are never
 * negative. When null_count, nan_count and num_values are all known,
 * null_count + nan_count <= num_values.
 *
 * Min/max values use FileInfo.column_orders and follow the bound semantics of
 * parquet.Statistics.min_value and max_value, including the NaN and signed-zero
 * rules in parquet.ColumnOrder. Min/max statistics are not supported for INT96
 * columns.
 */
struct RangeStatistics {
  /** How the ranges are defined:
   * COLUMN_CHUNK: statistics over each column chunk, one entry per chunk.
   *   ColumnChunkMetadata.first_row_indexes must be present.
   * PAGE: statistics over each data page, one entry per page.
   *   PageMetadata.first_row_indexes and both DataLayout streams must be
   *   present.
   * ARBITRARY: statistics over row ranges chosen by the writer and listed in
   *   first_row_indexes, for example every 100,000 rows. The ranges need not
   *   line up with chunks, pages or row groups.
   *
   * For each column represented by one or more ranges, those ranges cover
   * [0, FileInfo.num_rows) exactly once, with no empty ranges. With
   * ARBITRARY, a column without statistics has no ranges. Empty files have no
   * ranges. These rules also apply to encrypted statistics. Readers cannot use
   * statistics whose range_kind they do not recognize.
   */
  1: required RowRangeKind range_kind;

  /** INT64, one value per range: the row number of the range's first row.
   * Within each column, a range ends where the next one starts, or at
   * FileInfo.num_rows for the last range. Present if and only if range_kind
   * is ARBITRARY.
   *
   * Example: in a file with 250,000 rows, two columns have three ranges and
   * one range, respectively:
   *   first_row_indexes = [0, 100000, 200000, 0]
   * The first column has ranges [0, 100000), [100000, 200000) and
   * [200000, 250000). The second column has the range [0, 250000).
   */
  2: optional StreamLocation first_row_indexes;

  /** INT64, one nullable value per range: the number of null values in the
   * range.
   */
  3: optional StreamLocation null_count;

  /** INT64, one nullable value per range: the number of NaN values in the
   * range. NaNs are not counted in null_count.
   */
  4: optional StreamLocation nan_count;

  /** INT64, one nullable value per range: the number of values in the range,
   * including nulls and NaNs. Must not be written for COLUMN_CHUNK ranges,
   * which use ColumnChunkMetadata.num_values instead.
   */
  5: optional StreamLocation num_values;

  /** INT64, one nullable value per range: the number of distinct values in the
   * range.
   */
  6: optional StreamLocation distinct_counts;

  /** Minimum values, one stream per supported physical type; each column uses the
   * stream for its type. One nullable value per range. A value is null when
   * the minimum is unavailable or the column has a different type.
   */
  7: optional StreamLocation min_boolean; // BOOLEAN
  8: optional StreamLocation min_int32; // INT32
  9: optional StreamLocation min_int64; // INT64
  10: optional StreamLocation min_float; // FLOAT
  11: optional StreamLocation min_double; // DOUBLE
  12: optional StreamLocation min_byte_array; // BYTE_ARRAY

  /** BYTE_ARRAY, one nullable value per range: the minimum for a
   * FIXED_LEN_BYTE_ARRAY column. Null when the minimum is unavailable or the
   * column has a different physical type. Each non-null value must contain
   * exactly SchemaElement.type_length bytes for its column. The stream uses
   * BYTE_ARRAY so columns with different fixed lengths can share it.
   */
  21: optional StreamLocation min_fixed_len_byte_array;

  /** Maximum values, stored the same way as the minimum values. */
  13: optional StreamLocation max_boolean; // BOOLEAN
  14: optional StreamLocation max_int32; // INT32
  15: optional StreamLocation max_int64; // INT64
  16: optional StreamLocation max_float; // FLOAT
  17: optional StreamLocation max_double; // DOUBLE
  18: optional StreamLocation max_byte_array; // BYTE_ARRAY

  /** BYTE_ARRAY, one nullable value per range: the maximum for a
   * FIXED_LEN_BYTE_ARRAY column, stored as in min_fixed_len_byte_array.
   */
  22: optional StreamLocation max_fixed_len_byte_array;

  /** BOOLEAN, one nullable value per range: whether the minimum is the actual
   * minimum of the range. Null when unknown or when the minimum is
   * unavailable.
   */
  19: required StreamLocation min_is_exact;

  /** BOOLEAN, one nullable value per range: whether the maximum is the actual
   * maximum of the range. Null when unknown or when the maximum is
   * unavailable.
   */
  20: required StreamLocation max_is_exact;
}

/**
 * One set of row-range statistics for all columns, protected like the rest of
 * the footer. Columns whose statistics are encrypted separately are treated
 * as lacking statistics here.
 */
struct SharedRangeStatistics {
  /** INT64, one value per column: the inclusive prefix sum of each column's
   * number of ranges, like DataLayout.column_chunk_index. Column c owns ranges
   * [start(column_range_index, c), column_range_index[c]). Present if and only
   * if statistics.range_kind is ARBITRARY.
   *
   * Example: columns a, b and c with 3, 0 and 1 ranges give
   *   column_range_index = [3, 3, 4]
   */
  1: optional StreamLocation column_range_index;

  /** The statistics for all columns. Which positions belong to column c
   * depends on range_kind, with a = start(column_chunk_index, c) and
   * b = column_chunk_index[c] (start() is defined in DataLayout):
   *   COLUMN_CHUNK: [a, b).
   *   PAGE: [start(page_index, a), start(page_index, b)).
   *   ARBITRARY: the positions given by column_range_index.
   */
  2: required RangeStatistics statistics;

  /** INT32, one value per column: the parquet.BoundaryOrder of the column's
   * min/max values across its ranges, compared using FileInfo.column_orders.
   * UNORDERED for columns without statistics. If this stream is absent, every
   * column is UNORDERED.
   */
  3: optional StreamLocation boundary_orders;
}

/** File schema, row and column counts, writer information and column orders. */
struct FileInfo {
  /** Number of physical (leaf) columns. */
  1: required i32 num_columns;
  /** Number of rows in the file. */
  2: required i64 num_rows;
  /** Schema of the file's data, as in FileMetaData.schema. */
  3: required list<parquet.SchemaElement> schema;
  /** Application that wrote the file, as in FileMetaData.created_by. */
  4: optional string created_by;

  /** Comparison orders for min/max statistics, as in FileMetaData.column_orders.
   * When present, contains exactly num_columns entries in schema leaf-column
   * order. Each entry applies to all statistics sets for that column, including
   * encrypted statistics.
   *
   * Required when any statistics set contains a non-null min/max value. If the
   * list is absent or a column's order is unsupported or undefined, readers
   * must ignore that column's min/max statistics and boundary orders.
   */
  5: optional list<parquet.ColumnOrder> column_orders;
}

// Parquet Modular Encryption (PME) structures.

/**
 * Encryption follows Parquet Modular Encryption (Encryption.md), with these
 * differences:
 * - The root struct is always signed, like a plaintext footer.
 * - Encrypted footer mode: FileInfo is in encrypted_file_info, and each shared
 *   stream is encrypted with the footer key. The magic stays "PAR3".
 * - Plaintext footer mode: FileInfo is plaintext, and each shared stream is
 *   signed with the footer key.
 * - If a column is encrypted with its own key, its statistics are not stored
 *   in the shared statistics. They are encrypted with that column key and
 *   stored separately (see EncryptedRowRangeStatistics).
 * - AAD suffixes use new module types, with these fields in place of row group
 *   and page ordinals:
 *     root struct (NEW_FOOTER_DIRECTORY_TYPE): LE32(version)
 *     FileInfo (NEW_FILE_INFO_TYPE): LE32(version)
 *     stream (NEW_METADATA_STREAM_TYPE): LE32(version), the stream's path
 *       (LE32 count, then LE32 per component), LE64(offset), LE64(length) and
 *       LE32(codec). The path is the Thrift field IDs and list positions from
 *       the root struct to the StreamLocation, e.g. [8, 0, 2, 8] for min_int32
 *       in statistics set 0.
 *     column statistics (NEW_ROW_RANGE_STATISTICS_TYPE): LE32(version) and
 *       LE32(column ordinal)
 *   Module type values are not allocated yet.
 */

/**
 * One column's statistics, encrypted as a whole with the column's key.
 * Positions count only this column's chunks, pages or ranges, and only the
 * min and max streams for the column's type may be present.
 */
struct ColumnRowRangeStatistics {
  /** This column's statistics sets, as in SharedRangeStatistics. */
  1: required list<RangeStatistics> statistics;

  /** The bytes of the streams in `statistics`. Their StreamLocation offsets
   * are counted from the start of this field.
   */
  2: required binary stream_data;

  /** One BoundaryOrder per entry in statistics, in the same order, compared
   * using this column's entry in FileInfo.column_orders. Missing entries are
   * UNORDERED.
   */
  3: optional list<parquet.BoundaryOrder> boundary_orders;
}

/** Location and key of one column's encrypted statistics. */
struct EncryptedColumnRowRangeStatistics {
  /** The column's position among the leaf columns in FileInfo.schema. */
  1: required i32 column_ordinal;

  /** Key used, as in ColumnChunk.crypto_metadata. path_in_schema must match
   * column_ordinal.
   */
  2: required parquet.ColumnCryptoMetaData crypto_metadata;

  /** Byte offset from the start of the file. */
  3: required i64 offset;

  /** Size in bytes. The plaintext is a ColumnRowRangeStatistics. */
  4: required i64 length;
}

/**
 * Statistics encrypted separately per column: for columns with their own key,
 * or that need encryption in a plaintext footer mode file. In the shared
 * statistics these columns have null values, or no ranges with ARBITRARY. A
 * reader without the key treats their statistics as unavailable.
 */
struct EncryptedRowRangeStatistics {
  /** One entry per column whose statistics are stored separately, in any
   * order.
   */
  1: required list<EncryptedColumnRowRangeStatistics> columns;
}

// Footer directory.

/**
 * Root of the modular footer. It records where every metadata stream is,
 * including the column-key descriptors for encrypted statistics. Readers find
 * it from the end of the file:
 *
 *   +----------------------------------------------+
 *   | data and dictionary pages                    |
 *   +----------------------------------------------+
 *   | metadata streams and encrypted column        |
 *   | statistics (must not overlap)                |
 *   +----------------------------------------------+ <- file_size - 8 - directory_length
 *   | ModularFooter (Thrift compact protocol)      |
 *   | 28-byte signature (only if crypto_metadata)  |
 *   +----------------------------------------------+
 *   | directory_length: u32, little-endian         |  covers ModularFooter + signature
 *   | magic: "PAR3"                                |
 *   +----------------------------------------------+ <- file_size
 *
 * directory_length counts the ModularFooter struct and its optional signature,
 * not the final 8 bytes. Readers must check directory_length against the file
 * size before computing the start position. See the PME section for
 * signature and AAD rules.
 */
struct ModularFooter {
  /** Format version of the modular footer. The value is not allocated yet. */
  1: required i32 version;

  /** Basic file metadata, in plaintext. Exactly one of file_info and
   * encrypted_file_info is present.
   */
  2: optional FileInfo file_info;
  3: required DataLayout data_layout;
  4: required DictionaryMetadata dictionary_metadata;
  5: optional RowGroupMetadata row_group_metadata;
  6: required ColumnChunkMetadata column_chunk_metadata;
  7: optional PageMetadata page_metadata;

  /** Statistics sets for the file. Each set divides rows into ranges in its
   * own way (see RangeStatistics.range_kind). A file can have several, for
   * example statistics over column chunks, over pages, or over arbitrary row
   * ranges.
   *
   * Sets are independent: a range in one set does not have to fall inside a
   * range of another. To combine sets, match ranges by the rows they cover, not
   * by their position, and do not add up counts from ranges that overlap.
   * Leave out sets without statistics, and leave out the list when none remain.
   */
  8: optional list<SharedRangeStatistics> row_range_statistics;

  /** BYTE_ARRAY, one value per key/value metadata entry: the key. */
  9: optional StreamLocation key_value_metadata_keys;

  /** BYTE_ARRAY, one nullable value per entry in key_value_metadata_keys: the
   * value for that key.
   */
  10: optional StreamLocation key_value_metadata_values;

  /** Encryption algorithm and footer key metadata, as in FileCryptoMetaData.
   * Absent in unencrypted files. With file_info, the file uses plaintext footer
   * mode; with encrypted_file_info, encrypted footer mode (see the PME
   * section).
   */
  11: optional parquet.FileCryptoMetaData crypto_metadata;

  /** FileInfo, encrypted with the footer key (encrypted footer mode). */
  12: optional binary encrypted_file_info;

  /** Statistics encrypted separately for each column. A column's statistics
   * are stored either here or in row_range_statistics, not both.
   */
  13: optional EncryptedRowRangeStatistics encrypted_row_range_statistics;
}
