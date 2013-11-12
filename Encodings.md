Parquet encoding definitions
====

This file contains the specification of all supported encodings.

### Plain:

Supported Types: all

This is the plain encoding that must be supported for types.  It is
intended to be the simplest encoding.  Values are encoded back to back. 

For native types, this outputs the data as little endian. Floating
    point types are encoded in IEEE.  

For the byte array type, it encodes the length as a 4 byte little
endian, followed by the bytes.

### GroupVarInt:

Supported Types: INT32, INT64


32-bit ints are encoded in groups of 4 with 1 leading bytes to encode the
byte length of the following 4 ints.

64-bit are encoded in groups of 5,
with 2 leading bytes to encode the byte length of the 5 ints.  

For 32-bit ints, the leading byte contains 2 bits per int.  Each length
encoding specifies the number of bytes minus 1 for that int.  For example
a byte value of 0b00101101, indicates that:

  * the first int has 1 byte (0b00 + 1), 
  * the second int has 3 bytes (0b10 + 1),
  * the third int has 4 bytes (0b11 + 1)
  * the 4th int has 2 bytes (0b01 + 1)

In this case, the entire row group would be: 1 + (1 + 3 + 4 + 2) = 11 bytes.  
The bytes that follow the leading byte is just the int data encoded in little
endian.  With this example:

  * the first int starts at byte offset 1 with a max value of 0xFF,
  * the second int starts at byte offset 2 with a max value of 0xFFFFFF,
  * the third int starts at byte offset 5 with a max value of 0xFFFFFFFF, and
  * the 4th int starts at byte offset 9 with a max value of 0xFFFF. 

For 64-bit ints, the lengths of the 5 ints is encoded as 3 bits.  Combined,
this uses 15 bits and fits in 2 bytes.  The msb of the two bytes is unused.
Like the 32-bit case, after the length bytes, the data bytes follow.

In the case where the data does not make a complete group, (e.g. 3 32-bit ints),
a complete group should still be output with 0's filling in for the remainder.
For example, if the input was (1,2,3,4,5): the resulting encoding should
behave as if the input was (1,2,3,4,5,0,0,0) and the two groups should be
encoded back to back.

### Delta-length byte array:

Supported Types: BYTE_ARRAY

This encoding is always preferred over PLAIN for byte array columns.

For this encoding, we will take all the byte array lengths and encode them using delta
encoding. The byte array data follows all of the length data just concatenated back to 
back. The expected savings is from the cost of encoding the lengths and possibly 
better compression in the data (it is no longer interleaved with the lengths).

The data stream looks like:

<Delta Encoded Lengths> <Byte Array Data>

For example, if the data was "Hello", "World", "Foobar", "ABCDEF":

The encoded data would be DeltaEncoding(5, 5, 6, 6) "HelloWorldFoobarABCDEF"

### Delta Strings:

Supported Types: BYTE_ARRAY

This is also known as incremental encoding or front compression: for each element in a
sorted sequence of strings, store the prefix length of the previous entry plus the
suffix.

For a longer description, see http://en.wikipedia.org/wiki/Incremental_encoding.

This is stored as a sequence of delta-encoded prefix lengths (DELTA_BINARY_PACKED), followed by
the suffixes encoded as delta length byte arrays (DELTA_LENGTH_BYTE_ARRAY). 

