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
 * Array-page physical encoding for the modular footer.
 *
 * A metadata page is encoded as:
 *
 *   [compact-Thrift MetadataPageHeader][raw payload]
 *
 * The payload is not a Thrift binary field. It begins immediately after the
 * MetadataPageHeader STOP byte and has exactly payload_length bytes. Its layout is selected by
 * MetadataArrayEncoding, in the same way that a Parquet data page header selects the encoding of
 * the data page body.
 *
 * This file defines the page headers and the always-read footer index. The outer file framing that
 * locates ModularFooterPageIndex from the end of a file is specified separately.
 */

include "parquet.thrift"

namespace cpp parquet.modular.page
namespace java org.apache.parquet.format.modular.page

/** Modules preserve independent read lifecycles; pages never combine modules. */
enum MetadataModule {
  SCHEMA = 0,
  PLACEMENT = 1,
  ROW_GROUP_STATS = 2,
  OFFSET_INDEX = 3,
  COLUMN_INDEX = 4,
  FILE_METADATA = 5
}

/**
 * Stable semantic identifiers for metadata arrays. Numeric values MUST NOT be reused for a
 * different meaning.
 */
enum MetadataArray {
  DATA_PAGE_OFFSET = 0,
  FIRST_DICTIONARY_PAGE = 1,
  DICTIONARY_PAGE_OFFSET = 2,
  TOTAL_COMPRESSED_SIZE = 3,
  TOTAL_UNCOMPRESSED_SIZE = 4,
  NUM_VALUES = 5,
  CODEC = 6,
  PHYSICAL_TYPE = 7,
  IS_FULLY_DICTIONARY_ENCODED = 8,

  NULL_COUNT = 20,
  MIN_VALUE = 21,
  MAX_VALUE = 22,
  MIN_IS_EXACT = 23,
  MAX_IS_EXACT = 24,
  NAN_COUNT = 25,

  PAGE_OFFSET = 40,
  COMPRESSED_PAGE_SIZE = 41,
  FIRST_ROW_INDEX = 42,
  NULL_PAGE = 43,
  BOUNDARY_ORDER = 44,

  /** Cumulative absolute offsets of per-column-chunk metadata page groups. */
  PAGE_GROUP_OFFSET = 45
}

/** Logical type of each value exposed by a decoded metadata page. */
enum MetadataValueType {
  BOOLEAN = 0,
  UINT32 = 1,
  UINT64 = 2,
  BYTE_ARRAY = 3
}

/** Initial raw payload encodings. Neither applies general-purpose compression. */
enum MetadataArrayEncoding {
  BIT_PACKED = 0,
  SPARSE = 1
}

/** The logical domain in which page positions are interpreted. */
enum MetadataPageScope {
  /** File-wide chunk space, column space, or another array-defined domain. */
  FILE = 0,
  /** Data-page ordinals within one (leaf column, row group) column chunk. */
  COLUMN_CHUNK = 1
}

/** Parameters for a dense BIT_PACKED payload. */
struct BitPackedEncodingHeader {
  /** Width of each integer value, or each BYTE_ARRAY cumulative offset, in bits. */
  1: required i8 bit_width
}

/** Parameters for a SPARSE payload. */
struct SparseEncodingHeader {
  /** Number of logical positions that have a value. */
  1: required i32 num_present,
  /** Width of each entry in the sorted logical-position stream, in bits. */
  2: required i8 position_bit_width,
  /** Width of each integer value, or each BYTE_ARRAY cumulative offset, in bits. */
  3: required i8 value_bit_width
}

/** Exactly one member MUST be set, matching MetadataPageHeader.encoding. */
union MetadataEncodingHeader {
  1: BitPackedEncodingHeader bit_packed,
  2: SparseEncodingHeader sparse
}

/**
 * Compact-Thrift header immediately followed by raw payload bytes.
 *
 * FILE pages omit column_ordinal and row_group_ordinal. COLUMN_CHUNK pages MUST carry both. The
 * latter identify the column chunk whose data-page ordinals form this page's logical domain.
 */
struct MetadataPageHeader {
  1: required MetadataModule module,
  2: required MetadataArray array,
  3: required MetadataValueType value_type,
  4: required MetadataArrayEncoding encoding,
  /** Addressable positions, including absent positions under SPARSE. */
  5: required i32 num_values,
  /** Raw bytes immediately following this struct's STOP byte. */
  6: required i32 payload_length,
  7: required MetadataEncodingHeader encoding_header,
  8: required MetadataPageScope scope,
  9: optional i32 column_ordinal,
  10: optional i32 row_group_ordinal
}

/** Locates one complete [MetadataPageHeader][payload] record. */
struct MetadataPageLocation {
  1: required MetadataModule module,
  2: required MetadataArray array,
  3: required MetadataPageScope scope,
  4: optional i32 column_ordinal,
  5: optional i32 row_group_ordinal,
  6: required i64 offset,
  /** Header plus payload bytes. */
  7: required i32 length
}

/** Ordinary compact-Thrift structures that are read in full remain separate modules. */
enum ThriftMetadataModule {
  SCHEMA = 0,
  FILE_METADATA = 1
}

/** Absolute location of one independently serialized ordinary Thrift module. */
struct ThriftModuleLocation {
  1: required ThriftMetadataModule module,
  2: required i64 offset,
  3: required i64 length
}

/**
 * The always-read root of an array-page modular footer.
 *
 * pages contains only FILE-scoped pages. In particular, it contains at most one
 * PAGE_GROUP_OFFSET page for OFFSET_INDEX and one for COLUMN_INDEX. It MUST NOT expand every
 * column chunk's page-index arrays into this root.
 *
 * A PAGE_GROUP_OFFSET payload has num_columns * num_row_groups + 1 dense UINT64 values in chunk
 * space. Entry k and k+1 delimit the absolute byte range containing the COLUMN_CHUNK-scoped
 * metadata pages for chunk k. Equal offsets mean that the chunk has no index. Pages within a
 * nonempty group are concatenated in ascending MetadataArray order.
 */
struct ModularFooterPageIndex {
  1: required i32 version,
  2: required i32 num_row_groups,
  3: required i32 num_columns,
  4: required i64 num_rows,
  5: required list<i64> row_group_num_rows,
  6: required list<MetadataPageLocation> pages,
  7: optional list<ThriftModuleLocation> thrift_modules
}
