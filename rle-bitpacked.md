# RLE-Bitpacked hybrid encoder

The RLE-Bitpacked hybrid encoder is a parquet-specific encoder that combines two well known encoding strategies,
[RLE](https://en.wikipedia.org/wiki/Run-length_encoding) and bitpacking. Note that "combine" here means this encoder allows both encodings within the same stream, and, during encoding, it can switch between them.

This encoder is only used to encode integer values that may either represent definition levels, representation levels or ids of dictionary-encoded pages. Note that this encoder supports integers that can be represented in less than 8 bits.

This document uses [LSB](https://en.wikipedia.org/wiki/Bit_numbering#Least_significant_bit) to identify bits. In this representation, a byte is represented by `[b7 b6 b5 b4 b3 b2 b1 b0]` where `b0` is the first bit.

This document uses MUST, SHOULD, etc. according to [RFC-8174](https://tools.ietf.org/html/rfc8174).

## Decoding

Decoding a stream of bytes (denoted as `[a1, a2, a3, ...]`) assumes a specific `bit_width` indicating the number of bits necessary to represent the largest encoded integer in the stream.

The `bit_width` MUST be sufficient to represent the largest encoded integer on the stream or the result is undefined.

The first 4 bytes of the stream MUST represent a little-endian unsigned integer (`uint32`) with the length of the rest of the stream. For example, `[4u8, 0, 0, 0]` announces that the stream has a total of `4 + 4 = 8` bytes. The first 4 bytes are only used for this purpose.

The remaining bytes are divided in "runs", which MUST be either RLE-encoded or bitpacked-encoded. Each "run" MUST be composed by a header of a variable number of bytes and by a body, in sequence, i.e. `[h1, h1, h1, ...]`. The header MUST be a single [ULEB128](https://en.wikipedia.org/wiki/LEB128#Unsigned_LEB128)-encoded `i32`, here denoted as `h1`. The bytes needed to decode the ULEB128-encoded constitute the header and the remaining bytes constitute the body.

The first bit of the last byte of the header is denotes whether the run is bitpacked-encoded or RLE-encoded. `h1 & 1 == 1` indicates a bitpacked-encoded run, `h1 & 1 != 1` a RLE-encoded run.

### Decoding RLE-encoded runs

Given a header `h1` and the stream of bytes past the header, the number of repetitions is given by `repetitions = h1 >> 1`. The number of bytes in the body, `body_length`, MUST be the minimum number of bytes that can hold `bit_width`, `body_length = ceil(bit_width, 8)`. The body MUST represent the repeated value in little endian for byte types (e.g. `int32`) and [LSB](https://en.wikipedia.org/wiki/Bit_numbering#Least_significant_bit) for boolean types.

### Decoding bitpacked-encoded runs

Given a header `h1` and the stream of bytes past the header, the number of bytes in the body, `body_length`, is equal to `body_length = h1 >> 1`. The body represents bitpacked-encoded values with exactly `8 / bit_width` items.

Note that for `bit_width = 1`, this encoding corresponds exactly to LSB. Thus, in-memory formats that store booleans or validities in `LSB` (e.g. Apache Arrow), the body can be memcopied as is to a bitmap.

### Example:

Let's now consider the the following byte stream and a `bit_width = 1`:

```
[
    5, 0, 0, 0,
    0b00000101, 0b11101011, 0b00000010,
    0b00010000, 0b00000001,
    0b00000101,
    0b00000101,
]
```

We use the first 4 bytes to identify relevant length, within the stream, of the encoded bytes. This corresponds to `[5, 0, 0, 0]` which in little endian corresponds to `5u32`. We can thus assume that all runs of this encoded stream are encoded in 

```
[
    0b00000101, 0b11101011, 0b00000010,
    0b00010000, 0b00000001,
]
```

The ULEB128-decoding of this stream yields `h1 = 5i32` and length 1, i.e. the first byte is enough to represent the header of the first run. `5 & 1 == 1` and thus the first run is bitpacked-encoded. `body_length = 5i32 >> 1 = 2`, which means that the next two bytes form the body. bit-unpacking these two bytes yields (in `i32`, 

```
[
    1, 1, 0, 1, 0, 1, 1, 1, 
    0, 1, 0, 0, 0, 0, 0, 0
]
```

(read bytes left to right, and bits within a byte right to left).

We proceed through the stream, from which `[0b00010000, 0b00000001]` remains, and repeat the operation: the ULEB128-decoding yields `h1 = 16i32`. `16 & 1 == 0` and thus the next run is RLE-encoded. We compute the number of repetitions via `repetitions = h1 >> 1 = 8`. The body size is `body_length = ceil(bit_width, 8) = 1`, which is consistent with `length = 5 = 1 + 2 + 1 + 1`. Since the body is `0b00000001 = 1`, we conclude that this run is the number 1 repeated 8 times, `[1, 1, 1, 1, 1, 1, 1, 1]`.

We reached the end of the stream and thus the final result is

```
[
    1, 1, 0, 1, 0, 1, 1, 1, 
    0, 1, 0, 0, 0, 0, 0, 0,
    1, 1, 1, 1, 1, 1, 1, 1,
]
```
