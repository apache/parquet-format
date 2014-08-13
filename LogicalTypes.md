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

## Numeric Types

### Signed Integers

`INT_8`, `INT_16`, `INT_32`, and `INT_64` annotations can be used to specify
the maximum number of bits in the stored value.  Implementations may use these
annotations to produce smaller in-memory representations when reading data.

If a stored value is larger than the maximum allowed by the annotation, the
behavior is not defined and can be determined by the implementation.
Implementations must not write values that are larger than the annotation
allows.

`INT_8`, `INT_16`, and `INT_32` must annotate an `int32` primitive type and
`INT_64` must annotate an `int64` primitive type. `INT_32` and `INT_64` are
implied by the `int32` and `int64` primitive types if no other annotation is
present and should be considered optional.

### Unsigned Integers

`UINT_8`, `UINT_16`, `UINT_32`, and `UINT_64` annotations can be used to
specify unsigned integer types, along with a maximum number of bits in the
stored value. Implementations may use these annotations to produce smaller
in-memory representations when reading data.

If a stored value is larger than the maximum allowed by the annotation, the
behavior is not defined and can be determined by the implementation.
Implementations must not write values that are larger than the annotation
allows.

`UINT_8`, `UINT_16`, and `UINT_32` must annotate an `int32` primitive type and
`UINT_64` must annotate an `int64` primitive type.

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

## Date/Time Types

### DATE

`DATE` is used to for a logical date type, without a time of day. It must
annotate an `int32` that stores the number of days from the Unix epoch, 1
January 1970.

### TIME_MILLIS

`TIME_MILLIS` is used for a logical time type, without a date. It must annotate
an `int32` that stores the number of milliseconds after midnight.

### TIMESTAMP_MILLIS

`TIMESTAMP_MILLIS` is used for a combined logical date and time type. It must
annotate an `int64` that stores the number of milliseconds from the Unix epoch,
00:00:00.000 on 1 January 1970, UTC.

### INTERVAL

`INTERVAL` is used for an interval of time. It must annotate a
`fixed_len_byte_array` of length 12. This array stores three little-endian
unsigned integers that represent durations at different granularities of time.
The first stores a number in months, the second stores a number in days, and
the third stores a number in milliseconds. This representation is independent
of any particular timezone or date.

Each component in this representation is independent of the others. For
example, there is no requirement that a large number of days should be
expressed as a mix of months and days because there is not a constant
conversion from days to months.

## Embedded Types

### JSON

`JSON` is used for an embedded JSON document. It must annotate a `binary`
primitive type. The `binary` data is interpreted as a UTF-8 encoded character
string of valid JSON as defined by the [JSON specification][json-spec]

[json-spec]: http://json.org/

### BSON

`BSON` is used for an embedded BSON document. It must annotate a `binary`
primitive type. The `binary` data is interpreted as an encoded BSON document as
defined by the [BSON specification][bson-spec].

[bson-spec]: http://bsonspec.org/spec.html
