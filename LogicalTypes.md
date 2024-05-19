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

The parquet format's `LogicalType` stores the type annotation. The annotation
may require additional metadata fields, as well as rules for those fields.

There is an older representation of the logical type annotations called `ConvertedType`.
To support backward compatibility with old files, readers should interpret `LogicalTypes`
in the same way as `ConvertedType`, and writers should populate `ConvertedType` in the metadata
according to well defined conversion rules.

### Compatibility

The Thrift definition of the metadata has two fields for logical types: `ConvertedType` and `LogicalType`.
`ConvertedType` is an enum of all available annotations. Since Thrift enums can't have additional type parameters,
it is cumbersome to define additional type parameters, like decimal scale and precision
(which are additional 32 bit integer fields on SchemaElement, and are relevant only for decimals) or time unit
and UTC adjustment flag for Timestamp types. To overcome this problem, a new logical type representation was introduced into
the metadata to replace `ConvertedType`: `LogicalType`.  The new representation is a union of structs of logical types,
this way allowing more flexible API, logical types can have type parameters.

`ConvertedType` is deprecated. However, to maintain compatibility with old writers,
Parquet readers should be able to read and interpret `ConvertedType` annotations
in case `LogicalType` annotations are not present. Parquet writers must always write
`LogicalType` annotations where applicable, but must also write the corresponding
`ConvertedType` annotations (if any) to maintain compatibility with old readers.

Compatibility considerations are mentioned for each annotation in the corresponding section.

## String Types

### STRING

`STRING` may only be used to annotate the binary primitive type and indicates
that the byte array should be interpreted as a UTF-8 encoded character string.

The sort order used for `STRING` strings is unsigned byte-wise comparison.

*Compatibility*

`STRING` corresponds to `UTF8` ConvertedType.

### ENUM

`ENUM` annotates the binary primitive type and indicates that the value
was converted from an enumerated type in another data model (e.g. Thrift, Avro, Protobuf).
Applications using a data model lacking a native enum type should interpret `ENUM`
annotated field as a UTF-8 encoded string. 

The sort order used for `ENUM` values is unsigned byte-wise comparison.

### UUID

