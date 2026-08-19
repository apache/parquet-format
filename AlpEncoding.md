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

ALP (Adaptive Lossless floating-Point) Encoding
====

This file contains the detailed specification of the
[ALP encoding](Encodings.md#ALP) (`ALP = 10`).

## Overview

For each data page, ALP encoding consists of a header followed by an offset array
and one or more encoded vectors (batches of values). Each vector contains up to
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

The compression pipeline below describes *one* way to produce a conforming
vector. It is informative, not normative: an encoder may use any strategy as long
as it emits the byte layout defined in [Page Layout](#page-layout). Only that
byte layout and the [Decoding](#decoding) procedure are normative.

```
                    Input: float/double array
                              |
                              v
    +----------------------------------------------------------+
    |  1. CHOOSE PARAMETERS                                    |
    |     Select (exponent, factor) pair for this array        |
    +----------------------------------------------------------+
                              |
                              v
    +----------------------------------------------------------+
    |  2. DECIMAL ENCODING                                     |
    |     encoded[i] = fast_round(value[i] * 10^e * 10^(-f))  |
    |     Detect exceptions where decode(encode(v)) != v       |
    +----------------------------------------------------------+
                              |
                              v
    +----------------------------------------------------------+
    |  3. FRAME OF REFERENCE (FOR)                             |
    |     min_val = min(encoded[:])                            |
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

The `fast_round` used in step 2 is one recommended rounding technique, described in
[Fast Rounding](#fast-rounding) below; it is informative, not normative.

## Page Layout

### Header (7 bytes)

All multi-byte values are stored in little-endian order.

```
 Byte:         0                1              2         3    4    5    6
       +----------------+---------------+--------------+----+----+----+----+
       | compression    | integer       | log_vector   |     num_elements  |
       | _mode          | _encoding     | _size        |     (int32 LE)    |
       +----------------+---------------+--------------+----+----+----+----+
```

| Offset | Field | Size | Type | Description |
|--------|-------|------|------|-------------|
| 0 | compression_mode | 1 byte | uint8 | Compression mode (0 = ALP). Reserved for future variants (e.g., ALP-RD). |
| 1 | integer_encoding | 1 byte | uint8 | Integer encoding (must be 0 = FOR + bit-packing) |
| 2 | log_vector_size | 1 byte | uint8 | log2(vector\_size). Must be in the inclusive range \[3, 15\]. Recommended default: 10 (vector size 1024) |
| 3 | num_elements | 4 bytes | int32 | Total number of non-null floating-point values in the page |

The number of vectors is `ceil(num_elements / vector_size)`. The last vector may
contain fewer than `vector_size` elements.

**Note:** The number of elements per vector is NOT stored in the header — it is
derived: `vector_size` for all vectors except the last, which may be smaller.

### Offset Array

Immediately following the header is an array of `num_vectors` little-endian uint32
values. Each offset gives the byte position of the corresponding vector's data,
measured from the start of the offset array itself.

The first offset always equals `num_vectors * 4` (pointing just past the offset array).
Each subsequent offset equals the previous offset plus the stored size of the
previous vector. No padding is inserted between vectors.

Offsets are relative to the start of the offset array. A vector's absolute byte
position is `alp_data_start + 7 + offset`, where `alp_data_start` is the first
byte of the ALP header within the *decoded* page data — that is, after the page
has been decompressed and after any repetition/definition levels — and `7` is the
size of the ALP header. (When the page is uncompressed and carries no repetition
or definition levels, `alp_data_start` coincides with the first byte after the
page's Thrift header.)

### Vector Format

Each vector is self-describing and contains the encoding parameters, FOR metadata,
bit-packed encoded values, and exception data. The layout described here applies
when `compression_mode` = 0 (ALP) and `integer_encoding` = 0 (FOR + bit-packing);
future modes may define different vector contents and need not include `AlpInfo`
or `ForInfo`.

```
<----------- Vector Header -----------><----------------------- Data Section ----------------------->
+-------------------+-----------------+-------------------+---------------------+-------------------+
|      AlpInfo      |     ForInfo     |   PackedValues    | ExceptionPositions  | ExceptionValues   |
|     (4 bytes)     | (5B or 9B)      |    (variable)     |     (variable)      |    (variable)     |
+-------------------+-----------------+-------------------+---------------------+-------------------+
```

The first two components (`AlpInfo` and `ForInfo`) form the *vector header*; the
remaining three (`PackedValues`, `ExceptionPositions`, `ExceptionValues`) form the
*data section*.

Vector header sizes:
| Type   | AlpInfo | ForInfo | Total Header |
|--------|---------|---------|--------------|
| FLOAT  | 4 bytes | 5 bytes | 9 bytes      |
| DOUBLE | 4 bytes | 9 bytes | 13 bytes     |

Data section sizes:
| Section             | Size Formula                | Description                  |
|---------------------|-----------------------------|------------------------------|
| PackedValues        | ceil(num\_elements\_in\_vector * bit\_width / 8) | Bit-packed delta values      |
| ExceptionPositions  | num\_exceptions * 2 bytes   | uint16 indices of exceptions |
| ExceptionValues     | num\_exceptions * sizeof(encoded type) (float=4 and double=8) | Original values, stored as their exact IEEE-754 bits (NaN not canonicalized) |

Here `bit_width` and `num_exceptions` are read from the vector header (`ForInfo`
and `AlpInfo` respectively), described below.

#### AlpInfo (4 bytes, both types)

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

#### ForInfo for FLOAT (5 bytes)

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

#### ForInfo for DOUBLE (9 bytes)

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

#### PackedValues

The FOR-encoded deltas, bit-packed into `ceil(num_elements_in_vector * bit_width / 8)` bytes.
Values are bit-packed using the same LSB-first packing order as the
[RLE/Bit-Packing Hybrid](Encodings.md#RLE) encoding. When the total number of packed bits is
not a multiple of 8, the final byte is padded with zero bits in its most
significant positions.

Each delta is `encoded[i] - frame_of_reference`, computed in unsigned (wrapping)
arithmetic and stored as an unsigned integer. Computing it as unsigned avoids
signed-integer overflow when the vector's range (`max - min`) exceeds the signed
maximum of the encoded type, and it means no sign extension is applied when
unpacking. Because `frame_of_reference` is the minimum encoded integer in the
vector, every delta is non-negative.

If `bit_width` is 0, no bytes are stored (all deltas are zero, meaning all encoded
integers are equal to `frame_of_reference`).

#### ExceptionPositions

An array of `num_exceptions` little-endian uint16 values, each giving
the 0-based index within the vector of an exception value.

#### ExceptionValues

An array of `num_exceptions` values in the original floating-point type
(4 bytes little-endian IEEE 754 for FLOAT, 8 bytes for DOUBLE), stored in
the same order as the corresponding positions. Each value is stored as its exact
IEEE 754 bit pattern; implementations MUST NOT canonicalize NaN or otherwise alter
the bits, so that decoding reproduces the original value bit-for-bit.

## Encoding

### Encoding Formula

```
+-------------------------------------------------------------------+
|                                                                   |
|   encoded = fast_round( value  *  10^e  *  10^(-f) )             |
|                                                                   |
|   decoded = encoded  *  10^f  *  10^(-e)                          |
|                                                                   |
+-------------------------------------------------------------------+
```

The formula uses two separate multiplications (not a single multiplication by
`10^(e-f)`, and not division). This is a requirement of the **decode** path, which
is normative: to reconstruct a value every reader MUST compute
`decoded = encoded * 10^f * 10^(-e)` using the same two-step multiplication and the
same power-of-10 constants, so that all implementations reproduce the stored value
bit-for-bit. The power-of-10 constants MUST be the correctly-rounded IEEE 754
values of the decimal literals `1e0`, `1e1`, ..., `1e18` and `1e-1`, `1e-2`, ...,
`1e-18` as defined by the decimal-to-binary conversion in IEEE 754-2008 §5.12.2.
Implementations MUST NOT compute these constants at runtime via `pow()` or
equivalent functions, which are not guaranteed to be correctly rounded.

The **encode** direction — mapping each value to the integer it will be stored as,
via `fast_round(value * 10^e * 10^(-f))` — is informative, not normative. An
encoder MAY choose that integer by any means, because every value is checked
against the normative decode above and any value that does not round-trip exactly
is stored as an exception. The rounding method therefore affects only compression
ratio and exception count, never correctness or what a reader decodes. The
`fast_round` technique below is one recommended implementation.

### Fast Rounding (informative)

`fast_round` recovers the integer intended by `value * 10^e * 10^(-f)` — which
carries floating-point rounding noise — by rounding it to the nearest integer
(ties to even), without a division or a call to a library rounding function. It is
**not** normative: an encoder MAY use any rounding method, since values that do not
round-trip under the normative decode are stored as exceptions.

The technique adds then subtracts a "magic number" (a power of two large enough to
discard the fractional bits), leaving the nearest integer. Implementations vary:
some apply it in a single branch-free form, others add a sign test.

| Type   | Magic Number                      | Formula (value &ge; 0)           | Formula (value &lt; 0)           |
|--------|-----------------------------------|----------------------------------|----------------------------------|
| FLOAT  | 2^23 = 8,388,608                 | `(int32_t)((value + magic) - magic)` | `(int32_t)((value - magic) + magic)` |
| DOUBLE | 2^52 = 4,503,599,627,370,496     | `(int64_t)((value + magic) - magic)` | `(int64_t)((value - magic) + magic)` |

The `value ± magic` operations must be evaluated in the value's own precision
(FLOAT in binary32, DOUBLE in binary64); only the final cast converts to an integer.
The two forms round some large-magnitude inputs differently, but since any value
that fails to round-trip is stored as an exception, the choice affects only
compression ratio, never correctness.

### Parameter Selection

Any valid (exponent, factor) pair produces a correct encoding — the decoder is
agnostic to the selection strategy, and the exception mechanism guarantees
round-trip fidelity regardless of which pair is chosen. The choice only affects
compression ratio.

The encoder SHOULD select the (exponent, factor) pair that produces the smallest
encoded output. A simple heuristic is to minimize exception count; a more precise
approach accounts for both bit-width and exception overhead.

Valid combinations satisfy 0 &le; factor &le; exponent:

| Type   | Max Exponent | Total Combinations |
|--------|--------------|--------------------|
| FLOAT  | 10           | 66                 |
| DOUBLE | 18           | 190                |

To avoid the cost of exhaustive search on every vector, implementations
can use a sampling approach. One such approach, described in the paper, is to
select up to 5 candidate (exponent, factor) combinations (the "encoding preset")
at the start of each column chunk, and when encoding each vector,
evaluate each candidate for the best compression.

Suggested sampling parameters (from the paper):

| Parameter            | Value | Description                         |
|----------------------|-------|-------------------------------------|
| Sample Size          | 256   | Values sampled per vector           |
| Max Combinations     | 5     | Best (e,f) pairs kept in preset     |
| Sample Vectors       | 8     | Vectors sampled per row group       |

### Exception Detection

A value becomes an exception if any of the following is true:

| Condition          | Example                    | Reason                           |
|--------------------|----------------------------|----------------------------------|
| NaN                | `NaN`                      | Cannot convert to integer        |
| Infinity           | `+Inf`, `-Inf`             | Cannot convert to integer        |
| Negative zero      | `-0.0`                     | Would become `+0.0` after encoding |
| Out of range       | scaled value outside int32 (FLOAT) or int64 (DOUBLE) | Exceeds target integer type range |
| Round-trip failure  | `0.333...` with e=1, f=0  | `decode(encode(v)) != v`         |

Exception values at positions in the vector are replaced with a placeholder
(the encoded integer of the first non-exception value, or 0 if all values
are exceptions) before FOR encoding. This keeps the FOR range tight.

### Example: Frame of Reference and Bit-Packing

Given the following data after decimal encoding and exception substitution:

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
| 1. Find min            | min\_val = min(encoded\[:\])          | 12                          |
| 2. Compute deltas      | delta\[i\] = encoded\[i\] - min\_val | \[111, 444, 777, 0\]       |
| 3. Calculate bit width | bit\_width = ceil(log2(max\_delta+1)) | ceil(log2(778)) = 10       |
| 4. Pack values         | Each value uses bit\_width bits       | 4 * 10 = 40 bits = 5 bytes |

Special case: If all values are identical, bit\_width = 0 and no packed data is stored.

## Decoding

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

## Worked Example: Exceptions and Non-Zero Factor

**Input:** `double values[4] = { 1500.0, NaN, 2500.0, 333.5 }`

Best encoding found: (exponent=4, factor=3). This means:
`encoded = fast_round(value * 10^4 * 10^(-3)) = fast_round(value * 10)`

**Step 1: Decimal Encoding**

| Index | Value   | value * 10^4 * 10^(-3) | Rounded | Decoded: rounded * 10^3 * 10^(-4) | Exception? |
|-------|---------|------------------------|---------|------------------------------------|------------|
| 0     | 1500.0  | 15000.0                | 15000   | 1500.0                             | No         |
| 1     | NaN     | -                      | -       | -                                  | Yes (NaN)  |
| 2     | 2500.0  | 25000.0                | 25000   | 2500.0                             | No         |
| 3     | 333.5   | 3335.0                 | 3335    | 333.5                              | No         |

**Step 2: Handle Exceptions**

Exception positions: \[1\]
Exception values: \[NaN\]
Placeholder: 15000 (first non-exception encoded value)
Encoded with placeholders: \[15000, 15000, 25000, 3335\]

**Step 3: Frame of Reference**

| Encoded            | min = 3335 | Delta |
|--------------------|------------|-------|
| 15000              | -          | 11665 |
| 15000 (placeholder)| -          | 11665 |
| 25000              | -          | 21665 |
| 3335               | -          | 0     |

**Step 4: Bit Packing**

max\_delta = 21665, bit\_width = ceil(log2(21666)) = 15 bits,
packed\_size = ceil(4 * 15 / 8) = 8 bytes

**Serialized Vector:**

| Section             | Content                                          | Size     |
|---------------------|--------------------------------------------------|----------|
| AlpInfo             | e=4, f=3, num\_exceptions=1                      | 4 bytes  |
| ForInfo             | frame\_of\_reference=3335, bit\_width=15          | 9 bytes  |
| PackedValues        | \[11665, 11665, 21665, 0\] at 15 bits each       | 8 bytes  |
| ExceptionPositions  | \[1\]                                             | 2 bytes  |
| ExceptionValues     | \[NaN\]                                           | 8 bytes  |
| **Total**           |                                                   | **31 bytes** |

Compared to PLAIN encoding (4 * 8 = 32 bytes). With 1024 values, the 13-byte
vector header becomes negligible and compression ratios of 2-8x are typical.
