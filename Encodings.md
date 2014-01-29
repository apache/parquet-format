Parquet encoding definitions
====

This file contains the specification of all supported encodings.

### Plain: (PLAIN = 0)

Supported Types: all

This is the plain encoding that must be supported for types.  It is
intended to be the simplest encoding.  Values are encoded back to back. 

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

For native types, this outputs the data as little endian. Floating
    point types are encoded in IEEE.  

For the byte array type, it encodes the length as a 4 byte little
endian, followed by the bytes.

### Dictionary Encoding (PLAIN_DICTIONARY = 2)
The dictionary encoding builds a dictionary of values encountered in a given column. The 
dictionary will be stored in a dictionary page per column chunk. The values are stored as integers
using the RLE/Bit-Packing Hybrid encoding described above. If the dictionary grows too big, whether in size
or number of distinct values, the encoding will fall back to the plain encoding. The dictionary page is 
written first, before the data pages of the column chunk.

Dictionary page format: the entries in the dictionary - in dictionary order - using the plain encoding described above.

Data page format: the bit width used to encode the entry ids stored as 1 byte (max bit width = 32),
followed by the values encoded using RLE/Bit packed described above (with the given bit width).

### Run Length Encoding / Bit-Packing Hybrid (RLE = 3)
This encoding uses a combination of bit-packing and run length encoding to more efficiently store repeated values.

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

### Bit-packed (Deprecated) (BIT_PACKED = 4)
This is a bit-packed only encoding, which is deprecated and will be replaced by the run length ecoding / bit backing hybrid in the next section.
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

### Delta Encoding (DELTA_BINARY_PACKED = 5)
Supported Types: INT32, INT64

This encoding is adapted from the Binary packing described in ["Decoding billions of integers per second through vectorization"](http://arxiv.org/pdf/1209.2137v5.pdf) by D. Lemire and L. Boytsov

Delta encoding consists of a header followed by blocks of delta encoded values binary packed. Each block is made of miniblocks, each of them binary packed with its own bit width. When there are not enough values to encode a full block we pad with zeros (added to the frame of reference).
The header is defined as follows:
```
<block size in values> <number of miniblocks in a block> <total value count> <first value>
```
 * the block size is a multiple of 128 stored as VLQ int
 * the miniblock count per block is a diviser of the block size stored as VLQ int the number of values in the miniblock is a multiple of 32.
 * the total value count is stored as a VLQ int
 * the first value is stored as a zigzag VLQ int

Each block contains 
```
<min delta> <list of bitwidths of miniblocks> <miniblocks>
```
 * the min delta is a VLQ int (we compute a minimum as we need positive integers for bit packing)
 * the bitwidth of each block is stored as a byte
 * each miniblock is a list of bit packed ints according to the bit width stored at the begining of the block

Having multiple blocks allows us to escape values and restart from a new base value.

To encode each delta block, we will:

1. Compute the deltas

2. Encode the first value as zigzag VLQ int

3. For each block, compute the frame of reference(minimum of the deltas) for the deltas. This guarantees
all deltas are positive.

4. encode the frame of reference delta as VLQ int followed by the delta values (minus the minimum) encoded as bit packed per miniblock.

Steps 2 and 3 are skipped if the number of values in the block is 1.

#### Example 1
1, 2, 3, 4, 5

After step 1), we compute the deltas as:

1, 1, 1, 1

The minimum delta is 1 and after step 2, the deltas become

0, 0, 0, 0

The final encoded data is:

 header:
8 (block size), 1 (miniblock count), 5 (value count), 1 (first value)

 block
1 (minimum delta), 0 (bitwidth), (no data needed for bitwidth 0)

#### Example 2
7, 5, 3, 1, 2, 3, 4, 5, the deltas would be

-2, -2, -2, 1, 1, 1, 1

The minimum is -2, so the relative deltas are:

0, 0, 0, 3, 3, 3, 3

The encoded data is

 header:
8 (block size), 1 (miniblock count), 8 (value count), 7 (first value)

 block
0 (minimum delta), 2 (bitwidth), 000000111111b (0,0,0,3,3,3 packed on 2 bits)

#### Characteristics
This encoding is similar to the RLE encoding. However the RLE encoding (described here) is specifically used when the range of ints is small over the entire page, as is true of repetition and definition levels. It uses a single bit width for the whole page.
The binary packing algorithm described above stores a bit width per mini block and is less sensitive to variations in the size of encoded integers. It is also somewhat doing RLE encoding as a block containing all the same values will be bit packed to a zero bit width thus being only a header.

### Delta-length byte array: (DELTA_LENGTH_BYTE_ARRAY = 6)

Supported Types: BYTE_ARRAY

This encoding is always preferred over PLAIN for byte array columns.

For this encoding, we will take all the byte array lengths and encode them using delta
encoding (DELTA_BINARY_PACKED). The byte array data follows all of the length data just
concatenated back to back. The expected savings is from the cost of encoding the lengths
and possibly better compression in the data (it is no longer interleaved with the lengths).

The data stream looks like:

<Delta Encoded Lengths> <Byte Array Data>

For example, if the data was "Hello", "World", "Foobar", "ABCDEF":

The encoded data would be DeltaEncoding(5, 5, 6, 6) "HelloWorldFoobarABCDEF"

### Delta Strings: (DELTA_BYTE_ARRAY = 7)

Supported Types: BYTE_ARRAY

This is also known as incremental encoding or front compression: for each element in a
sequence of strings, store the prefix length of the previous entry plus the suffix.

For a longer description, see http://en.wikipedia.org/wiki/Incremental_encoding.

This is stored as a sequence of delta-encoded prefix lengths (DELTA_BINARY_PACKED), followed by
the suffixes encoded as delta length byte arrays (DELTA_LENGTH_BYTE_ARRAY). 