`UUID` annotates a 16-byte fixed-length binary. The value is encoded using
big-endian, so that `00112233-4455-6677-8899-aabbccddeeff` is encoded as the
bytes `00 11 22 33 44 55 66 77 88 99 aa bb cc dd ee ff`
(This example is from [wikipedia's UUID page][wiki-uuid]).

The sort order used for `UUID` values is unsigned byte-wise comparison.

[wiki-uuid]: https://en.wikipedia.org/wiki/Universally_unique_identifier

## Numeric Types

### Signed Integers

`INT` annotation can be used to specify the maximum number of bits in the stored value.
The annotation has two parameters: bit width and sign.
Allowed bit width values are `8`, `16`, `32`, `64`, and sign can be `true` or `false`.
For signed integers, the second parameter should be `true`,
for example, a signed integer with bit width of 8 is defined as `INT(8, true)`
Implementations may use these annotations to produce smaller
in-memory representations when reading data.

If a stored value is larger than the maximum allowed by the annotation, the
behavior is not defined and can be determined by the implementation.
Implementations must not write values that are larger than the annotation
allows.

`INT(8, true)`, `INT(16, true)`, and `INT(32, true)` must annotate an `int32` primitive type and
`INT(64, true)` must annotate an `int64` primitive type. `INT(32, true)` and `INT(64, true)` are
implied by the `int32` and `int64` primitive types if no other annotation is
present and should be considered optional.

The sort order used for signed integer types is signed.

### Unsigned Integers

`INT` annotation can be used to specify unsigned integer types,
along with a maximum number of bits in the stored value.
The annotation has two parameters: bit width and sign.
Allowed bit width values are `8`, `16`, `32`, `64`, and sign can be `true` or `false`.
In case of unsigned integers, the second parameter should be `false`,
for example, an unsigned integer with bit width of 8 is defined as `INT(8, false)`
Implementations may use these annotations to produce smaller
in-memory representations when reading data.

If a stored value is larger than the maximum allowed by the annotation, the
behavior is not defined and can be determined by the implementation.
Implementations must not write values that are larger than the annotation
allows.

`INT(8, false)`, `INT(16, false)`, and `INT(32, false)` must annotate an `int32` primitive type and
`INT(64, false)` must annotate an `int64` primitive type.

The sort order used for unsigned integer types is unsigned.

### Deprecated integer ConvertedType

`INT_8`, `INT_16`, `INT_32`, and `INT_64` annotations can be also used to specify
signed integers with 8, 16, 32, or 64 bit width.

`INT_8`, `INT_16`, and `INT_32` must annotate an `int32` primitive type and
`INT_64` must annotate an `int64` primitive type. `INT_32` and `INT_64` are
implied by the `int32` and `int64` primitive types if no other annotation is
present and should be considered optional.

`UINT_8`, `UINT_16`, `UINT_32`, and `UINT_64` annotations can be also used to specify
unsigned integers with 8, 16, 32, or 64 bit width.

`UINT_8`, `UINT_16`, and `UINT_32` must annotate an `int32` primitive type and
`UINT_64` must annotate an `int64` primitive type.

*Backward compatibility:*

| ConvertedType | LogicalType |
|---------------|-------------|
| INT_8  | IntType (bitWidth = 8, isSigned = true) |
| INT_16 | IntType (bitWidth = 16, isSigned = true) |
| INT_32 | IntType (bitWidth = 32, isSigned = true) |
| INT_64 | IntType (bitWidth = 64, isSigned = true) |
| UINT_8  | IntType (bitWidth = 8, isSigned = false) |
| UINT_16 | IntType (bitWidth = 16, isSigned = false) |
| UINT_32 | IntType (bitWidth = 32, isSigned = false) |
| UINT_64 | IntType (bitWidth = 64, isSigned = false) |

*Forward compatibility:*

<table>
    <tr colspan="3">
        <th colspan="3">LogicalType</th>
        <th>ConvertedType</th>
    </tr>
    <tr>
        <td rowspan="8">IntType</td>
        <td rowspan="4">isSigned</td>
        <td>bitWidth = 8</td>
        <td>INT_8</td>
    </tr>
    <tr>
        <td>bitWidth = 16</td>
        <td>INT_16</td>
    </tr>
    <tr>
        <td>bitWidth = 32</td>
        <td>INT_32</td>
    </tr>
    <tr>
        <td>bitWidth = 64</td>
        <td>INT_64</td>
    </tr>
    <tr>
        <td rowspan="4">!isSigned</td>
        <td>bitWidth = 8</td>
        <td>UINT_8</td>
    </tr>
    <tr>
        <td>bitWidth = 16</td>
        <td>UINT_16</td>
    </tr>
    <tr>
        <td>bitWidth = 32</td>
        <td>UINT_32</td>
    </tr>
    <tr>
        <td>bitWidth = 64</td>
        <td>UINT_64</td>
    </tr>
</table>

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
than or equal to the precision. Precision is required and must be a non-zero positive
integer. A precision too large for the underlying type (see below) is an error.

`DECIMAL` can be used to annotate the following types:
* `int32`: for 1 &lt;= precision &lt;= 9
* `int64`: for 1 &lt;= precision &lt;= 18; precision &lt; 10 will produce a
  warning
* `fixed_len_byte_array`: precision is limited by the array size. Length `n`
  can store &lt;= `floor(log_10(2^(8*n - 1) - 1))` base-10 digits
* `binary`: `precision` is not limited, but is required. The minimum number of
  bytes to store the unscaled value should be used.

The sort order used for `DECIMAL` values is signed comparison of the represented
value.

If the column uses `int32` or `int64` physical types, then signed comparison of
the integer values produces the correct ordering. If the physical type is
fixed, then the correct ordering can be produced by flipping the
most-significant bit in the first byte and then using unsigned byte-wise
comparison.

*Compatibility*

To support compatibility with older readers, implementations of parquet-format should
write `DecimalType` precision and scale into the corresponding SchemaElement field in metadata.

### FLOAT16

The `FLOAT16` annotation represents half-precision floating-point numbers in the 2-byte IEEE little-endian format.

Used in contexts where precision is traded off for smaller footprint and potentially better performance.

The primitive type is a 2-byte fixed length binary.

The type-defined sort order for `FLOAT16` is signed (with special handling of NaNs and signed zeros), as for `FLOAT` and `DOUBLE`. It is recommended that writers use IEEE754TotalOrder when writing columns of this type for a well-defined handling of NaNs and signed zeros. See the `ColumnOrder` union in the [Thrift definition](src/main/thrift/parquet.thrift) for details.

## Temporal Types

### DATE

`DATE` is used to for a logical date type, without a time of day. It must
annotate an `int32` that stores the number of days from the Unix epoch, 1
January 1970.

The sort order used for `DATE` is signed.

### TIME

`TIME` is used for a logical time type without a date with millisecond or microsecond precision.
The type has two type parameters: UTC adjustment (`true` or `false`)
and unit (`MILLIS` or `MICROS`, `NANOS`).

`TIME` with unit `MILLIS` is used for millisecond precision.
It must annotate an `int32` that stores the number of
milliseconds after midnight.

`TIME` with unit `MICROS` is used for microsecond precision.
It must annotate an `int64` that stores the number of
microseconds after midnight.

`TIME` with unit `NANOS` is used for nanosecond precision.
It must annotate an `int64` that stores the number of
nanoseconds after midnight.

The sort order used for `TIME` is signed.

#### Deprecated time ConvertedType

`TIME_MILLIS` is the deprecated ConvertedType counterpart of a `TIME` logical
type that is UTC normalized and has `MILLIS` precision. Like the logical type
counterpart, it must annotate an `int32`.

`TIME_MICROS` is the deprecated ConvertedType counterpart of a `TIME` logical
type that is UTC normalized and has `MICROS` precision. Like the logical type
counterpart, it must annotate an `int64`.

Despite there is no exact corresponding ConvertedType for local time semantic,
in order to support forward compatibility with those libraries, which annotated
their local time with legacy `TIME_MICROS` and `TIME_MILLIS` annotation,
Parquet writer implementation *must* annotate local time with legacy annotations too,
as shown below.

*Backward compatibility:*

| ConvertedType | LogicalType |
|---------------|-------------|
| TIME_MILLIS | TimeType (isAdjustedToUTC = true, unit = MILLIS) |
| TIME_MICROS | TimeType (isAdjustedToUTC = true, unit = MICROS) |

*Forward compatibility:*

<table>
    <tr colspan="3">
        <th colspan="3">LogicalType</th>
        <th>ConvertedType</th>
    </tr>
    <tr>
        <td rowspan="6">TimeType</td>
        <td rowspan="3">isAdjustedToUTC = true</td>
        <td>unit = MILLIS</td>
        <td>TIME_MILLIS</td>
    </tr>
    <tr>
        <td>unit = MICROS</td>
        <td>TIME_MICROS</td>
    </tr>
    <tr>
        <td>unit = NANOS</td>
        <td>-</td>
    </tr>
    <tr>
        <td rowspan="3">isAdjustedToUTC = false</td>
        <td>unit = MILLIS</td>
        <td>TIME_MILLIS</td>
    </tr>
    <tr>
        <td>unit = MICROS</td>
        <td>TIME_MICROS</td>
    </tr>
    <tr>
        <td>unit = NANOS</td>
        <td>-</td>
    </tr>
</table>

### TIMESTAMP

In data annotated with the `TIMESTAMP` logical type, each value is a single
`int64` number that can be decoded into year, month, day, hour, minute, second
and subsecond fields using calculations detailed below. Please note that a value
defined this way does not necessarily correspond to a single instant on the
time-line and such interpretations are allowed on purpose.

The `TIMESTAMP` type has two type parameters:
- `isAdjustedToUTC` must be either `true` or `false`.
- `unit` must be one of `MILLIS`, `MICROS` or `NANOS`. This list is subject
  to potential expansion in the future. Upon reading, unknown `unit`-s must
  be handled as unsupported features (rather than as errors in the data files).

#### Instant semantics (timestamps normalized to UTC)

A `TIMESTAMP` with `isAdjustedToUTC=true` is defined as the number of
milliseconds, microseconds or nanoseconds (depending on the `unit`
parameter being `MILLIS`, `MICROS` or `NANOS`, respectively) elapsed since the
Unix epoch, 1970-01-01 00:00:00 UTC. Each such value unambiguously identifies a
single instant on the time-line.

For example, in a `TIMESTAMP(isAdjustedToUTC=true, unit=MILLIS)`, the
number 172800000 corresponds to 1970-01-03 00:00:00 UTC, because it is equal to
2 * 24 * 60 * 60 * 1000, therefore it is exactly two days from the reference
point, the Unix epoch. In Java, this calculation can be achieved by calling
`Instant.ofEpochMilli(172800000)`.

As a slightly more complicated example, if one wants to store 1970-01-03
00:00:00 (UTC+01:00) as a `TIMESTAMP(isAdjustedToUTC=true, unit=MILLIS)`,
first the time zone offset has to be dealt with. By normalizing the timestamp to
UTC, we calculate what time in UTC corresponds to the same instant: 1970-01-02
23:00:00 UTC. This is 1 day and 23 hours after the epoch, therefore it can be
encoded as the number (24 + 23) * 60 * 60 * 1000 = 169200000.

Please note that time zone information gets lost in this process. Upon reading a
value back, we can only reconstruct the instant, but not the original
representation. In practice, such timestamps are typically displayed to users in
their local time zones, therefore they may be displayed differently depending on
the execution environment.

#### Local semantics (timestamps not normalized to UTC)

A `TIMESTAMP` with `isAdjustedToUTC=false` represents year, month, day, hour,
minute, second and subsecond fields in a local timezone, _regardless of what
specific time zone is considered local_. This means that such timestamps should
always be displayed the same way, regardless of the local time zone in effect.
On the other hand, without additional information such as an offset or
time-zone, these values do not identify instants on the time-line unambiguously,
because the corresponding instants would depend on the local time zone.

Using a single number to represent a local timestamp is a lot less intuitive
than for instants. One must use a local timestamp as the reference point and
calculate the elapsed time between the actual timestamp and the reference point.
The problem is that the result may depend on the local time zone, for example
because there may have been a daylight saving time change between the two
timestamps.

The solution to this problem is to use a simplification that makes the result
easy to calculate and independent of the timezone. Treating every day as
consisting of exactly 86400 seconds and ignoring DST changes altogether allows
us to unambiguously represent a local timestamp as a difference from a reference
local timestamp. We define the reference local timestamp to be 1970-01-01
00:00:00 (note the lack of UTC at the end, as this is not an instant). This way
the encoding of local timestamp values becomes very similar to the encoding of
instant values. For example, in a `TIMESTAMP(isAdjustedToUTC=false,
unit=MILLIS)`, the number 172800000 corresponds to 1970-01-03 00:00:00
(note the lack of UTC at the end), because it is exactly two days from the
reference point (172800000 = 2 * 24 * 60 * 60 * 1000).

Another way to get to the same definition is to treat the local timestamp value
_as if_ it were in UTC and store it as an instant. For example, if we treat the
local timestamp 1970-01-03 00:00:00 _as if_ it were the instant 1970-01-03
00:00:00 UTC, we can store it as 172800000. When reading 172800000 back, we can
reconstruct the instant 1970-01-03 00:00:00 UTC and convert it to a local
timestamp _as if_ we were in the UTC time zone, resulting in 1970-01-03
00:00:00. In Java, this can be achieved by calling
`LocalDateTime.ofEpochSecond(172800, 0, ZoneOffset.UTC)`.

Please note that while from a practical point of view this second definition is
equivalent to the first one, from a theoretical point of view only the first
definition can be considered correct, the second one just "incidentally" leads
to the same results. Nevertheless, this second definition is worth mentioning as
well, because it is relatively widespread and it can lead to confusion,
especially due to its usage of UTC in the calculations. One can stumble upon
code, comments and specifications ambiguously stating that a timestamp "is
stored in UTC". In some contexts, it means that it is _normalized_ to UTC and
acts as an instant. In some other contexts though, it means the exact opposite,
namely that the timestamp is stored _as if_ it were in UTC and acts as a
local timestamp in reality.

#### Common considerations

Every possible `int64` number represents a valid timestamp, but depending on the
precision, the corresponding year may be outside of the practical everyday
limits and implementations may choose to only support a limited range.

On the other hand, not every combination of year, month, day, hour, minute,
second and subsecond values can be encoded into an `int64`. Most notably:

- An arbitrary combination of timestamp fields can not be encoded as a single
  number if the values for some of the fields are outside of their normal range
  (where the "normal range" corresponds to everyday usage). For example, neither
  of the following can be represented in a timestamp:
  - hour = -1
  - hour = 25
  - minute = 61
  - month = 13
  - day = 29, month = 2, year = any non-leap year
- Due to the range of the `int64` type, timestamps using the `NANOS` unit
  can only represent values between 1677-09-21 00:12:43 and 2262-04-11 23:47:16.
  Values outside of this range can not be represented with the `NANOS`
  unit. (Other precisions have similar limits but those are outside of the
  domain for practical everyday usage.)

The sort order used for `TIMESTAMP` is signed.

#### Deprecated timestamp ConvertedType

`TIMESTAMP_MILLIS` is the deprecated ConvertedType counterpart of a `TIMESTAMP`
logical type that is UTC normalized and has `MILLIS` precision. Like the logical
type counterpart, it must annotate an `int64`.

`TIMESTAMP_MICROS` is the deprecated ConvertedType counterpart of a `TIMESTAMP`
logical type that is UTC normalized and has `MICROS` precision. Like the logical
type counterpart, it must annotate an `int64`.

Despite there is no exact corresponding ConvertedType for local timestamp semantic,
in order to support forward compatibility with those libraries, which annotated
their local timestamps with legacy `TIMESTAMP_MICROS` and `TIMESTAMP_MILLIS` annotation,
Parquet writer implementation *must* annotate local timestamps with legacy annotations too,
as shown below.

*Backward compatibility:*

| ConvertedType | LogicalType |
|---------------|-------------|
| TIMESTAMP_MILLIS | TimestampType (isAdjustedToUTC = true, unit = MILLIS) |
| TIMESTAMP_MICROS | TimestampType (isAdjustedToUTC = true, unit = MICROS) |

*Forward compatibility:*

<table>
    <tr colspan="3">
        <th colspan="3">LogicalType</th>
        <th>ConvertedType</th>
    </tr>
    <tr>
        <td rowspan="6">TimestampType</td>
        <td rowspan="3">isAdjustedToUTC = true</td>
        <td>unit = MILLIS</td>
        <td>TIMESTAMP_MILLIS</td>
    </tr>
    <tr>
        <td>unit = MICROS</td>
        <td>TIMESTAMP_MICROS</td>
    </tr>
    <tr>
        <td>unit = NANOS</td>
        <td>-</td>
    </tr>
    <tr>
        <td rowspan="3">isAdjustedToUTC = false</td>
        <td>unit = MILLIS</td>
        <td>TIMESTAMP_MILLIS</td>
    </tr>
    <tr>
        <td>unit = MICROS</td>
        <td>TIMESTAMP_MICROS</td>
    </tr>
    <tr>
        <td>unit = NANOS</td>
        <td>-</td>
    </tr>
</table>

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

The sort order used for `INTERVAL` is undefined. When writing data, no min/max
statistics should be saved for this type and if such non-compliant statistics
are found during reading, they must be ignored.

## Embedded Types

Embedded types do not have type-specific orderings.

### JSON

`JSON` is used for an embedded JSON document. It must annotate a `binary`
primitive type. The `binary` data is interpreted as a UTF-8 encoded character
string of valid JSON as defined by the [JSON specification][json-spec]

[json-spec]: http://json.org/

The sort order used for `JSON` is unsigned byte-wise comparison.

### BSON

`BSON` is used for an embedded BSON document. It must annotate a `binary`
primitive type. The `binary` data is interpreted as an encoded BSON document as
defined by the [BSON specification][bson-spec].

[bson-spec]: http://bsonspec.org/spec.html

The sort order used for `BSON` is unsigned byte-wise comparison.

## Nested Types

This section specifies how `LIST` and `MAP` can be used to encode nested types
by adding group levels around repeated fields that are not present in the data.

This does not affect repeated fields that are not annotated: A repeated field
that is neither contained by a `LIST`- or `MAP`-annotated group nor annotated
by `LIST` or `MAP` should be interpreted as a required list of required
elements where the element type is the type of the field.

Implementations should use either `LIST` and `MAP` annotations _or_ unannotated
repeated fields, but not both. When using the annotations, no unannotated
repeated types are allowed.

### Lists

`LIST` is used to annotate types that should be interpreted as lists.

`LIST` must always annotate a 3-level structure:

```
<list-repetition> group <name> (LIST) {
  repeated group list {
    <element-repetition> <element-type> element;
  }
}
```

* The outer-most level must be a group annotated with `LIST` that contains a
  single field named `list`. The repetition of this level must be either
  `optional` or `required` and determines whether the list is nullable.
* The middle level, named `list`, must be a repeated group with a single
  field named `element`.
* The `element` field encodes the list's element type and repetition. Element
  repetition must be `required` or `optional`.

The following examples demonstrate two of the possible lists of string values.

```
// List<String> (list non-null, elements nullable)
required group my_list (LIST) {
  repeated group list {
    optional binary element (UTF8);
  }
}

// List<String> (list nullable, elements non-null)
optional group my_list (LIST) {
  repeated group list {
    required binary element (UTF8);
  }
}
```

Element types can be nested structures. For example, a list of lists:

```
// List<List<Integer>>
optional group array_of_arrays (LIST) {
  repeated group list {
    required group element (LIST) {
      repeated group list {
        required int32 element;
      }
    }
  }
}
```

#### Backward-compatibility rules

It is required that the repeated group of elements is named `list` and that
its element field is named `element`. However, these names may not be used in
existing data and should not be enforced as errors when reading. For example,
the following field schema should produce a nullable list of non-null strings,
even though the repeated group is named `element`.

```
optional group my_list (LIST) {
  repeated group element {
    required binary str (UTF8);
  };
}
```

Some existing data does not include the inner element layer. For
backward-compatibility, the type of elements in `LIST`-annotated structures
should always be determined by the following rules:

1. If the repeated field is not a group, then its type is the element type and
   elements are required.
2. If the repeated field is a group with multiple fields, then its type is the
   element type and elements are required.
3. If the repeated field is a group with one field and is named either `array`
   or uses the `LIST`-annotated group's name with `_tuple` appended then the
   repeated type is the element type and elements are required.
4. Otherwise, the repeated field's type is the element type with the repeated
   field's repetition.

Examples that can be interpreted using these rules:

```
// List<Integer> (nullable list, non-null elements)
optional group my_list (LIST) {
  repeated int32 element;
}

// List<Tuple<String, Integer>> (nullable list, non-null elements)
optional group my_list (LIST) {
  repeated group element {
    required binary str (UTF8);
    required int32 num;
  };
}

// List<OneTuple<String>> (nullable list, non-null elements)
optional group my_list (LIST) {
  repeated group array {
    required binary str (UTF8);
  };
}

// List<OneTuple<String>> (nullable list, non-null elements)
optional group my_list (LIST) {
  repeated group my_list_tuple {
    required binary str (UTF8);
  };
}
```

### Maps

`MAP` is used to annotate types that should be interpreted as a map from keys
to values. `MAP` must annotate a 3-level structure:

```
<map-repetition> group <name> (MAP) {
  repeated group key_value {
    required <key-type> key;
    <value-repetition> <value-type> value;
  }
}
```

* The outer-most level must be a group annotated with `MAP` that contains a
  single field named `key_value`. The repetition of this level must be either
  `optional` or `required` and determines whether the list is nullable.
* The middle level, named `key_value`, must be a repeated group with a `key`
  field for map keys and, optionally, a `value` field for map values.
* The `key` field encodes the map's key type. This field must have
  repetition `required` and must always be present.
* The `value` field encodes the map's value type and repetition. This field can
  be `required`, `optional`, or omitted.

The following example demonstrates the type for a non-null map from strings to
nullable integers:

```
// Map<String, Integer>
required group my_map (MAP) {
  repeated group key_value {
    required binary key (UTF8);
    optional int32 value;
  }
}
```

If there are multiple key-value pairs for the same key, then the final value
for that key must be the last value. Other values may be ignored or may be
added with replacement to the map container in the order that they are encoded.
The `MAP` annotation should not be used to encode multi-maps using duplicate
keys.

#### Backward-compatibility rules

It is required that the repeated group of key-value pairs is named `key_value`
and that its fields are named `key` and `value`. However, these names may not
be used in existing data and should not be enforced as errors when reading.

Some existing data incorrectly used `MAP_KEY_VALUE` in place of `MAP`. For
backward-compatibility, a group annotated with `MAP_KEY_VALUE` that is not
contained by a `MAP`-annotated group should be handled as a `MAP`-annotated
group.

Examples that can be interpreted using these rules:

```
// Map<String, Integer> (nullable map, non-null values)
optional group my_map (MAP) {
  repeated group map {
    required binary str (UTF8);
    required int32 num;
  }
}

// Map<String, Integer> (nullable map, nullable values)
optional group my_map (MAP_KEY_VALUE) {
  repeated group map {
    required binary key (UTF8);
    optional int32 value;
  }
}
```

## UNKNOWN (always null)

Sometimes, when discovering the schema of existing data, values are always null
and there's no type information.
The `UNKNOWN` type can be used to annotate a column that is always null.
(Similar to Null type in Avro and Arrow)
