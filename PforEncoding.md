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
| 0 | frame_of_reference | 4 bytes | int32 | Minimum value in the vector |
| 4 | bit_width | 1 byte | uint8 | Bits per packed delta value. Range: \[0, 32\]. |
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
| 0 | frame_of_reference | 8 bytes | int64 | Minimum value in the vector |
| 8 | bit_width | 1 byte | uint8 | Bits per packed delta value. Range: \[0, 64\]. |
| 9 | num_exceptions | 2 bytes | uint16 | Number of exception values in this vector. |

#### PackedValues

The FOR-encoded deltas, bit-packed into `ceil(num_elements_in_vector * bit_width / 8)` bytes.
Values are packed from the least significant bit of each byte to the most significant bit,
in groups of 8 values, using the same bit-packing order as the
[RLE/Bit-Packing Hybrid](Encodings.md#RLE) encoding.

Exception positions contain 0 as a placeholder in the packed data. The actual
exception values are stored separately and patched during decoding.

If `bit_width` is 0, no bytes are stored (all deltas are zero, meaning all values
are equal to `frame_of_reference` and there are no exceptions).

#### ExceptionPositions

An array of `num_exceptions` little-endian uint16 values, each giving
the 0-based index within the vector of an exception value.

#### ExceptionValues

An array of `num_exceptions` values in the original integer type
(4 bytes little-endian for INT32, 8 bytes for INT64), stored in
the same order as the corresponding positions. These are the **original**
integer values (not FOR offsets).

## Encoding

### Frame of Reference

The frame of reference is the minimum value in the vector:

```
frame_of_reference = min(values[])
delta[i] = (unsigned)(values[i] - frame_of_reference)
```

All deltas are non-negative. The unsigned cast prevents signed overflow when
values span a large range (e.g., INT32\_MIN to INT32\_MAX).

### Cost-Model Bit Width Selection

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

### Exception Extraction

After selecting the optimal bit width:

1. Compute `mask = (1 << bit_width) - 1` (for bit\_width < max\_bits; if
   bit\_width equals max\_bits, there are no exceptions).
2. For each delta where `delta[i] > mask`:
   * Record the position `i` in the exception positions array.
   * Record the **original value** `values[i]` in the exception values array.
   * Replace `delta[i]` with 0 in the delta array (placeholder for bit-packing).

### Bit-Packing

Pack the deltas (with exception placeholders set to 0) using `bit_width` bits
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

## Example 1: Integer Keys with an Outlier

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

## Example 2: Uniform Data (No Exceptions)

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

## Example 3: Date Key Column (TPC-DS pattern)

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

## Characteristics

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

PFOR and [DELTA\_BINARY\_PACKED](Encodings.md#DELTAENC) are complementary: DELTA\_BINARY\_PACKED
excels on sorted or sequential data where successive differences are small, while
PFOR excels on data with a tight cluster and a few outliers. PFOR does not compute
deltas between successive values -- it operates on absolute values relative to
the minimum.

## Size Calculations

### Vector Size Formula

```
vector_bytes = vector_header_size                           // INT32: 7, INT64: 11
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
| INT32 max bit width | 32      | Maximum bits for uint32 delta           |
| INT64 max bit width | 64      | Maximum bits for uint64 delta           |
| Max exceptions      | 65,535  | uint16 limit per vector                 |
