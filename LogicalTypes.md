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
`ConvertedType` is an enum of all available annotation. Since Thrift enums can't have additional type parameters,
it is cumbersome to define additional type parameters, like decimal scale and precision
(which are additional 32 bit integer fields on SchemaElement, and are relevant only for decimals) or time unit
and UTC adjustment flag for Timestamp types. To overcome this problem, a new logical type representation was introduced into
the metadata to replace `ConvertedType`: `LogicalType`.  The new representation is a union of struct of logical types,
this way allowing more flexible API, logical types can have type parameters.

However, to maintain compatibility, Parquet readers should be able to read
and interpret old logical type representation (in case the new one is not present,
because the file was written by older writer), and write `ConvertedType` field for old readers.

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
The annotation has two parameter: bit width and sign.
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
The annotation has two parameter: bit width and sign.
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
`INT(64, true)` must annotate an `int64` primitive type.

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
than the precision. Precision is required and must be a non-zero positive
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

## Date/Time Types

### DATE

`DATE` is used to for a logical date type, without a time of day. It must
annotate an `int32` that stores the number of days from the Unix epoch, 1
January 1970.

The sort order used for `DATE` is signed.

### TIME

`TIME` is used for a logical time type without a date with millisecond or microsecond precision.
The type has two type parameters: UTC adjustment (`true` or `false`)
and precision (`MILLIS` or `MICROS`).

`TIME` with precision `MILLIS` is used for millisecond precision.
It must annotate an `int32` that stores the number of
milliseconds after midnight.

`TIME` with precision `MICROS` is used for microsecond precision.
It must annotate an `int64` that stores the number of
microseconds after midnight.

The sort order used for `TIME` is signed.

#### Deprecated time ConvertedType

`TIME_MILLIS` is the deprecated ConvertedType counterpart of `TIME` logical type
with precision `MILLIS`. Like the logical type counterpart, it must annotate an `int32`

`TIME_MICROS` is the deprecated ConvertedType counterpart of `TIME` logical type
with precision `MICROS`. Like the logical type counterpart, it must annotate an `int64`

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
        <td rowspan="2" colspan="2">TimeType</td>
        <td>unit = MILLIS</td>
        <td>TIME_MILLIS</td>
    </tr>
    <tr>
        <td>unit = MICROS</td>
        <td>TIME_MICROS</td>
    </tr>
</table>

### TIMESTAMP

`TIMESTAMP` is used for a combined logical date and time type, with
millisecond or microsecond precision. The type has two type parameters:
UTC adjustment (`true` or `false`) and precision (`MILLIS` or `MICROS`).

`TIMESTAMP` with precision `MILLIS` is used for millisecond precision.
It must annotate an `int64` that stores the number of
milliseconds from the Unix epoch, 00:00:00.000 on 1 January 1970, UTC.

`TIMESTAMP` with precision `MICROS` is used for microsecond precision.
It must annotate an `int64` that stores the number of
microseconds from the Unix epoch, 00:00:00.000000 on 1 January 1970, UTC.

The sort order used for `TIMESTAMP` is signed.

#### Deprecated timestamp ConvertedType

`TIMESTAMP_MILLIS` is the deprecated ConvertedType counterpart of `TIMESTAMP` logical type
with precision `MILLIS`. Like the logical type counterpart, it must annotate an `int64`

`TIMESTAMP_MICROS` is the deprecated ConvertedType counterpart of `TIMESTAMP` logical type
with precision `MICROS`. Like the logical type counterpart, it must annotate an `int64`

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
        <td rowspan="2" colspan="2">TimestampType</td>
        <td>unit = MILLIS</td>
        <td>TIMESTAMP_MILLIS</td>
    </tr>
    <tr>
        <td>unit = MICROS</td>
        <td>TIMESTAMP_MICROS</td>
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

## Null
Sometimes when discovering the schema of existing data values are always null and there's no type information.
The `NULL` type can be used to annotates a column that is always null.
(Similar to Null type in Avro)
