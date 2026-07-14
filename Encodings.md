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

Parquet encoding definitions
====

This file contains the specification of all supported encodings.

Unless otherwise stated in page or encoding documentation, any encoding can be
used with any page type.

### Supported Encodings

For details on current implementation status, see the [Implementation Status](https://parquet.apache.org/docs/file-format/implementationstatus/#encodings) page.

| Encoding type                                    | Encoding enum                                             | Supported Types                                   |
| ------------------------------------------------ | --------------------------------------------------------- | ------------------------------------------------- |
| [Plain](#PLAIN)                                  | PLAIN = 0                                                 | All Physical Types                                |
| [Dictionary Encoding](#DICTIONARY)               | PLAIN_DICTIONARY = 2 (Deprecated) <br> RLE_DICTIONARY = 8 | All Physical Types                                |
| [Run Length Encoding / Bit-Packing Hybrid](#RLE) | RLE = 3                                                   | BOOLEAN, Dictionary Indices                       |
| [Delta Encoding](#DELTAENC)                      | DELTA_BINARY_PACKED = 5                                   | INT32, INT64                                      |
| [Delta-length byte array](#DELTALENGTH)          | DELTA_LENGTH_BYTE_ARRAY = 6                               | BYTE_ARRAY                                        |
| [Delta Strings](#DELTASTRING)                    | DELTA_BYTE_ARRAY = 7                                      | BYTE_ARRAY, FIXED_LEN_BYTE_ARRAY                  |
| [Byte Stream Split](#BYTESTREAMSPLIT)            | BYTE_STREAM_SPLIT = 9                                     | INT32, INT64, FLOAT, DOUBLE, FIXED_LEN_BYTE_ARRAY |

### Deprecated Encodings

| Encoding type                         | Encoding enum  |
| ------------------------------------- | -------------- |
| [Bit-packed (Deprecated)](#BITPACKED) | BIT_PACKED = 4 |


<a name="PLAIN"></a>
### Plain: (PLAIN = 0)

Supported Types: all

This is the plain encoding that must be supported for types.  It is
intended to be the simplest encoding.  Values are encoded back to back.

The plain encoding is used whenever a more efficient encoding cannot be used. It
stores the data in the following format:
 - BOOLEAN: bit-packed, LSB first (using the same packing scheme as the
   [RLE/bit-packing hybrid](#RLE) encoding)
 - INT32: 4 bytes little endian
 - INT64: 8 bytes little endian
 - INT96: 12 bytes little endian (deprecated)
 - FLOAT: 4 bytes IEEE little endian
 - DOUBLE: 8 bytes IEEE little endian
 - BYTE_ARRAY: length in 4 bytes little endian followed by the bytes contained in the array
 - FIXED_LEN_BYTE_ARRAY: the bytes contained in the array

For native types, this outputs the data as little endian. Floating
    point types are encoded in IEEE.

For the byte array type, it encodes the length as a 4-byte little
endian integer, followed by the bytes.

<a name="DICTIONARY"></a>
### Dictionary Encoding (PLAIN_DICTIONARY = 2 and RLE_DICTIONARY = 8)
The dictionary encoding builds a dictionary of values encountered in a given column. The
dictionary will be stored in a dictionary page per column chunk. The values are stored as integers
using the [RLE/Bit-Packing Hybrid](#RLE) encoding. If the dictionary grows too big, whether in size
or number of distinct values, the encoding will fall back to the plain encoding. The dictionary page is
written first, before the data pages of the column chunk.

Dictionary page format: the entries in the dictionary using the [plain](#PLAIN) encoding.

Data page format: the bit width used to encode the entry ids stored as 1 byte (max bit width = 32),
followed by the values encoded using the RLE/Bit-Packing described above (with the given bit width).

Using the `PLAIN_DICTIONARY` enum value is deprecated, use `RLE_DICTIONARY`
in a data page and `PLAIN` in a dictionary page for new Parquet files.

<a name="RLE"></a>
### Run Length Encoding / Bit-Packing Hybrid (RLE = 3)

This encoding uses a combination of bit-packing and run length encoding to more efficiently store repeated values.

The grammar for this encoding looks like this, given a fixed bit-width known in advance:
```
rle-bit-packed-hybrid: <length> <encoded-data>
// length is not always prepended, please check the table below for more detail
length := length of the <encoded-data> in bytes stored as 4 bytes little endian (unsigned int32)
encoded-data := <run>*
run := <bit-packed-run> | <rle-run>
bit-packed-run := <bit-packed-header> <bit-packed-values>
bit-packed-header := varint-encode(<bit-pack-scaled-run-len> << 1 | 1)
// we always bit-pack a multiple of 8 values at a time, so we only store the number of values / 8
bit-pack-scaled-run-len := (bit-packed-run-len) / 8
bit-packed-run-len := *see 3 below*
bit-packed-values := *see 1 below*
rle-run := <rle-header> <repeated-value>
rle-header := varint-encode( (rle-run-len) << 1)
rle-run-len := *see 3 below*
repeated-value := value that is repeated, using a fixed-width of round-up-to-next-byte(bit-width)
```

1. The bit-packing here is done in a different order than the one in the [deprecated bit-packing](#BITPACKED) encoding.
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
   when deserializing more than one byte at a time. This is because 4 bytes can be read into a
   32-bit register (or 8 bytes into a 64-bit register) and values can be unpacked just by
   shifting and ORing with a mask. (to make this optimization work on a big-endian machine,
   you would have to use the ordering used in the [deprecated bit-packing](#BITPACKED) encoding)

2. varint-encode() is ULEB-128 encoding, see https://en.wikipedia.org/wiki/LEB128

3. bit-packed-run-len and rle-run-len must be in the range \[1, 2<sup>31</sup> - 1\].
   This means that a Parquet implementation can always store the run length in a signed
   32-bit integer. This length restriction was not part of the Parquet 2.5.0 and earlier
   specifications, but longer runs were not readable by the most common Parquet
   implementations so, in practice, were not safe for Parquet writers to emit.


Note that the RLE encoding method is only supported for the following types of
data:

* Repetition and definition levels
* Dictionary indices
* Boolean values in data pages, as an alternative to PLAIN encoding

Whether or not to prepend the four-byte `length` to the `encoded-data` is summarized in the table below:
```
+--------------+------------------------+-----------------+
| Page kind    | RLE-encoded data kind  | Prepend length? |
+--------------+------------------------+-----------------+
| Data page v1 | Definition levels      | Y               |
|              | Repetition levels      | Y               |
|              | Dictionary indices     | N               |
|              | Boolean values         | Y               |
+--------------+------------------------+-----------------+
| Data page v2 | Definition levels      | N               |
|              | Repetition levels      | N               |
|              | Dictionary indices     | N               |
|              | Boolean values         | Y               |
+--------------+------------------------+-----------------+
```

<a name="BITPACKED"></a>
### Bit-packed (Deprecated) (BIT_PACKED = 4)

This is a bit-packed only encoding, which is deprecated; it has been replaced by the [RLE/bit-packing](#RLE) hybrid encoding.
Each value is encoded back to back using a fixed width.
There is no padding between values (except for the last byte, which is padded with 0s).
For example, if the max repetition level was 3 (2 bits) and the max definition level was 3
(2 bits), to encode 30 values, we would have 30 * 2 = 60 bits = 8 bytes.

This implementation is deprecated because the [RLE/bit-packing](#RLE) hybrid is a superset of this implementation.
For compatibility reasons, this implementation packs values from the most significant bit to the least significant bit,
which is not the same as the [RLE/bit-packing](#RLE) hybrid.

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

Note that the BIT_PACKED encoding method is only supported for encoding
repetition and definition levels.

<a name="DELTAENC"></a>
### Delta Encoding (DELTA_BINARY_PACKED = 5)
Supported Types: INT32, INT64

This encoding is adapted from the Binary packing described in
["Decoding billions of integers per second through vectorization"](https://arxiv.org/pdf/1209.2137v5.pdf)
by D. Lemire and L. Boytsov.

In delta encoding we make use of variable length integers for storing various
numbers (not the deltas themselves). For unsigned values, we use ULEB128,
which is the unsigned version of LEB128 (https://en.wikipedia.org/wiki/LEB128#Unsigned_LEB128).
For signed values, we use zigzag encoding (https://developers.google.com/protocol-buffers/docs/encoding#signed-integers)
to map negative values to positive ones and apply ULEB128 on the result.

Delta encoding consists of a header followed by blocks of delta encoded values
binary packed. Each block is made of miniblocks, each of them binary packed with its own bit width.

The header is defined as follows:
```
<block size in values> <number of miniblocks in a block> <total value count> <first value>
```
 * the block size is a multiple of 128; it is stored as a ULEB128 int
 * the miniblock count per block is a divisor of the block size such that their
   quotient, the number of values in a miniblock, is a multiple of 32; it is
   stored as a ULEB128 int
 * the total value count is stored as a ULEB128 int
 * the first value is stored as a zigzag ULEB128 int

Each block contains
```
<min delta> <list of bitwidths of miniblocks> <miniblocks>
```
 * the min delta is a zigzag ULEB128 int (we compute a minimum as we need
   positive integers for bit packing)
 * the bitwidth of each miniblock is stored as a byte
 * each miniblock is a list of bit-packed ints according to the bit width
   stored at the beginning of the block

To encode a block, we will:

1. Compute the differences between consecutive elements. For the first
   element in the block, use the last element in the previous block or, in
   the case of the first block, use the first value of the whole sequence,
   stored in the header.

2. Compute the frame of reference (the minimum of the deltas in the block).
   Subtract this min delta from all deltas in the block. This guarantees that
   all values are non-negative.

3. Encode the frame of reference (min delta) as a zigzag ULEB128 int followed
   by the bit widths of the miniblocks and the delta values (minus the min
   delta) bit-packed per miniblock.

Having multiple blocks allows us to adapt to changes in the data by changing
the frame of reference (the min delta) which can result in smaller values
after the subtraction which, again, means we can store them with a lower bit width.

If there are not enough values to fill the last miniblock, we pad the miniblock
so that its length is always the number of values in a full miniblock multiplied
by the bit width. The values of the padding bits should be zero, but readers
must accept paddings consisting of arbitrary bits as well.

If, in the last block, less than ```<number of miniblocks in a block>```
miniblocks are needed to store the values, the bytes storing the bit widths
of the unneeded miniblocks are still present, their value should be zero,
but readers must accept arbitrary values as well. There are no additional
padding bytes for the miniblock bodies though, as if their bit widths were 0
(regardless of the actual byte values). The reader knows when to stop reading
by keeping track of the number of values read.

Subtractions in steps 1) and 2) may incur signed arithmetic overflow, and so
will the corresponding additions when decoding. Overflow should be allowed
and handled as wrapping around in 2's complement notation so that the original
values are correctly restituted. This may require explicit care in some programming
languages (for example by doing all arithmetic in the unsigned domain). Writers
must not use more bits when bit packing the miniblock data than would be required
to PLAIN encode the physical type (e.g. INT32 data must not use more than 32 bits).

The following examples use 8 as the block size to keep the examples short,
but in real cases it would be invalid.

#### Example 1
1, 2, 3, 4, 5

After step 1), we compute the deltas as:

1, 1, 1, 1

The minimum delta is 1 and after step 2, the relative deltas become:

0, 0, 0, 0

The final encoded data is:

 header:
8 (block size), 1 (miniblock count), 5 (value count), 1 (first value)

 block:
1 (minimum delta), 0 (bitwidth), (no data needed for bitwidth 0)

#### Example 2
7, 5, 3, 1, 2, 3, 4, 5, the deltas would be

-2, -2, -2, 1, 1, 1, 1

The minimum is -2, so the relative deltas are:

0, 0, 0, 3, 3, 3, 3

The encoded data is

 header:
8 (block size), 1 (miniblock count), 8 (value count), 7 (first value)

 block:
-2 (minimum delta), 2 (bitwidth), 00000011111111b (0,0,0,3,3,3,3 packed on 2 bits)

#### Characteristics
This encoding is similar to the [RLE/bit-packing](#RLE) encoding. However the [RLE/bit-packing](#RLE) encoding is specifically used when the range of ints is small over the entire page, as is true of repetition and definition levels. It uses a single bit width for the whole page.
The delta encoding algorithm described above stores a bit width per miniblock and is less sensitive to variations in the size of encoded integers. It is also somewhat doing RLE encoding as a block containing all the same values will be bit packed to a zero bit width thus being only a header.

<a name="DELTALENGTH"></a>
### Delta-length byte array: (DELTA_LENGTH_BYTE_ARRAY = 6)

Supported Types: BYTE_ARRAY

This encoding is always preferred over PLAIN for byte array columns.

For this encoding, we will take all the byte array lengths and encode them using delta
encoding (DELTA_BINARY_PACKED). The byte array data follows all of the length data just
concatenated back to back. The expected savings is from the cost of encoding the lengths
and possibly better compression in the data (it is no longer interleaved with the lengths).

The data stream looks like:
```
<Delta Encoded Lengths> <Byte Array Data>
```

For example, if the data was "Hello", "World", "Foobar", "ABCDEF"

then the encoded data would be comprised of the following segments:
- DeltaEncoding(5, 5, 6, 6) (the string lengths)
- "HelloWorldFoobarABCDEF"

<a name="DELTASTRING"></a>
### Delta Strings: (DELTA_BYTE_ARRAY = 7)

Supported Types: BYTE_ARRAY, FIXED_LEN_BYTE_ARRAY

This is also known as incremental encoding or front compression: for each element in a
sequence of strings, store the prefix length of the previous entry plus the suffix.

For a longer description, see https://en.wikipedia.org/wiki/Incremental_encoding.

This is stored as a sequence of delta-encoded prefix lengths (DELTA_BINARY_PACKED), followed by
the suffixes encoded as delta length byte arrays (DELTA_LENGTH_BYTE_ARRAY).

For example, if the data was "axis", "axle", "babble", "babyhood"

then the encoded data would be comprised of the following segments:
- DeltaEncoding(0, 2, 0, 3) (the prefix lengths)
- DeltaEncoding(4, 2, 6, 5) (the suffix lengths)
- "axislebabbleyhood"

Note that, even for FIXED_LEN_BYTE_ARRAY, all lengths are encoded despite the redundancy.

<a name="BYTESTREAMSPLIT"></a>
### Byte Stream Split: (BYTE_STREAM_SPLIT = 9)

Supported Types: FLOAT, DOUBLE, INT32, INT64, FIXED_LEN_BYTE_ARRAY

This encoding does not reduce the size of the data but can lead to a significantly better
compression ratio and speed when a compression algorithm is used afterwards.

This encoding creates K byte-streams of length N where K is the size in bytes of the data
type and N is the number of elements in the data sequence. For example, K is 4 for FLOAT
type and 8 for DOUBLE type.

The bytes of each value are scattered to the corresponding streams. The 0-th byte goes to the
0-th stream, the 1-st byte goes to the 1-st stream and so on.
The streams are concatenated in the following order: 0-th stream, 1-st stream, etc.
The total length of encoded streams is K * N bytes. Because it does not have any metadata
to indicate the total length, the end of the streams is also the end of data page. No padding
is allowed inside the data page.

Example:
Original data is three 32-bit floats and for simplicity we look at their raw representation.
```
       Element 0      Element 1      Element 2
Bytes  AA BB CC DD    00 11 22 33    A3 B4 C5 D6
```
After applying the transformation, the data has the following representation:
```
Bytes  AA 00 A3 BB 11 B4 CC 22 C5 DD 33 D6
```

<a name="PFOR"></a>
### Patched Frame of Reference (PFOR = 11)

Supported Types: INT32, INT64

PFOR (Patched Frame of Reference) compresses integer columns by subtracting the
minimum value (Frame of Reference), then bit-packing the deltas at an optimal
bit width selected by a cost model. Values that do not fit in the chosen bit width
are stored as exceptions ("patches"). The cost model trades off narrower bit-packing
against the overhead of storing exceptions, achieving better compression than plain
FOR when a few outlier values would otherwise inflate the bit width.

#### Overview

PFOR encoding consists of a page-level header followed by an offset array and one
or more encoded vectors (batches of values). Each vector contains up to
`vector_size` elements (default 1024).

```
+-------------+-----------------------------+--------------------------------------+
|   Header    |        Offset Array         |            Vector Data               |
|  (7 bytes)  |   (num_vectors * 4 bytes)   |            (variable)                |
+-------------+------+------+-----+---------+----------+----------+-----+----------+
| Page Header | off0 | off1 | ... | off N-1 | Vector 0 | Vector 1 | ... | Vec N-1  |
|  (7 bytes)  | (4B) | (4B) |     |  (4B)   |(variable)|(variable)|     |(variable)|
+-------------+------+------+-----+---------+----------+----------+-----+----------+
```

The compression pipeline for each vector is:

```
                    Input: integer array
                              |
                              v
    +----------------------------------------------------------+
    |  1. FRAME OF REFERENCE (FOR)                             |
    |     min_val = min(values[])                              |
    |     delta[i] = (unsigned)(values[i] - min_val)           |
    +----------------------------------------------------------+
                              |
                              v
    +----------------------------------------------------------+
    |  2. COST-MODEL BIT WIDTH SELECTION                       |
    |     For each candidate bit_width b:                      |
    |       total_cost = packing_cost + exception_cost         |
    |     Select b that minimizes total_cost                   |
    +----------------------------------------------------------+
                              |
                              v
    +----------------------------------------------------------+
    |  3. EXCEPTION EXTRACTION                                 |
    |     Values exceeding mask are exceptions                 |
    |     Replace with 0 placeholder in delta array            |
    +----------------------------------------------------------+
                              |
                              v
    +----------------------------------------------------------+
    |  4. BIT PACKING                                          |
    |     Pack each delta into bit_width bits                  |
    +----------------------------------------------------------+
                              |
                              v
                   Output: Serialized vector bytes
```

#### Page Layout

##### Header (7 bytes)

All multi-byte values are little-endian.

```
 Byte:    0              1               2              3    4    5    6
       +----------------+---------------+--------------+----+----+----+----+
       | packing        | log_vector    | value_byte   |     num_elements  |
       | _mode          | _size         | _width       |     (uint32 LE)   |
       +----------------+---------------+--------------+----+----+----+----+
```

| Offset | Field | Size | Type | Description |
|--------|-------|------|------|-------------|
| 0 | packing_mode | 1 byte | uint8 | Packing mode (must be 0 = FOR + bit-packing) |
| 1 | log_vector_size | 1 byte | uint8 | log2(vector\_size). Must be in \[3, 15\]. Default: 10 (vector size 1024) |
| 2 | value_byte_width | 1 byte | uint8 | Bytes per integer value: 4 (INT32) or 8 (INT64) |
| 3 | num_elements | 4 bytes | uint32 | Total number of integer values in the page |

The number of vectors is `ceil(num_elements / vector_size)`. The last vector may
contain fewer than `vector_size` elements.

**Note:** The `value_byte_width` field makes pages self-describing. While the
column type is available from the Parquet schema, including it in the header
enables independent validation and debugging without schema context.

**Note:** The number of elements per vector and the packed data size are NOT stored
in the header. They are derived:
* Elements per vector: `vector_size` for all vectors except the last, which may be smaller.
* Packed data size: `ceil(num_elements_in_vector * bit_width / 8)`.

##### Offset Array

Immediately following the header is an array of `num_vectors` little-endian uint32
values. Each offset gives the byte position of the corresponding vector's data,
measured from the start of the offset array itself.

The first offset equals `num_vectors * 4` (pointing just past the offset array).
Each subsequent offset equals the previous offset plus the stored size of the
previous vector.

##### Vector Format

Each vector is self-describing and contains the FOR metadata, bit-packed delta
values, and exception data.

```
+-------------------+-------------------+---------------------+-------------------+
|   PforVectorInfo  |   PackedValues    | ExceptionPositions  | ExceptionValues   |
|   (7B or 11B)     |    (variable)     |     (variable)      |    (variable)     |
+-------------------+-------------------+---------------------+-------------------+
```

Vector header sizes:
| Type   | PforVectorInfo | Total Header |
|--------|----------------|--------------|
| INT32  | 7 bytes        | 7 bytes      |
| INT64  | 11 bytes       | 11 bytes     |

Data section sizes:
| Section             | Size Formula                              | Description                  |
|---------------------|-------------------------------------------|------------------------------|
| PackedValues        | ceil(N * bit\_width / 8)                  | Bit-packed delta values      |
| ExceptionPositions  | num\_exceptions * 2 bytes                 | uint16 indices of exceptions |
| ExceptionValues     | num\_exceptions * value\_byte\_width bytes | Original integer values      |

###### PforVectorInfo for INT32 (7 bytes)

```
 Byte:    0    1    2    3       4          5       6
       +----+----+----+----+-----------+---------+---------+
       | frame_of_reference | bit_width |  num_exceptions   |
       |    (int32 LE)      |  (uint8)  |   (uint16 LE)     |
       +----+----+----+----+-----------+---------+---------+
```

| Offset | Field | Size | Type | Description |
|--------|-------|------|------|-------------|
| 0 | frame_of_reference | 4 bytes | int32 | Minimum value in the vector |
| 4 | bit_width | 1 byte | uint8 | Bits per packed delta value. Range: \[0, 32\]. |
| 5 | num_exceptions | 2 bytes | uint16 | Number of exception values in this vector. |

###### PforVectorInfo for INT64 (11 bytes)

```
 Byte:    0    1    2    3    4    5    6    7       8          9      10
       +----+----+----+----+----+----+----+----+-----------+---------+---------+
       |          frame_of_reference           | bit_width |  num_exceptions   |
       |              (int64 LE)               |  (uint8)  |   (uint16 LE)     |
       +----+----+----+----+----+----+----+----+-----------+---------+---------+
```

| Offset | Field | Size | Type | Description |
|--------|-------|------|------|-------------|
| 0 | frame_of_reference | 8 bytes | int64 | Minimum value in the vector |
| 8 | bit_width | 1 byte | uint8 | Bits per packed delta value. Range: \[0, 64\]. |
| 9 | num_exceptions | 2 bytes | uint16 | Number of exception values in this vector. |

###### PackedValues

The FOR-encoded deltas, bit-packed into `ceil(num_elements_in_vector * bit_width / 8)` bytes.
Values are packed from the least significant bit of each byte to the most significant bit,
in groups of 8 values, using the same bit-packing order as the
[RLE/Bit-Packing Hybrid](#RLE) encoding.

Exception positions contain 0 as a placeholder in the packed data. The actual
exception values are stored separately and patched during decoding.

If `bit_width` is 0, no bytes are stored (all deltas are zero, meaning all values
are equal to `frame_of_reference` and there are no exceptions).

###### ExceptionPositions

An array of `num_exceptions` little-endian uint16 values, each giving
the 0-based index within the vector of an exception value.

###### ExceptionValues

An array of `num_exceptions` values in the original integer type
(4 bytes little-endian for INT32, 8 bytes for INT64), stored in
the same order as the corresponding positions. These are the **original**
integer values (not FOR offsets).

#### Encoding

##### Frame of Reference

The frame of reference is the minimum value in the vector:

```
frame_of_reference = min(values[])
delta[i] = (unsigned)(values[i] - frame_of_reference)
```

All deltas are non-negative. The unsigned cast prevents signed overflow when
values span a large range (e.g., INT32\_MIN to INT32\_MAX).

##### Cost-Model Bit Width Selection

The cost model evaluates every candidate bit width and selects the one that
minimizes total encoded size. This is the key difference from plain FOR encoding,
which always uses the bit width of the maximum delta.

**Algorithm:**

1. Build a histogram `H[b]` where `H[b]` = number of deltas requiring exactly
   `b` bits (using `bits_required(delta) = ceil(log2(delta + 1))`, with
   `bits_required(0) = 0`).

2. For each candidate bit width `b` from 0 to `max_bits` (32 for INT32, 64
   for INT64):

   ```
   num_exceptions_b = sum(H[k] for k = b+1 to max_bits)
   packing_cost     = num_elements * b
   exception_cost   = num_exceptions_b * (16 + value_byte_width * 8)
   total_cost_b     = packing_cost + exception_cost
   ```

   Where:
   * `16` = bits for exception position (uint16)
   * `value_byte_width * 8` = bits for exception value (32 or 64)

3. Select the bit width `b` that minimizes `total_cost_b`.

**Implementation note:** The histogram can be accumulated incrementally. Starting
from `b = max_bits` and working downward, `num_exceptions` accumulates as each
bit width bucket is passed. This makes the search O(max\_bits).

##### Exception Extraction

After selecting the optimal bit width:

1. Compute `mask = (1 << bit_width) - 1` (for bit\_width < max\_bits; if
   bit\_width equals max\_bits, there are no exceptions).
2. For each delta where `delta[i] > mask`:
   * Record the position `i` in the exception positions array.
   * Record the **original value** `values[i]` in the exception values array.
   * Replace `delta[i]` with 0 in the delta array (placeholder for bit-packing).

##### Bit-Packing

Pack the deltas (with exception placeholders set to 0) using `bit_width` bits
per value. The packing order is LSB-first in groups of 8, matching the
[RLE/Bit-Packing Hybrid](#RLE) encoding.

#### Decoding

```
                    Input: Serialized vector bytes
                              |
                              v
    +----------------------------------------------------------+
    |  1. BIT UNPACKING                                        |
    |     Unpack num_elements values at bit_width bits each    |
    +----------------------------------------------------------+
                              |
                              v
    +----------------------------------------------------------+
    |  2. REVERSE FOR                                          |
    |     values[i] = delta[i] + frame_of_reference            |
    +----------------------------------------------------------+
                              |
                              v
    +----------------------------------------------------------+
    |  3. PATCH EXCEPTIONS                                     |
    |     values[pos[j]] = exception_values[j]                 |
    +----------------------------------------------------------+
                              |
                              v
                  Output: Original integer array
```

For each vector:

1. Read PforVectorInfo from the vector header.
2. Unpack `bit_width`-bit unsigned integers from PackedValues.
3. Add `frame_of_reference` to each unpacked integer (signed addition).
4. Patch exceptions: for each (position, value) in the exception arrays,
   overwrite the decoded output at that position with the stored value.

**Special case:** If `bit_width == 0` and `num_exceptions == 0`, all values
equal `frame_of_reference`. Fill the output array and return.

#### Example 1: Integer Keys with an Outlier

**Input:** `int32 values[8] = { 100, 102, 101, 103, 100, 99, 50000, 104 }`

**Step 1: Frame of Reference**

min\_val = 99, deltas = \[1, 3, 2, 4, 1, 0, 49901, 5\]

**Step 2: Cost Model**

| Bit Width | Packing Cost | Exceptions | Exception Cost | Total Cost |
|-----------|-------------|------------|----------------|------------|
| 3         | 24 bits     | 1          | 48 bits        | 72 bits    |
| 16        | 128 bits    | 0          | 0 bits         | 128 bits   |

The cost model selects bit\_width = 3 (72 bits < 128 bits).

**Step 3: Exception Extraction**

mask = 7 (for bit\_width = 3). Value 50000 at index 6 has delta 49901 > 7.
* Exception position: \[6\]
* Exception value: \[50000\] (original value)
* Delta array with placeholder: \[1, 3, 2, 4, 1, 0, **0**, 5\]

**Step 4: Bit Packing**

8 values at 3 bits each = 3 bytes.

**Serialized Vector:**

| Section             | Content                                 | Size     |
|---------------------|-----------------------------------------|----------|
| PforVectorInfo      | for=99, bit\_width=3, num\_exceptions=1 | 7 bytes  |
| PackedValues        | \[1, 3, 2, 4, 1, 0, 0, 5\] at 3 bits   | 3 bytes  |
| ExceptionPositions  | \[6\]                                   | 2 bytes  |
| ExceptionValues     | \[50000\]                               | 4 bytes  |
| **Total**           |                                         | **16 bytes** |

Compared to PLAIN encoding (8 * 4 = 32 bytes). Plain FOR would use
bit\_width = 16 (to fit 49901), costing 7 + 16 = 23 bytes. PFOR saves 7 bytes
by accepting one exception.

#### Example 2: Uniform Data (No Exceptions)

**Input:** `int32 values[1024]` where all values are between 1000 and 1255.

min\_val = 1000, max\_delta = 255, bit\_width = 8 (same as plain FOR).
No exceptions. PFOR produces identical output to plain FOR encoding.

**Serialized Page:**

| Section          | Size          |
|------------------|---------------|
| Header           | 7 bytes       |
| Offset Array     | 4 bytes       |
| PforVectorInfo   | 7 bytes       |
| PackedValues     | 1,024 bytes   |
| **Total**        | **1,042 bytes** |

Compared to PLAIN encoding (1024 * 4 = 4,096 bytes) -- 3.9x compression.

#### Example 3: Date Key Column (TPC-DS pattern)

1024 date key values (INT32) ranging from 2,450,815 to 2,453,005 with a few
outlier keys at 2,415,022 (null sentinel) interspersed.

| Metric        | Value       | Calculation                                 |
|---------------|-------------|---------------------------------------------|
| FOR min       | 2,415,022   | The null sentinel is the minimum             |
| Max delta     | 37,983      | 2,453,005 - 2,415,022                       |
| Plain FOR bw  | 16          | ceil(log2(37984)) = 16 bits                 |
| PFOR bw       | 11          | ceil(log2(2191)) = 11 for range 2450815-2453005 |
| Exceptions    | ~10         | The null sentinel outliers                   |

**Size Comparison:**

| Encoding      | Packed + Exc | Overhead | Total        | Ratio  |
|---------------|-------------|----------|--------------|--------|
| PLAIN         | 4,096 B     | 0 B      | 4,096 bytes  | 1.0x   |
| Plain FOR     | 2,048 B     | 7 B      | 2,055 bytes  | 0.50x  |
| PFOR          | 1,408 B     | 67 B     | 1,482 bytes  | 0.36x  |

PFOR achieves 28% better compression than plain FOR by narrowing the bit width
from 16 to 11 and storing 10 exceptions.

#### Characteristics

| Property       | Description                                                                          |
|----------------|--------------------------------------------------------------------------------------|
| Lossless       | All original integer values are perfectly recoverable                                |
| Adaptive       | Cost model selects optimal bit width per vector based on data distribution           |
| Vectorized     | Fixed-size vectors enable SIMD-optimized bit packing/unpacking                       |
| Exception-safe | Outlier values are stored separately without inflating bit width                     |

**Best use cases:**

* Integer columns with mostly narrow range but occasional outliers
* Foreign key columns (date keys, store keys, customer keys)
* Sequence IDs with gaps or sentinel values
* Columns where DELTA\_BINARY\_PACKED is suboptimal (non-sequential data)

**Worst case scenarios:**

* Uniformly distributed random integers (no outliers to exploit)
* Very small datasets (header overhead dominates)
* Data where all values require the same bit width (PFOR reduces to plain FOR)

**Comparison with other encodings:**

| Encoding              | Type Support | Compression | Best For                   |
|-----------------------|--------------|-------------|----------------------------|
| PLAIN                 | All          | None        | General purpose            |
| DELTA\_BINARY\_PACKED | Int32/Int64  | High        | Sequential/sorted integers |
| PFOR                  | Int32/Int64  | High        | Clustered with outliers    |
| ALP                   | Float/Double | High        | Decimal-like floats        |

PFOR and [DELTA\_BINARY\_PACKED](#DELTA) are complementary: DELTA\_BINARY\_PACKED
excels on sorted or sequential data where successive differences are small, while
PFOR excels on data with a tight cluster and a few outliers. PFOR does not compute
deltas between successive values -- it operates on absolute values relative to
the minimum.

#### Size Calculations

##### Vector Size Formula

```
vector_bytes = vector_header_size                           // INT32: 7, INT64: 11
             + ceil(num_elements * bit_width / 8)           // packed values
             + num_exceptions * 2                           // exception positions (uint16)
             + num_exceptions * value_byte_width            // exception values (4 or 8)
```

##### Page Size Formula

```
page_bytes = 7                                   // page header
           + num_vectors * 4                     // offset array
           + sum(vector_bytes for each vector)   // all vectors
```

#### Constants Reference

| Constant            | Value   | Description                             |
|---------------------|---------|-----------------------------------------|
| Vector size         | 1024    | Default elements per compressed vector  |
| INT32 max bit width | 32      | Maximum bits for uint32 delta           |
| INT64 max bit width | 64      | Maximum bits for uint64 delta           |
| Max exceptions      | 65,535  | uint16 limit per vector                 |
