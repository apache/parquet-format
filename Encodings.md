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

<a name="PLAIN"></a>
### Plain: (PLAIN = 0)

Supported Types: all

This is the plain encoding that must be supported for types.  It is
intended to be the simplest encoding.  Values are encoded back to back.

The plain encoding is used whenever a more efficient encoding can not be used. It
stores the data in the following format:
 - BOOLEAN: [Bit Packed](#BITPACKED), LSB first
 - INT32: 4 bytes little endian
 - INT64: 8 bytes little endian
 - INT96: 12 bytes little endian (deprecated)
 - FLOAT: 4 bytes IEEE little endian
 - DOUBLE: 8 bytes IEEE little endian
 - BYTE_ARRAY: length in 4 bytes little endian followed by the bytes contained in the array
 - FIXED_LEN_BYTE_ARRAY: the bytes contained in the array

For native types, this outputs the data as little endian. Floating
    point types are encoded in IEEE.

For the byte array type, it encodes the length as a 4 byte little
endian, followed by the bytes.

### Dictionary Encoding (PLAIN_DICTIONARY = 2 and RLE_DICTIONARY = 8)
The dictionary encoding builds a dictionary of values encountered in a given column. The
dictionary will be stored in a dictionary page per column chunk. The values are stored as integers
using the [RLE/Bit-Packing Hybrid](#RLE) encoding. If the dictionary grows too big, whether in size
or number of distinct values, the encoding will fall back to the plain encoding. The dictionary page is
written first, before the data pages of the column chunk.

Dictionary page format: the entries in the dictionary using the [plain](#PLAIN) encoding.

Data page format: the bit width used to encode the entry ids stored as 1 byte (max bit width = 32),
followed by the values encoded using RLE/Bit packed described above (with the given bit width).

Using the PLAIN_DICTIONARY enum value is deprecated in the Parquet 2.0 specification. Prefer using RLE_DICTIONARY
in a data page and PLAIN in a dictionary page for Parquet 2.0+ files.

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
   when deserializing more than one byte at at time. This is because 4 bytes can be read into a
   32 bit register (or 8 bytes into a 64 bit register) and values can be unpacked just by
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

Whether prepending the four-byte `length` to the `encoded-data` is summarized as the table below:
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

This is a bit-packed only encoding, which is deprecated and will be replaced by the [RLE/bit-packing](#RLE) hybrid encoding.
Each value is encoded back to back using a fixed width.
There is no padding between values (except for the last byte, which is padded with 0s).
For example, if the max repetition level was 3 (2 bits) and the max definition level as 3
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
["Decoding billions of integers per second through vectorization"](http://arxiv.org/pdf/1209.2137v5.pdf)
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
 * the bitwidth of each block is stored as a byte
 * each miniblock is a list of bit packed ints according to the bit width
   stored at the begining of the block

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
languages (for example by doing all arithmetic in the unsigned domain).

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
