/**
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements.  See the NOTICE file
 * distributed with this work for additional information
 * regarding copyright ownership.  The ASF licenses this file
 * to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance
 * with the License.  You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/**
 * File format description for the redfile file format
 */
namespace cpp redfile
namespace java redfile

/**
 * Types supported by redfile.  These types are intended to be for the storage
 * format, and in particular how they interact with different encodings.
 * For example INT16 is not included as a type since a good encoding of INT32
 * would handle this.
 */
enum Type {
  BOOLEAN = 0;
  INT32 = 1;
  INT64 = 2;
  INT96 = 3;
  FLOAT = 4;
  DOUBLE = 5;
  BYTE_ARRAY = 6;
}

/**
 * Encodings supported by redfile.  Not all encodings are valid for all types.
 */
enum Encoding {
  /** Default encoding.
   * BOOLEAN - 1 bit per value.
   * INT32 - 4 bytes per value.  Stored as little-endian.
   * INT64 - 8 bytes per value.  Stored as little-endian.
   * FLOAT - 4 bytes per value.  IEEE. Stored as little-endian.
   * DOUBLE - 8 bytes per value.  IEEE. Stored as little-endian.
   * BYTE_ARRAY - 4 byte length stored as little endian, followed by bytes.  
   */
  PLAIN = 0;

  /** Group VarInt encoding for INT32/INT64. **/
  GROUP_VAR_INT = 1;
}

/**
 * Supported compression algorithms.  
 */
enum CompressionCodec {
  UNCOMPRESSED = 0;
  SNAPPY = 1;
  GZIP = 2;
  LZO = 3;
}

enum PageType {
  DATA_PAGE = 0;
  INDEX_PAGE = 1;
}

/** Data page header **/
struct DataPageHeader {
  1: required i32 num_values

  /** Encoding used for this data page **/
  2: required Encoding encoding

  /** TODO: should this contain min/max for this page? It could also be stored in an index page **/

}

struct IndexPageHeader {
  /** TODO: **/
}

struct PageHeader {
  1: required PageType type

  /** Uncompressed page size in bytes **/
  2: required i32 uncompressed_page_size

  /** Compressed page size in bytes **/
  3: required i32 compressed_page_size

  /** 32bit crc for the data below. This allows for disabling checksumming in HDFS
   *  if only a few pages needs to be read 
   **/
  4: optional i32 crc

  5: optional DataPageHeader data_page;
  6: optional IndexPageHeader index_page;
}

/** 
 * Wrapper struct to store key values
 */
 struct KeyValue {
  1: required string key
  2: optional string value
 }

/**
 * Description for column metadata
 */
struct ColumnMetaData {
  /** Type of this column **/
  1: required Type type

  /** Set of all encodings used for this column. The purpose is to validate whether we can decode those pages. **/
  2: required list<Encoding> encodings

  /** Path in schema **/
  3: required list<string> path_in_schema

  /** Compression codec **/
  4: required CompressionCodec codec

  /** Number of values in this column **/
  5: required i64 num_values

  /** total of uncompressed pages size in bytes **/
  6: required i64 total_uncompressed_size

  /** total of compressed pages size in bytes **/
  7: required i64 total_compressed_size

  /** Byte offset from beginning of file to first data page **/
  8: required i64 data_page_offset

  /** Byte offset from beginning of file to root index page **/
  9: optional i64 index_page_offset

  /** Optional key/value metadata **/
  10: optional list<KeyValue> key_value_metadata
}

struct ColumnChunk {
  /** File where column data is stored.  If not set, assumed to be same file as 
    * metadata 
    **/
  1: optional string file_path

  /** Byte offset in file_path to the ColumnMetaData **/
  2: required i64 file_offset

  /** Column metadata for this chunk. This is the same content as what is at
   * file_path/file_offset.  Having it here has it replicated in the file
   * metadata. 
   **/
  3: optional ColumnMetaData meta_data
}
  
struct RowGroup {
  1: required list<ColumnChunk> columns
  /** Total byte size of all the uncompressed column data in this row group **/
  2: required i64 total_byte_size
  /** Number of rows in this row group **/
  3: required i64 num_rows
}

/**
 * Description for file metadata
 */
struct FileMetaData {
  /** Version of this file **/
  1: required i32 version

  /** Number of rows in this file **/
  2: required i64 num_rows

  /** schema for this file **/
  3: required string schema

  /** Row groups in this file **/
  4: required list<RowGroup> row_groups

  /** Optional key/value metadata **/
  5: optional list<KeyValue> key_value_metadata

}
