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

PFOR (Patched Frame of Reference) Encoding
====

This file contains the detailed specification of the
[PFOR encoding](Encodings.md#PFOR) (`PFOR = 11`).

The values that reach the packed stream are called *residuals* throughout this
file, in both modes: a residual is what remains after the frame of reference
is subtracted, whether the frame was subtracted from a value or from a
difference.

## Overview

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
    |  0. DELTA MODE (optional, writer's choice)               |
    |     start_value = values[0]                              |
    |     d[0] = 0                                             |
    |     d[i] = (unsigned)(values[i] - values[i-1])           |
    |     Steps 1..4 then run on d[] instead of values[]       |
    +----------------------------------------------------------+
                              |
                              v
    +----------------------------------------------------------+
    |  1. FRAME OF REFERENCE (FOR)                             |
    |     min_val = min(values[])                              |
    |     residual[i] = (unsigned)(values[i] - min_val)        |
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
    |     Replace with 0 placeholder in residual array         |
    +----------------------------------------------------------+
                              |
                              v
    +----------------------------------------------------------+
    |  4. BIT PACKING                                          |
    |     Pack each residual into bit_width bits               |
    +----------------------------------------------------------+
                              |
                              v
                   Output: Serialized vector bytes
```

## Page Layout

### Header (7 bytes)

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

### Offset Array

Immediately following the header is an array of `num_vectors` little-endian uint32
values. Each offset gives the byte position of the corresponding vector's data,
measured from the start of the offset array itself.

The first offset equals `num_vectors * 4` (pointing just past the offset array).
Each subsequent offset equals the previous offset plus the stored size of the
previous vector.

### Vector Format

Each vector is self-describing and contains the FOR metadata, bit-packed residual
values, and exception data. A vector in the delta mode carries one more field, its
start value, between the metadata and the packed residuals.

```
+------------------+---------------+----------------+--------------------+-----------------+
|  PforVectorInfo  |  StartValue   |  PackedValues  | ExceptionPositions | ExceptionValues |
|  (7B or 11B)     | (0B, 4B, 8B)  |   (variable)   |     (variable)     |   (variable)    |
+------------------+---------------+----------------+--------------------+-----------------+
```

Vector header sizes:
| Type   | PforVectorInfo | Total Header, plain | Total Header, delta mode |
|--------|----------------|---------------------|--------------------------|
| INT32  | 7 bytes        | 7 bytes             | 11 bytes                 |
| INT64  | 11 bytes       | 11 bytes            | 19 bytes                 |

Data section sizes:
| Section             | Size Formula                              | Description                  |
|---------------------|-------------------------------------------|------------------------------|
| StartValue          | value\_byte\_width bytes, or 0            | Present only in the delta mode |
| PackedValues        | ceil(N * bit\_width / 8)                  | Bit-packed residual values   |
| ExceptionPositions  | num\_exceptions * 2 bytes                 | uint16 indices of exceptions |
| ExceptionValues     | num\_exceptions * value\_byte\_width bytes | Unpatched values, or differences in the delta mode |

#### PforVectorInfo for INT32 (7 bytes)

```
 Byte:    0    1    2    3       4          5       6
       +----+----+----+----+-----------+---------+---------+
       | frame_of_reference | bit_width |  num_exceptions   |
       |    (int32 LE)      |  (uint8)  |   (uint16 LE)     |
       +----+----+----+----+-----------+---------+---------+
```

| Offset | Field | Size | Type | Description |
|--------|-------|------|------|-------------|
| 0 | frame_of_reference | 4 bytes | int32 | Minimum value in the vector, or the minimum difference in the delta mode |
| 4 | bit_width | 1 byte | uint8 | Bits per packed residual value in bits 0..6; bit 7 is the delta flag. Range: \[0, 32\]. |
| 5 | num_exceptions | 2 bytes | uint16 | Number of exception values in this vector. |

#### PforVectorInfo for INT64 (11 bytes)

```
 Byte:    0    1    2    3    4    5    6    7       8          9      10
       +----+----+----+----+----+----+----+----+-----------+---------+---------+
       |          frame_of_reference           | bit_width |  num_exceptions   |
       |              (int64 LE)               |  (uint8)  |   (uint16 LE)     |
       +----+----+----+----+----+----+----+----+-----------+---------+---------+
```

| Offset | Field | Size | Type | Description |
|--------|-------|------|------|-------------|
| 0 | frame_of_reference | 8 bytes | int64 | Minimum value in the vector, or the minimum difference in the delta mode |
| 8 | bit_width | 1 byte | uint8 | Bits per packed residual value in bits 0..6; bit 7 is the delta flag. Range: \[0, 64\]. |
| 9 | num_exceptions | 2 bytes | uint16 | Number of exception values in this vector. |

**The bit_width byte.** Bits 0..6 hold the width; bit 7 is the delta flag. A
reader MUST mask off bit 7 before comparing the width against the type's maximum,
and MUST read the flag rather than ignore it: the flag decides whether a
StartValue field is present, so a reader that skips it reads the packed residuals
from the wrong offset.

The width takes seven bits rather than six because its range is 0..64 inclusive,
and 64 does not fit in six. Masking with six bits reads an INT64 vector whose
residuals need the full 64 bits as width 0. Such a vector also has no exceptions,
so the mis-read looks like a constant vector: the reader fills the output with the
frame of reference, and neither a size mismatch nor an error reveals the
corruption.

The flag is a bit of its own rather than another code in a mode field because
differencing is orthogonal to everything else the header carries: a delta vector
still has a frame of reference, a width and exceptions, and each of those is
chosen over the differences exactly as it would be over the values.

#### StartValue

Present only when the delta flag is set, in which case it is one value in the
column's integer type (4 bytes little-endian for INT32, 8 for INT64), holding the
vector's first value. It sits between PforVectorInfo and PackedValues.

Carrying it per vector is what keeps a delta vector independently decodable. The
alternative -- carrying the running total across vectors -- would make every
vector in a page depend on its predecessors, and a reader could no longer start at
an arbitrary vector.

The field is absent on a plain vector rather than written as zero. At the default
vector size of 1024 the difference is negligible, but the format allows vectors as
short as 8 elements, where 8 unused bytes across 8 values would be a byte per
value.

#### PackedValues

The FOR-encoded residuals, bit-packed into `ceil(num_elements_in_vector * bit_width / 8)` bytes.
In the delta mode these are the residuals of the differences between successive
values, not of the values.
Values are packed from the least significant bit of each byte to the most significant bit,
in groups of 8 values, using the same bit-packing order as the
[RLE/Bit-Packing Hybrid](Encodings.md#RLE) encoding.

Exception positions contain 0 as a placeholder in the packed data. The actual
exception values are stored separately and patched during decoding.

If `bit_width` is 0, no bytes are stored: every residual is zero. In a plain vector
that means every value equals `frame_of_reference`. In a delta vector it means every
difference equals `frame_of_reference`, and because `d[0]` is 0 and the frame is the
minimum of the differences, the frame of such a vector is 0 -- so the values are all
equal to `start_value`.

#### ExceptionPositions

An array of `num_exceptions` little-endian uint16 values, each giving
the 0-based index within the vector of an exception value.

#### ExceptionValues

An array of `num_exceptions` values in the column's integer type (4 bytes
little-endian for INT32, 8 bytes for INT64), stored in the same order as the
corresponding positions. These are never residuals: each is the value the packed
stream would have carried had it fitted. In a plain vector that is the original
integer value; in a delta vector it is the difference, which the reader patches in
**before** the prefix sum so that a patched difference is summed like any other.

## Encoding

A writer makes two choices per vector -- whether to difference, and what width to
pack at -- and the sections below take them in the order the encoded bytes depend
on them. Only the width is forced: given the first choice, the cost model
determines it. A writer that always declines to difference produces valid pages.

### Delta Mode

A writer MAY replace the vector's values with the differences between successive
values before doing anything else:

```
start_value = values[0]
d[0]        = 0
d[i]        = (unsigned)(values[i] - values[i-1])      for i > 0
```

Everything after this point -- the frame, the width, the exceptions, the packing --
then operates on `d[]` in place of `values[]`. The writer sets bit 7 of `bit_width`
and writes `start_value` in the StartValue field.

The subtraction is modular, but what it produces is an ordinary signed value in the
column's type, and it is **not** zigzag-encoded. A vector with negative differences
is handled by the frame instead: the frame is the minimum of `d[]`, so subtracting
it makes every residual non-negative, which is the same mechanism a plain vector
uses for negative values. `d[0]` is defined as 0 rather than as `values[0]` so that
the first element does not force a wide frame or an exception of its own; the reader
adds `start_value` to it.

Both the differencing and the prefix sum that reverses it MUST be computed on the
unsigned bit patterns. Signed overflow is undefined behaviour in some languages, and
a column spanning the type's range will overflow -- computing both directions
modularly is what makes the bits round-trip exactly.

Deciding whether to difference is entirely the writer's business. Differencing pays
on data whose successive values are close -- sorted keys, timestamps, counters --
and costs bits on data where they are not, plus one full-width start value per
vector either way. One way to decide is to run the cost model of the next section
twice, once on the values and once on the differences, and keep the cheaper; a
writer that does not want to spend that search may leave the mode off for a column
and still produce pages every reader accepts.

### Frame of Reference

The frame of reference is the minimum value in the vector, or the minimum of the
differences when the delta mode is in use:

```
frame_of_reference = min(values[])
residual[i] = (unsigned)(values[i] - frame_of_reference)
```

All residuals are non-negative. The unsigned cast prevents signed overflow when
values span a large range (e.g., INT32\_MIN to INT32\_MAX).

### Cost-Model Bit Width Selection

The cost model evaluates every candidate bit width and selects the one that
minimizes total encoded size. It runs on the residuals as given, so it assumes the
delta decision is already made. This is the key difference from plain FOR encoding,
which always uses the bit width of the maximum residual.

**Algorithm:**

1. Build a histogram `H[b]` where `H[b]` = number of residuals requiring exactly
   `b` bits (using `bits_required(residual) = ceil(log2(residual + 1))`, with
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

### Exception Extraction

After selecting the optimal bit width:

1. Compute `mask = (1 << bit_width) - 1` (for bit\_width < max\_bits; if
   bit\_width equals max\_bits, there are no exceptions).
2. For each residual where `residual[i] > mask`:
   * Record the position `i` in the exception positions array.
   * Record the **unreduced value** in the exception values array: `values[i]` in a
     plain vector, `d[i]` in a delta vector.
   * Replace `residual[i]` with 0 in the residual array (placeholder for bit-packing).

### Bit-Packing

Pack the residuals (with exception placeholders set to 0) using `bit_width` bits
per value. The packing order is LSB-first in groups of 8, matching the
[RLE/Bit-Packing Hybrid](Encodings.md#RLE) encoding.

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
    |     values[i] = residual[i] + frame_of_reference         |
    +----------------------------------------------------------+
                              |
                              v
    +----------------------------------------------------------+
    |  3. PATCH EXCEPTIONS                                     |
    |     values[pos[j]] = exception_values[j]                 |
    +----------------------------------------------------------+
                              |
                              v
    +----------------------------------------------------------+
    |  4. PREFIX SUM (delta mode only)                         |
    |     acc = start_value                                    |
    |     for i: acc += values[i]; values[i] = acc             |
    +----------------------------------------------------------+
                              |
                              v
                  Output: Original integer array
```

For each vector:

1. Read PforVectorInfo from the vector header. Mask bit 7 off `bit_width` to get
   the width, and keep it as the delta flag.
2. If the delta flag is set, read StartValue from the `value_byte_width` bytes that
   follow the header. The packed residuals begin after it. A reader MUST check that
   those bytes are within the page before reading them: the header bound was
   satisfied before the flag was known, so a reader that validates only the header
   and then the residual section reads StartValue from outside the page and checks
   the residual bound from an offset that has already moved past the end.
3. Unpack `bit_width`-bit unsigned integers from PackedValues.
4. Add `frame_of_reference` to each unpacked integer, in the unsigned type.
5. Patch exceptions: for each (position, value) in the exception arrays,
   overwrite the decoded output at that position with the stored value.
6. If the delta flag is set, replace the output with its running sum, starting from
   `start_value`:

   ```
   acc = (unsigned)start_value
   for i in 0 .. num_elements-1:
     acc += (unsigned)output[i]
     output[i] = (signed)acc
   ```

The sum MUST come after the patch, not before. An exception in a delta vector is a
difference like any other, and summing first would carry its zero placeholder into
every value that follows it. The sum MUST also run on the unsigned bit patterns,
matching how the writer took the differences.

**Special case:** If `bit_width == 0` and `num_exceptions == 0`, every residual is
zero, so a reader can fill the output instead of unpacking: in a plain vector with
`frame_of_reference`, in a delta vector with `start_value`, because a delta vector
whose residuals are all zero has a frame of 0. A reader MAY instead run the general
path -- add the frame to an all-zero array, then prefix-sum in the delta mode -- and
get the same answer for any frame; the fill is an optimization, not a separate rule.

## Example 1: Integer Keys with an Outlier

**Input:** `int32 values[8] = { 100, 102, 101, 103, 100, 99, 50000, 104 }`

**Step 1: Frame of Reference**

min\_val = 99, residuals = \[1, 3, 2, 4, 1, 0, 49901, 5\]

**Step 2: Cost Model**

| Bit Width | Packing Cost | Exceptions | Exception Cost | Total Cost |
|-----------|-------------|------------|----------------|------------|
| 3         | 24 bits     | 1          | 48 bits        | 72 bits    |
| 16        | 128 bits    | 0          | 0 bits         | 128 bits   |

The cost model selects bit\_width = 3 (72 bits < 128 bits).

**Step 3: Exception Extraction**

mask = 7 (for bit\_width = 3). Value 50000 at index 6 has residual 49901 > 7.
* Exception position: \[6\]
* Exception value: \[50000\] (original value)
* Residual array with placeholder: \[1, 3, 2, 4, 1, 0, **0**, 5\]

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

## Example 2: Uniform Data (No Exceptions)

**Input:** `int32 values[1024]` where all values are between 1000 and 1255.

min\_val = 1000, max\_residual = 255, bit\_width = 8 (same as plain FOR).
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

## Example 3: Date Key Column (TPC-DS pattern)

1024 date key values (INT32) ranging from 2,450,815 to 2,453,005 with a few
outlier keys at 2,415,022 (null sentinel) interspersed.

| Metric        | Value       | Calculation                                 |
|---------------|-------------|---------------------------------------------|
| FOR min       | 2,415,022   | The null sentinel is the minimum             |
| Max residual  | 37,983      | 2,453,005 - 2,415,022                       |
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

## Example 4: Delta Mode

**Input:** `int64 values[1024]` where `values[i] = 1'700'000'000'000 + i * 7` -- a
timestamp column sampled at a fixed interval.

Undifferenced, the frame is 1,700,000,000,000 and the residuals run to
1023 * 7 = 7,161, so bits\_required(7,161) = 13 and there are no exceptions:
`11 + ceil(1024 * 13 / 8)` = 1,675 bytes.

Differenced, `start_value` = 1,700,000,000,000 and `d` = \[0, 7, 7, ..., 7\]. The
frame is min(`d`) = 0, leaving residuals of 0 and 7, so bit\_width = 3 with no
exceptions:

| Section             | Content                                                | Size     |
|---------------------|--------------------------------------------------------|----------|
| PforVectorInfo      | for=0, bit\_width=3 with bit 7 set, num\_exceptions=0  | 11 bytes |
| StartValue          | 1,700,000,000,000                                      | 8 bytes  |
| PackedValues        | \[0, 7, 7, ..., 7\] at 3 bits                          | 384 bytes |
| **Total**           |                                                        | **403 bytes** |

The start value costs 8 bytes and the differencing saves 10 bits per value, so the
delta vector is 4.2x smaller than the undifferenced one. The reader unpacks 1,024
residuals, adds the frame of 0, and runs the prefix sum from 1,700,000,000,000.

**With an exception.** Take the same column but with one gap: `values[500]` jumps a
further 1,000,000,000. Then `d[500]` = 1,000,000,007 and every other difference is
still 7. Packing all of them needs bits\_required(1,000,000,007) = 30 bits, while
bit\_width = 3 with `d[500]` as an exception costs `1024 * 3 + 1 * (16 + 64)` =
3,152 bits, so the cost model keeps width 3:

| Section             | Content                                                 | Size     |
|---------------------|---------------------------------------------------------|----------|
| PforVectorInfo      | for=0, bit\_width=3 with bit 7 set, num\_exceptions=1   | 11 bytes |
| StartValue          | 1,700,000,000,000                                       | 8 bytes  |
| PackedValues        | \[0, 7, ..., **0**, ..., 7\] at 3 bits                  | 384 bytes |
| ExceptionPositions  | \[500\]                                                | 2 bytes  |
| ExceptionValues     | \[1,000,000,007\] -- the *difference*, not the value    | 8 bytes  |
| **Total**           |                                                         | **413 bytes** |

The reader unpacks, adds the frame, overwrites index 500 with 1,000,000,007, and
only then runs the prefix sum. Patching after the sum would leave the placeholder 0
in place for the sum, so every value from index 500 onwards would come out
1,000,000,000 too small -- and index 500 itself would be overwritten with a
difference where a value belongs.

## Characteristics

| Property       | Description                                                                          |
|----------------|--------------------------------------------------------------------------------------|
| Lossless       | All original integer values are perfectly recoverable                                |
| Adaptive       | Cost model selects optimal bit width per vector based on data distribution           |
| Vectorized     | Fixed-size vectors enable SIMD-optimized bit packing/unpacking                       |
| Exception-safe | Outlier values are stored separately without inflating bit width                     |
| Optional differencing | The delta mode packs successive differences, chosen per vector rather than per column |

**Best use cases:**

* Integer columns with mostly narrow range but occasional outliers
* Foreign key columns (date keys, store keys, customer keys)
* Sequence IDs with gaps or sentinel values
* Columns where DELTA\_BINARY\_PACKED is suboptimal (non-sequential data)
* Sorted, sequential or fixed-interval columns, through the delta mode
* Columns that are sorted in parts, where the delta mode can be taken per vector

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

PFOR and [DELTA\_BINARY\_PACKED](Encodings.md#DELTAENC) overlap where the data is sorted or
sequential, and differ in how the choice is made. DELTA\_BINARY\_PACKED always
differences; PFOR's delta mode differences when the writer decides it pays, per
vector, so one page can difference its sorted stretches and leave the rest on
absolute values. A plain PFOR vector operates on absolute values relative to the
frame, which is what suits a tight cluster with a few outliers.

## Size Calculations

### Vector Size Formula

```
vector_bytes = vector_header_size                           // INT32: 7, INT64: 11
             + (delta_flag ? value_byte_width : 0)          // start value (delta mode only)
             + ceil(num_elements * bit_width / 8)           // packed values
             + num_exceptions * 2                           // exception positions (uint16)
             + num_exceptions * value_byte_width            // exception values (4 or 8)
```

### Page Size Formula

```
page_bytes = 7                                   // page header
           + num_vectors * 4                     // offset array
           + sum(vector_bytes for each vector)   // all vectors
```

## Constants Reference

| Constant            | Value   | Description                             |
|---------------------|---------|-----------------------------------------|
| Vector size         | 1024    | Default elements per compressed vector  |
| INT32 max bit width | 32      | Maximum bits for uint32 residual        |
| INT64 max bit width | 64      | Maximum bits for uint64 residual        |
| Max exceptions      | 65,535  | uint16 limit per vector                 |
| Delta flag          | 0x80    | Bit 7 of the bit\_width byte            |
| Bit width mask      | 0x7F    | Bits 0-6 of the bit\_width byte         |
