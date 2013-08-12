Parquet [![Build Status](https://travis-ci.org/Parquet/parquet-format.png?branch=master)](http://travis-ci.org/Parquet/parquet-format)
======
Parquet is a columnar storage format that supports nested data.

Parquet metadata is encoded using Apache Thrift.

The `Parquet-format` project contains all Thrift definitions that are necessary to create readers
and writers for Parquet files.

## Motivation

We created Parquet to make the advantages of compressed, efficient columnar data representation available to any project in the Hadoop ecosystem.

Parquet is built from the ground up with complex nested data structures in mind, and uses the [record shredding and assembly algorithm](https://github.com/Parquet/parquet-mr/wiki/The-striping-and-assembly-algorithms-from-the-Dremel-paper) described in the Dremel paper. We believe this approach is superior to simple flattening of nested name spaces.

Parquet is built to support very efficient compression and encoding schemes. Multiple projects have demonstrated the performance impact of applying the right compression and encoding scheme to the data. Parquet allows compression schemes to be specified on a per-column level, and is future-proofed to allow adding more encodings as they are invented and implemented.

Parquet is built to be used by anyone. The Hadoop ecosystem is rich with data processing frameworks, and we are not interested in playing favorites. We believe that an efficient, well-implemented columnar storage substrate should be useful to all frameworks without the cost of extensive and difficult to set up dependencies.

## Modules

The `parquet-format` project contains format specifications and Thrift definitions of metadata required to properly read Parquet files.

The `parquet-mr` project contains multiple sub-modules, which implement the core components of reading and writing a nested, column-oriented data stream, map this core onto the parquet format, and provide Hadoop Input/Output Formats, Pig loaders, and other java-based utilities for interacting with Parquet.

The `parquet-compatibility` project contains compatibility tests that can be used to verify that implementations in different languages can read and write each other's files.

## Building

Java resources can be build using `mvn package.` The current stable version should always be available from Maven Central.

C++ thrift resources can be generated via make.

Thrift can be also code-genned into any other thrift-supported language.

## Glossary
  - Block (hdfs block): This means a block in hdfs and the meaning is 
    unchanged for describing this file format.  The file format is 
    designed to work well on top of hdfs.

  - File: A hdfs file that must include the metadata for the file.
    It does not need to actually contain the data.

  - Row group: A logical horizontal partitioning of the data into rows.
    There is no physical structure that is guaranteed for a row group.
    A row group consists of a column chunk for each column in the dataset.

  - Column chunk: A chunk of the data for a particular column.  These live
    in a particular row group and is guaranteed to be contiguous in the file.

  - Page: Column chunks are divided up into pages.  A page is conceptually
    an indivisible unit (in terms of compression and encoding).  There can
    be multiple page types which is interleaved in a column chunk.

Hierarchically, a file consists of one or more rows groups.  A row group
contains exactly one column chunk per column.  Column chunks contain one or
more pages. 

## Unit of parallelization
  - MapReduce - File/Row Group
  - IO - Column chunk
  - Encoding/Compression - Page

## File format
This file and the thrift definition should be read together to understand the format.

    4-byte magic number "PAR1"
    <Column 1 Chunk 1 + Column Metadata>
    <Column 2 Chunk 1 + Column Metadata>
    ...
    <Column N Chunk 1 + Column Metadata>
    <Column 1 Chunk 2 + Column Metadata>
    <Column 2 Chunk 2 + Column Metadata>
    ...
    <Column N Chunk 2 + Column Metadata>
    ...
    <Column 1 Chunk M + Column Metadata>
    <Column 2 Chunk M + Column Metadata>
    ...
    <Column N Chunk M + Column Metadata>
    File Metadata
    4-byte length in bytes of file metadata
    4-byte magic number "PAR1"

In the above example, there are N columns in this table, split into M row 
groups.  The file metadata contains the locations of all the column metadata 
start locations.  More details on what is contained in the metadata can be found 
in the thrift files.

Metadata is written after the data to allow for single pass writing.

Readers are expected to first read the file metadata to find all the column 
chunks they are interested in.  The columns chunks should then be read sequentially.

 ![File Layout](https://raw.github.com/Parquet/parquet-format/master/doc/images/FileLayout.gif)

## Metadata
There are three types of metadata: file metadata, column (chunk) metadata and page
header metadata.  All thrift structures are serialized using the TCompactProtocol.

 ![Metadata diagram](https://github.com/Parquet/parquet-format/raw/master/doc/images/FileFormat.gif)

## Types
The types supported by the file format are intended to be as minimal as possible,
with a focus on how the types effect on disk storage.  For example, 16-bit ints
are not explicitly supported in the storage format since they are covered by
32-bit ints with an efficient encoding.  This reduces the complexity of implementing
readers and writers for the format.  The types are:
  - BOOLEAN: 1 bit boolean
  - INT32: 32 bit signed ints
  - INT64: 64 bit signed ints
  - INT96: 96 bit signed ints
  - FLOAT: IEEE 32-bit floating point values
  - DOUBLE: IEEE 64-bit floating point values
  - BYTE_ARRAY: arbitrarily long byte arrays.

## Nested Encoding
To encode nested columns, Parquet uses the Dremel encoding with definition and 
repetition levels.  Definition levels specify how many optional fields in the 
path for the column are defined.  Repetition levels specify at what repeated field
in the path has the value repeated.  The max definition and repetition levels can
be computed from the schema (i.e. how much nesting there is).  This defines the
maximum number of bits required to store the levels (levels are defined for all
values in the column).  

Two encodings for the levels are supported in the initial version.  

### Bit-packed (Deprecated) (BIT_PACKED = 4)
The first is a bit-packed only encoding, which is deprecated and will be replaced by the run length ecoding / bit backing hybrid in the next section.
Each value is encoded back to back using a fixed width.
There is no padding between values (except for the last byte) which is padded with 0s.
For example, if the max repetition level was 3 (2 bits) and the max definition level as 3
(2 bits), to encode 30 values, we would have 30 * 2 = 60 bits = 8 bytes.

This implementation is deprecated because the RLE / bit-packing hybrid below is a superset of this implementation.
For compatibility reasons, this implementation packs values from the most significant bit to the least significant bit,
which is not the same as the RLE / bit-packing hybrid below.

For example, the numbers 1 through 7 using bit width 3:  
```
dec value: 0   1   2   3   4   5   6   7
bit value: 000 001 010 011 100 101 110 111
bit label: ABC DEF GHI JKL MNO PQR STU VWX
```
would be encoded like this where spaces mark byte boundaries (3 bytes):  
```
bit value: 00000101 00111001 01110111
bit label: ABCDEFGH IJKLMNOP QRSTUVWX
```

### Run Length Encoding / Bit-Packing Hybrid (RLE = 3)
The second encoding uses a combination of bit-packing and run length encoding to more efficiently store repeated values.

The grammar for this encoding looks like this, given a fixed bit-width known in advance:
```
rle-bit-packed-hybrid: <length> <encoded-data>
length := length of the <encoded-data> in bytes stored as 4 bytes little endian
encoded-data := <run>*
run := <bit-packed-run> | <rle-run>  
bit-packed-run := <bit-packed-header> <bit-packed-values>  
bit-packed-header := varint-encode(<bit-pack-count> << 1 | 1)  
// we always bit-pack a multiple of 8 values at a time, so we only store the number of values / 8  
bit-pack-count := (number of values in this run) / 8  
bit-packed-values := *see 1 below*  
rle-run := <rle-header> <repeated-value>  
rle-header := varint-encode( (number of times repeated) << 1)  
repeated-value := value that is repeated, using a fixed-width of round-up-to-next-byte(bit-width)
```

1. The bit-packing here is done in a different order than the one in the deprecated encoding above.
   The values are packed from the least significant bit of each byte to the most significant bit,
   though the order of the bits in each value remains in the usual order of most significant to least
   significant. For example, to pack the same values as the example in the deprecated encoding above:

   The numbers 1 through 7 using bit width 3:  
   ```
   dec value: 0   1   2   3   4   5   6   7
   bit value: 000 001 010 011 100 101 110 111
   bit label: ABC DEF GHI JKL MNO PQR STU VWX
   ```
   
   would be encoded like this where spaces mark byte boundaries (3 bytes):  
   ```
   bit value: 10001000 11000110 11111010
   bit label: HIDEFABC RMNOJKLG VWXSTUPQ
   ```

   The reason for this packing order is to have fewer word-boundaries on little-endian hardware
   when deserializing more than one byte at at time. This is because 4 bytes can be read into a
   32 bit register (or 8 bytes into a 64 bit register) and values can be unpacked just by
   shifting and ORing with a mask. (to make this optimization work on a big-endian machine,
   you would have to use the ordering used in the deprecated bit-packing encoding)

2. varint-encode() is ULEB-128 encoding, see http://en.wikipedia.org/wiki/Variable-length_quantity

## Nulls
Nullity is encoded in the definition levels (which is run-length encoded).  NULL values 
are not encoded in the data.  For example, in a non-nested schema, a column with 1000 NULLs 
would be encoded with run-length encoding (0, 1000 times) for the definition levels and
nothing else.  

## Data Pages
For data pages, the 3 pieces of information are encoded back to back, after the page
header.  We have the 
 - definition levels data,  
 - repetition levels data, 
 - encoded values.
The size of specified in the header is for all 3 pieces combined.

The data for the data page is always required.  The definition and repetition levels
are optional, based on the schema definition.  If the column is not nested (i.e.
the path to the column has length 1), we do not encode the repetition levels (it would
always have the value 1).  For data that is required, the definition levels are
skipped (if encoded, it will always have the value of the max definition level). 

For example, in the case where the column is non-nested and required, the data in the
page is only the encoded values.

The following encodings are supported:

### Plain encoding (PLAIN = 0)
The plain encoding is used whenever a more efficient encoding can not be used. It 
stores the data in the following format:
 - BOOLEAN: Bit Packed (see above), LSB first
 - INT32: 4 bytes little endian
 - INT64: 8 bytes little endian
 - INT96: 12 bytes little endian
 - FLOAT: 4 bytes IEEE little endian
 - DOUBLE: 8 bytes IEEE little endian
 - BYTE_ARRAY: length in 4 bytes little endian followed by the bytes contained in the array
 - FIXED_LEN_BYTE_ARRAY: the bytes contained in the array

### Dictionary Encoding (PLAIN_DICTIONARY = 2)
The dictionary encoding builds a dictionary of values encountered in a given column. The 
dictionary will be stored in a dictionary page per column chunk. The values are stored as integers
using the RLE/Bit-Packing Hybrid encoding described above. If the dictionary grows too big, whether in size
or number of distinct values, the encoding will fall back to the plain encoding. The dictionary page is 
written first, before the data pages of the column chunk.

Dictionary page format: the entries in the dictionary - in dictionary order - using the plain encoding described above.

Data page format: the bit width used to encode the entry ids stored as 1 byte (max bit width = 32),
followed by the values encoded using RLE/Bit packed described above (with the given bit width).

## Column chunks
Column chunks are composed of pages written back to back.  The pages share a common 
header and readers can skip over page they are not interested in.  The data for the 
page follows the header and can be compressed and/or encoded.  The compression and 
encoding is specified in the page metadata.

## Schema Resolution
Schemas should be resolved by name. Columns from two different schemas are considered
equal if the full path is the same (ignoring case). The type of the columns and field 
repetition type must be identical. If a reader schema contains a column that is not
in file schema, NULLs should be returned for that column.

The name of the root schema object is arbitrary and does not need to be compared.

## Checksumming
Data pages can be individually checksummed.  This allows disabling of checksums at the 
HDFS file level, to better support single row lookups.

## Error recovery
If the file metadata is corrupt, the file is lost.  If the column metdata is corrupt, 
that column chunk is lost (but column chunks for this column in order row groups are 
okay).  If a page header is corrupt, the remaining pages in that chunk are lost.  If 
the data within a page is corrupt, that page is lost.  The file will be more 
resilient to corruption with smaller row groups.

Potential extension: With smaller row groups, the biggest issue is lowing the file 
metadata at the end.  If this happens in the write path, all the data written will 
be unreadable.  This can be fixed by writing the file metadata every Nth row group.  
Each file metadata would be cumulative and include all the row groups written so 
far.  Combining this with the strategy used for rc or avro files using sync markers, 
a reader could recovery partially written files.  

## Separating metadata and column data.
The format is explicitly designed to separate the metadata from the data.  This
allows splitting columns into multiple files as well as having a single metadata
file reference multiple parquet files.  

## Configurations
- Row group size: Larger row groups allow for larger column chunks which makes it 
possible to do larger sequential IO.  Larger groups also require more buffering in 
the write path (or a two pass write).  We recommend large row groups (512MB - 1GB). 
Since an entire row group might need to be read, we want it to completely fit on 
one HDFS block.  Therefore, HDFS block sizes should also be set to be larger.  An 
optimized read setup would be: 1GB row groups, 1GB HDFS block size, 1 HDFS block 
per HDFS file.
- Data page size: Data pages should be considered indivisible so smaller data pages 
allow for more fine grained reading (e.g. single row lookup).  Larger page sizes 
incur less space overhead (less page headers) and potentially less parsing overhead 
(processing headers).  Note: for sequential scans, it is not expected to read a page 
at a time; this is not the IO chunk.  We recommend 8KB for page sizes.

## Extensibility
There are many places in the format for compatible extensions:
- File Version: The file metadata contains a version.
- Encodings: Encodings are specified by enum and more can be added in the future.  
- Page types: Additional page types can be added and safely skipped.

## License
Copyright 2013 Twitter, Cloudera and other contributors.

Licensed under the Apache License, Version 2.0: http://www.apache.org/licenses/LICENSE-2.0
