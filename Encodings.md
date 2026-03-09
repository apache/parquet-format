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
 * the bitwidth of each block is stored as a byte
 * each miniblock is a list of bit packed ints according to the bit width
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

<a name="ALP"></a>
### Adaptive Lossless floating-Point: (ALP = 10)

Supported Types: FLOAT, DOUBLE

This encoding is adapted from the paper
["ALP: Adaptive Lossless floating-Point Compression"](https://dl.acm.org/doi/10.1145/3626717)
by Afroozeh and Boncz (SIGMOD 2024).

ALP works by converting floating-point values to integers using decimal scaling,
then applying Frame of Reference (FOR) encoding and bit-packing. Values that
cannot be losslessly converted are stored as exceptions. The encoding achieves
high compression for decimal-like floating-point data (e.g., monetary values,
sensor readings) while remaining fully lossless.

#### Overview

ALP encoding consists of a page-level header followed by an offset array and one
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
                    Input: float/double array
                              |
                              v
    +----------------------------------------------------------+
    |  1. SAMPLING & PRESET GENERATION                         |
    |     Sample vectors from column chunk                     |
    |     Try all (exponent, factor) combinations              |
    |     Select best k combinations for preset                |
    +----------------------------------------------------------+
                              |
                              v
    +----------------------------------------------------------+
    |  2. DECIMAL ENCODING                                     |
    |     encoded[i] = round(value[i] * 10^e * 10^(-f))       |
    |     Detect exceptions where decode(encode(v)) != v       |
    +----------------------------------------------------------+
                              |
                              v
    +----------------------------------------------------------+
    |  3. FRAME OF REFERENCE (FOR)                             |
    |     min_val = min(encoded[])                             |
    |     delta[i] = encoded[i] - min_val                      |
    +----------------------------------------------------------+
                              |
                              v
    +----------------------------------------------------------+
    |  4. BIT PACKING                                          |
    |     bit_width = ceil(log2(max_delta + 1))                |
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
       | compression    | integer       | log_vector   |     num_elements  |
       | _mode          | _encoding     | _size        |     (int32 LE)    |
       +----------------+---------------+--------------+----+----+----+----+
```

| Offset | Field | Size | Type | Description |
|--------|-------|------|------|-------------|
| 0 | compression_mode | 1 byte | uint8 | Compression mode (must be 0 = ALP) |
| 1 | integer_encoding | 1 byte | uint8 | Integer encoding (must be 0 = FOR + bit-packing) |
| 2 | log_vector_size | 1 byte | uint8 | log2(vector\_size). Must be in \[3, 15\]. Default: 10 (vector size 1024) |
| 3 | num_elements | 4 bytes | int32 | Total number of floating-point values in the page |

The number of vectors is `ceil(num_elements / vector_size)`. The last vector may
contain fewer than `vector_size` elements.

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

Each vector is self-describing and contains the encoding parameters, FOR metadata,
bit-packed encoded values, and exception data.

```
+-------------------+-----------------+-------------------+---------------------+-------------------+
|      AlpInfo      |     ForInfo     |   PackedValues    | ExceptionPositions  | ExceptionValues   |
|     (4 bytes)     | (5B or 9B)      |    (variable)     |     (variable)      |    (variable)     |
+-------------------+-----------------+-------------------+---------------------+-------------------+
```

Vector header sizes:
| Type   | AlpInfo | ForInfo | Total Header |
|--------|---------|---------|--------------|
| FLOAT  | 4 bytes | 5 bytes | 9 bytes      |
| DOUBLE | 4 bytes | 9 bytes | 13 bytes     |

Data section sizes:
| Section             | Size Formula                | Description                  |
|---------------------|-----------------------------|------------------------------|
| PackedValues        | ceil(N * bit\_width / 8)    | Bit-packed delta values      |
| ExceptionPositions  | num\_exceptions * 2 bytes   | uint16 indices of exceptions |
| ExceptionValues     | num\_exceptions * sizeof(T) | Original float/double values |

###### AlpInfo (4 bytes, both types)

```
 Byte:    0           1          2       3
       +----------+----------+---------+---------+
       | exponent |  factor  |  num_exceptions   |
       |  (uint8) | (uint8)  |   (uint16 LE)     |
       +----------+----------+---------+---------+
```

| Offset | Field | Size | Type | Description |
|--------|-------|------|------|-------------|
| 0 | exponent | 1 byte | uint8 | Power-of-10 exponent *e*. Range: \[0, 10\] for FLOAT, \[0, 18\] for DOUBLE. |
| 1 | factor | 1 byte | uint8 | Power-of-10 factor *f*. Range: \[0, *e*\]. |
| 2 | num_exceptions | 2 bytes | uint16 | Number of exception values in this vector. |

###### ForInfo for FLOAT (5 bytes)

```
 Byte:    0    1    2    3       4
       +----+----+----+----+-----------+
       | frame_of_reference | bit_width |
       |    (int32 LE)      |  (uint8)  |
       +----+----+----+----+-----------+
```

| Offset | Field | Size | Type | Description |
|--------|-------|------|------|-------------|
| 0 | frame_of_reference | 4 bytes | int32 | Minimum encoded integer in the vector |
| 4 | bit_width | 1 byte | uint8 | Bits per packed value. Range: \[0, 32\]. |

###### ForInfo for DOUBLE (9 bytes)

```
 Byte:    0    1    2    3    4    5    6    7       8
       +----+----+----+----+----+----+----+----+-----------+
       |          frame_of_reference           | bit_width |
       |              (int64 LE)               |  (uint8)  |
       +----+----+----+----+----+----+----+----+-----------+
```

| Offset | Field | Size | Type | Description |
|--------|-------|------|------|-------------|
| 0 | frame_of_reference | 8 bytes | int64 | Minimum encoded long in the vector |
| 8 | bit_width | 1 byte | uint8 | Bits per packed value. Range: \[0, 64\]. |

###### PackedValues

The FOR-encoded deltas, bit-packed into `ceil(num_elements_in_vector * bit_width / 8)` bytes.
Values are packed from the least significant bit of each byte to the most significant bit,
in groups of 8 values, using the same bit-packing order as the
[RLE/Bit-Packing Hybrid](#RLE) encoding.

If `bit_width` is 0, no bytes are stored (all deltas are zero, meaning all encoded
integers are equal to `frame_of_reference`).

###### ExceptionPositions

An array of `num_exceptions` little-endian uint16 values, each giving
the 0-based index within the vector of an exception value.

###### ExceptionValues

An array of `num_exceptions` values in the original floating-point type
(4 bytes little-endian IEEE 754 for FLOAT, 8 bytes for DOUBLE), stored in
the same order as the corresponding positions.

#### Encoding

##### Encoding Formula

```
+-------------------------------------------------------------------+
|                                                                   |
|   encoded = round( value  *  10^e  *  10^(-f) )                  |
|                                                                   |
|   decoded = encoded  *  10^f  *  10^(-e)                          |
|                                                                   |
+-------------------------------------------------------------------+
```

The encoding uses two separate multiplications (not a single multiplication by
`10^(e-f)`, and not division) to ensure that implementations produce identical
floating-point rounding across languages. The powers of 10 MUST be stored as
precomputed floating-point constants (i.e., literal values like `1e-3f`), not
computed at runtime.

##### Fast Rounding

The rounding function uses a "magic number" technique for branchless rounding:

| Type   | Magic Number                      | Formula                          |
|--------|-----------------------------------|----------------------------------|
| FLOAT  | 2^22 + 2^23 = 12,582,912         | `(int)((value + magic) - magic)` |
| DOUBLE | 2^51 + 2^52 = 6,755,399,441,055,744 | `(long)((value + magic) - magic)` |

For negative values, the signs are reversed: `(int)((value - magic) + magic)`.

##### Parameter Selection

The encoder selects the (exponent, factor) pair that minimizes exceptions.
Valid combinations satisfy 0 &le; factor &le; exponent:

| Type   | Max Exponent | Total Combinations |
|--------|--------------|--------------------|
| FLOAT  | 10           | 66                 |
| DOUBLE | 18           | 190                |

To avoid the cost of exhaustive search on every vector, implementations
SHOULD use sampling to select up to 5 candidate (exponent, factor)
combinations (the "encoding preset") at the start of each column chunk.
Each vector then searches only those 5 candidates.

Sampling parameters:

| Parameter            | Value | Description                         |
|----------------------|-------|-------------------------------------|
| Vector Size          | 1024  | Elements compressed as a unit       |
| Sample Size          | 256   | Values sampled per vector           |
| Max Combinations     | 5     | Best (e,f) pairs kept in preset     |
| Sample Vectors       | 8     | Vectors sampled per row group       |

##### Exception Detection

A value becomes an exception if any of the following is true:

| Condition          | Example                    | Reason                           |
|--------------------|----------------------------|----------------------------------|
| NaN                | `NaN`                      | Cannot convert to integer        |
| Infinity           | `+Inf`, `-Inf`             | Cannot convert to integer        |
| Negative zero      | `-0.0`                     | Would become `+0.0` after encoding |
| Out of range       | value * 10^e > INT32\_MAX  | Exceeds target integer limits    |
| Round-trip failure  | `0.333...` with e=1, f=0  | `decode(encode(v)) != v`         |

Exception values at positions in the vector are replaced with a placeholder
(the encoded integer of the first non-exception value, or 0 if all values
are exceptions) before FOR encoding. This keeps the FOR range tight.

##### Frame of Reference and Bit-Packing

After decimal encoding and exception substitution:

```
+---------------------------------------------------------------------+
|  Encoded:   [ 123,  456,  789,   12 ]                               |
|                                                                     |
|  min_val = 12  (stored as frame_of_reference)                       |
|                                                                     |
|  Deltas:    [ 111,  444,  777,    0 ]   <-- all non-negative        |
+---------------------------------------------------------------------+
```

| Step                   | Formula                               | Example                     |
|------------------------|---------------------------------------|-----------------------------|
| 1. Find min            | min\_val = min(encoded\[\])           | 12                          |
| 2. Compute deltas      | delta\[i\] = encoded\[i\] - min\_val | \[111, 444, 777, 0\]       |
| 3. Calculate bit width | bit\_width = ceil(log2(max\_delta+1)) | ceil(log2(778)) = 10       |
| 4. Pack values         | Each value uses bit\_width bits       | 4 * 10 = 40 bits = 5 bytes |

Special case: If all values are identical, bit\_width = 0 and no packed data is stored.

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
    |     encoded[i] = delta[i] + frame_of_reference           |
    +----------------------------------------------------------+
                              |
                              v
    +----------------------------------------------------------+
    |  3. DECIMAL DECODING                                     |
    |     value[i] = encoded[i] * 10^factor * 10^(-exponent)   |
    +----------------------------------------------------------+
                              |
                              v
    +----------------------------------------------------------+
    |  4. PATCH EXCEPTIONS                                     |
    |     value[pos[j]] = exception_values[j]                  |
    +----------------------------------------------------------+
                              |
                              v
                  Output: Original float/double array
```

For each vector:

1. Read AlpInfo and ForInfo from the vector header.
2. Unpack `bit_width`-bit integers from PackedValues.
3. Add `frame_of_reference` to each unpacked integer.
4. Decode: multiply each integer by `10^factor` then by `10^(-exponent)`.
5. Patch exceptions: for each (position, value) in the exception arrays,
   overwrite the decoded output at that position with the stored value.

#### Example 1: Simple Decimal Values

**Input:** `float values[4] = { 1.23, 4.56, 7.89, 0.12 }`

**Step 1: Find Best Exponent/Factor**

Testing (exponent=2, factor=0) means multiply by 10^2 = 100:

| Value | value * 100 | Rounded | Verify: rounded * 1.0 * 0.01 | Match? |
|-------|-------------|---------|-------------------------------|--------|
| 1.23  | 123.0       | 123     | 1.23                          | Yes    |
| 4.56  | 456.0       | 456     | 4.56                          | Yes    |
| 7.89  | 789.0       | 789     | 7.89                          | Yes    |
| 0.12  | 12.0        | 12      | 0.12                          | Yes    |

All values round-trip correctly -- no exceptions.

**Step 2: Frame of Reference**

| Encoded | min = 12 | Delta (encoded - min) |
|---------|----------|-----------------------|
| 123     | -        | 111                   |
| 456     | -        | 444                   |
| 789     | -        | 777                   |
| 12      | -        | 0                     |

**Step 3: Bit Packing**

max\_delta = 777, bit\_width = ceil(log2(778)) = 10 bits,
packed\_size = ceil(4 * 10 / 8) = 5 bytes

**Serialized Vector:**

| Section             | Content                                | Size     |
|---------------------|----------------------------------------|----------|
| AlpInfo             | e=2, f=0, num\_exceptions=0            | 4 bytes  |
| ForInfo             | frame\_of\_reference=12, bit\_width=10 | 5 bytes  |
| PackedValues        | \[111, 444, 777, 0\] at 10 bits each  | 5 bytes  |
| ExceptionPositions  | (none)                                 | 0 bytes  |
| ExceptionValues     | (none)                                 | 0 bytes  |
| **Total**           |                                        | **14 bytes** |

Compared to PLAIN encoding (4 * 4 = 16 bytes). With 1024 values, the 9-byte
vector header becomes negligible and compression ratios of 2-8x are typical.

#### Example 2: Values with Exceptions

**Input:** `float values[4] = { 1.5, NaN, 2.5, 0.333... }`

**Step 1: Decimal Encoding with (e=1, f=0)**

Multiply by 10^1 = 10:

| Index | Value    | value * 10 | Rounded | Verify         | Exception? |
|-------|----------|------------|---------|----------------|------------|
| 0     | 1.5      | 15.0       | 15      | 1.5 = 1.5      | No         |
| 1     | NaN      | -          | -       | -              | Yes (NaN)  |
| 2     | 2.5      | 25.0       | 25      | 2.5 = 2.5      | No         |
| 3     | 0.333... | 3.333...   | 3       | 0.3 != 0.333...| Yes (round-trip) |

**Step 2: Handle Exceptions**

Exception positions: \[1, 3\]
Exception values: \[NaN, 0.333...\]
Placeholder: 15 (first non-exception encoded value)
Encoded with placeholders: \[15, 15, 25, 15\]

**Step 3: Frame of Reference**

| Encoded          | min = 15 | Delta |
|------------------|----------|-------|
| 15               | -        | 0     |
| 15 (placeholder) | -        | 0     |
| 25               | -        | 10    |
| 15 (placeholder) | -        | 0     |

**Step 4: Bit Packing**

max\_delta = 10, bit\_width = ceil(log2(11)) = 4 bits,
packed\_size = ceil(4 * 4 / 8) = 2 bytes

**Serialized Vector:**

| Section             | Content                                | Size     |
|---------------------|----------------------------------------|----------|
| AlpInfo             | e=1, f=0, num\_exceptions=2            | 4 bytes  |
| ForInfo             | frame\_of\_reference=15, bit\_width=4  | 5 bytes  |
| PackedValues        | \[0, 0, 10, 0\] at 4 bits each        | 2 bytes  |
| ExceptionPositions  | \[1, 3\]                               | 4 bytes  |
| ExceptionValues     | \[NaN, 0.333...\]                      | 8 bytes  |
| **Total**           |                                        | **23 bytes** |

#### Example 3: Monetary Data (1024 values)

1024 price values ranging from $0.01 to $999.99 (e.g., product prices).

Optimal encoding: (exponent=2, factor=0)

| Metric        | Value       | Calculation                          |
|---------------|-------------|--------------------------------------|
| Exponent      | 2           | Multiply by 100 for 2 decimal places |
| Factor        | 0           | No additional scaling needed         |
| Encoded range | 1 to 99,999 | $0.01 -> 1, $999.99 -> 99999         |
| FOR min       | 1           | Assuming $0.01 is present            |
| Delta range   | 0 to 99,998 | After FOR subtraction                |
| Bit width     | 17          | ceil(log2(99999)) = 17 bits          |
| Packed size   | 2,176 bytes | ceil(1024 * 17 / 8)                  |

**Size Comparison:**

| Encoding      | Size         | Ratio               |
|---------------|--------------|----------------------|
| PLAIN (float) | 4,096 bytes  | 1.0x                 |
| ALP           | ~2,185 bytes | 0.53x (47% smaller)  |

#### Characteristics

| Property       | Description                                                                            |
|----------------|----------------------------------------------------------------------------------------|
| Lossless       | All original floating-point values are perfectly recoverable, including NaN, Inf, -0.0 |
| Adaptive       | Exponent/factor selection adapts per vector based on data characteristics               |
| Vectorized     | Fixed-size vectors enable SIMD-optimized bit packing/unpacking                         |
| Exception-safe | Values that don't fit decimal model are stored separately                              |

**Best use cases:**

* Monetary/financial data (prices, transactions)
* Sensor readings with fixed precision
* Scientific measurements with limited decimal places
* GPS coordinates and geographic data
* Normalized scores and percentages

**Worst case scenarios:**

* Random floating-point values (high exception rate)
* High-precision scientific data (many decimal places)
* Data with many special values (NaN, Inf)
* Very small datasets (header overhead dominates)

**Comparison with other encodings:**

| Encoding            | Type Support | Compression | Best For            |
|---------------------|--------------|-------------|---------------------|
| PLAIN               | All          | None        | General purpose     |
| BYTE\_STREAM\_SPLIT | Float/Double | Moderate    | Random floats       |
| ALP                 | Float/Double | High        | Decimal-like floats |
| DELTA\_BINARY\_PACKED | Int32/Int64 | High       | Sequential integers |

Unlike [Byte Stream Split](#BYTE_STREAM_SPLIT), ALP does not require a subsequent
compression step to achieve size reduction -- the bit-packing directly reduces the
encoded size. However, ALP and Byte Stream Split can be complementary: ALP
exploits decimal structure while Byte Stream Split exploits byte-level correlation.

#### Size Calculations

##### Vector Size Formula

```
vector_bytes = vector_header_size                  // FLOAT: 9, DOUBLE: 13
             + ceil(num_elements * bit_width / 8)  // packed values
             + num_exceptions * 2                  // exception positions (uint16)
             + num_exceptions * sizeof(T)          // exception values (4 or 8)
```

##### Page Size Formula

```
page_bytes = 7                                   // page header
           + num_vectors * 4                     // offset array
           + sum(vector_bytes for each vector)   // all vectors
```

#### Constants Reference

| Constant          | Value   | Description                             |
|-------------------|---------|-----------------------------------------|
| Vector size       | 1024    | Default elements per compressed vector  |
| Max combinations  | 5       | Max (e,f) pairs in preset               |
| Samples per vector| 256     | Values sampled per vector               |
| Sample vectors    | 8       | Vectors sampled per row group           |
| FLOAT max exponent| 10      | 10^10 ~ 10 billion                      |
| DOUBLE max exponent| 18     | 10^18 ~ 1 quintillion                   |
