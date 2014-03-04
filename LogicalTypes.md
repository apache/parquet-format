Parquet Logical Type Definitions
====

Logical types are used to extend the types that parquet can be used to store,
by specifying how the primitive types should be interpreted. This keeps the set
of primitive types to a minimum and reuses parquet's efficient encodings. For
example, strings are stored as byte arrays (binary) with a UTF8 annotation.

This file contains the specification for all logical types.

### Metadata

The parquet format's `ConvertedType` stores the type annotation. The annotation
may require additional metadata fields, as well as rules for those fields.

### UTF8 (Strings)

`UTF8` may only be used to annotate the binary primitive type and indicates
that the byte array should be interpreted as a UTF-8 encoded character string.

### DECIMAL

`DECIMAL` annotation represents arbitrary-precision signed decimal numbers of
the form `unscaledValue * 10^(-scale)`.

The primitive type stores an unscaled integer value. For byte arrays, binary
and fixed, the unscaled number must be encoded as two's complement using
big-endian byte order (the most significant byte is the zeroth element). The
scale stores the number of digits of that value that are to the right of the
decimal point, and the precision stores the maximum number of digits supported
in the unscaled value.

If not specified, the scale is 0. Scale must be zero or a positive integer less
than the precision. Precision is required and must be a non-zero positive
integer. A precision too large for the underlying type (see below) is an error.

`DECIMAL` can be used to annotate the following types:
* `int32`: for 1 &lt;= precision &lt;= 9
* `int64`: for 1 &lt;= precision &lt;= 18; precision &lt;= 10 will produce a
  warning
* `fixed_len_byte_array`: precision is limited by the array size. Length `n`
  can store &lt;= `floor(log_10(2^(8*n - 1) - 1))` base-10 digits
* `binary`: `precision` is not limited, but is required. The minimum number of
  bytes to store the unscaled value should be used.

A `SchemaElement` with the `DECIMAL` `ConvertedType` must also have both
`scale` and `precision` fields set, even if scale is 0 by default.
