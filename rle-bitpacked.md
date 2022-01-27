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

# RLE/bit-packed hybrid encoding

The RLE/bit-packed hybrid encoding is a parquet-specific encoding that combines
two well known encoding strategies, [RLE](https://en.wikipedia.org/wiki/Run-length_encoding)
and bit-packing. Note that "combine" here means this encoding allows both encodings
within the same stream, and, during encoding, it can switch between them.

This encoding is used to encode integer values that may either represent definition levels,
representation levels, or ids of dictionary-encoded pages.

This document uses MUST, SHOULD, etc. according to [RFC-8174](https://tools.ietf.org/html/rfc8174).

## Decoding

Decoding a stream of N bytes requires knowledge a specific `bit_width`, indicating the number of
bits necessary to represent the largest encoded integer in the stream.
The `bit_width` is a parameter of the decoder.

The `bit_width` MUST be sufficient to represent the largest encoded integer on the
stream or the result is undefined.

The bytes are divided in "runs", which MUST be either RLE-encoded or bitpacked-encoded.
Each "run" MUST be composed by a header of a variable number of bytes and by a body, in sequence.
I.e. `[h11, h12, h13, b11, b12, ...]` where `h11` is the first byte of the header
of run `1`, `h12` the second byte of the header, `b11` is the first byte of the body of the first run.

The header MUST be a single [ULEB128](https://en.wikipedia.org/wiki/LEB128#Unsigned_LEB128)-encoded,
here denoted as `h1`. The bytes needed to decode the ULEB128-encoded constitute the header,
and the remaining bytes constitute the body.

The LSB of the last byte of the header denotes whether the run is bitpacked-encoded
or RLE-encoded. `h1 & 1 == 1` indicates a bitpacked-encoded run, `h1 & 1 != 1` a RLE-encoded run.

### Decoding RLE-encoded runs

Given a header `h1` and the stream of bytes past the header, the number of repetitions
is given by `repetitions = h1 >> 1`. The number of bytes in the body, `body_length`,
MUST be the minimum number of bytes that can hold `bit_width`, `body_length = ceil(bit_width, 8)`.
The body MUST represent the repeated value in little endian for byte types (e.g. `int32`) and
[LSB](https://en.wikipedia.org/wiki/Bit_numbering#Least_significant_bit) for boolean types.

### Decoding bitpacked-encoded runs

Given a header `h1` and the stream of bytes past the header, the number of bytes
in the body, `body_length`, is equal to `body_length = (h1 >> 1) * bit_width`.
The body represents bitpacked-encoded values with exactly `8 / bit_width` items.

Note that for in-memory formats that use bitmaps where the LSB corresponds
to the first slot (e.g. Apache Arrow), the decoding is the identity function.

### Example

Let's now consider the following byte stream and a `bit_width = 1`,

```
[
    0b00000101, 0b11101011, 0b00000010,
    0b00010000, 0b00000001,
]
```

which could appear in a definition level of a non-nested Parquet type.

The ULEB128-decoding of this stream yields `h1 = 5` and length 1, i.e. the
first byte is enough to represent the header of the first run. Because `5 & 1 == 1`,
we conclude that the first run is bitpacked-encoded. `body_length = (5 >> 1) * 1 = 2`,
which means that the next two bytes form the body. Bit-unpacking these two
bytes yields,

```
[
    1, 1, 0, 1, 0, 1, 1, 1, 
    0, 1, 0, 0, 0, 0, 0, 0
]
```

(to understand why this is the case, read `0b11101011, 0b00000010` left to right,
and bits within a byte right to left).

We proceed through the stream, from which `[0b00010000, 0b00000001]` remains,
and repeat the operation: the ULEB128-decoding yields `h1 = 16`. `16 & 1 == 0`
and thus the next run is RLE-encoded. We compute the number of repetitions
via `repetitions = h1 >> 1 = 8`. The body size is `body_length = ceil(bit_width, 8) = 1`.
Since the body is `0b00000001 = 1`, we conclude that this run is the number 1 repeated 8 times,
`[1, 1, 1, 1, 1, 1, 1, 1]`.

We reached the end of the stream and thus the decoded result is

```
[
    1, 1, 0, 1, 0, 1, 1, 1, 
    0, 1, 0, 0, 0, 0, 0, 0,
    1, 1, 1, 1, 1, 1, 1, 1,
]
```
