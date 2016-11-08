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
* `int64`: for 1 &lt;= precision &lt;= 18; precision &lt; 10 will produce a
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

### TIME\_MILLIS

`TIME_MILLIS` is used for a logical time type with millisecond precision,
without a date. It must annotate an `int32` that stores the number of
milliseconds after midnight.

### TIME\_MICROS

`TIME_MICROS` is used for a logical time type with microsecond precision,
without a date. It must annotate an `int64` that stores the number of
microseconds after midnight.

### TIMESTAMP\_MILLIS

`TIMESTAMP_MILLIS` is used for a combined logical date and time type, with
millisecond precision. It must annotate an `int64` that stores the number of
milliseconds from the Unix epoch, 00:00:00.000 on 1 January 1970, UTC.

### TIMESTAMP\_MICROS

`TIMESTAMP_MICROS` is used for a combined logical date and time type with
microsecond precision. It must annotate an `int64` that stores the number of
microseconds from the Unix epoch, 00:00:00.000000 on 1 January 1970, UTC.

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

### Unions

A Union type annotates data stored as a Group.
It describes the different possible types under the same field name.
The group contains one optional field for each possible type in the Union.
The names of the fields in the annotated Group are not important, but as a convention the type names are used.

#### Nullability
 - If the union is not nullable then exactly one field is non-null and the field containing the union is required.
```
// Union<String, Integer, Boolean> (where the value of the union is not null)
// (exactly one of either String, Integer or Boolean is non-null)
required group my_union (UNION) {
  optional binary string (UTF8);
  optional int32 integer;
  optional boolean bool;
}
```
A projection might return an empty union if the non-null field is projected out. However we know that the Union is non-null,
it just contains a value that was not read from disk.

 - If the union is nullable then at most one field is non-null and the field containing the union is optional
```
// Union<String, Integer, Boolean> (where the value of the union may be null)
// at most one of either String, Integer or Boolean is non-null
// if they are all null then the field my_union itself must be null
optional  group my_union (UNION) {
  optional binary string (UTF8);
  optional int32 integer;
  optional boolean bool;
}
```
The definition level of the UNION group is used to differentiate a null value (the union was null to start with) from a projection that excludes the non-null field.
If the Union group is null then the value was null.
If the Union group is non-null, but all of the options within it are null, then the value was non-null but was an option that was not projected.

 - If - despite the spec - a group instance contains more than one non-null field the behavior is undefined and may change depending on the projection applied.

#### Projecting Unions
The following points are to be noted when projecting columns out of unions:
- At least one column from one of the branches must be included in the projection to know when the union is null or not.
- When projecting out some branches of the union, the type of the union is "unknown" for those at read time. Each object model integration (avro, thrift, ...) has its own rules to expose this.
- At least one column from each branch must be included in the projection to always know the type.
- The mechanism to filter records with "unknown" type (meaning these columns have been excluded from the projection) is defined by the model as well.
Find details about Thrift and Avro in their respective directory.

#### Mapping to Avro Unions
- an Avro Union that contains Null and at least two other types will map to an optional Parquet Union (of the remaining types).
- an Avro Union that does not contain null will map to a required Parquet Union.

## Null
Sometimes when discovering the schema of existing data values are always null and there's no type information.
The `NULL` type can be used to annotates a column that is always null.
(Similar to Null type in Avro)

