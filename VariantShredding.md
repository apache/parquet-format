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

# Variant Shredding

> [!IMPORTANT]
> **This specification is still under active development, and has not been formally adopted.**

The Variant type is designed to store and process semi-structured data efficiently, even with heterogeneous values.
Query engines encode each Variant value in a self-describing format, and store it as a group containing required `value` and `metadata` binary fields in Parquet.
Since data is often partially homogenous, it can be beneficial to extract certain fields into separate Parquet columns to further improve performance.
We refer to this process as **shredding**.
Each Parquet file remains fully self-describing, with no additional metadata required to read or fully reconstruct the Variant data from the file.
Combining shredding with a binary residual provides the flexibility to represent complex, evolving data with an unbounded number of unique fields while limiting the size of file schemas, and retaining the performance benefits of a columnar format.

This document focuses on the shredding semantics, Parquet representation, implications for readers and writers, as well as the Variant reconstruction.
For now, it does not discuss which fields to shred, user-facing API changes, or any engine-specific considerations like how to use shredded columns.
The approach builds upon the [Variant Binary Encoding](VariantEncoding.md), and leverages the existing Parquet specification.

Shredding allows a query engine to reap the full benefits of Parquet's columnar representation, such as more compact data encoding, min/max statistics for data skipping, and I/O and CPU savings from pruning unnecessary fields not accessed by a query (including the non-shredded Variant binary data).
Without shredding, any query that accesses a Variant column must fetch all bytes of the full binary buffer.
With shredding, readers can get nearly equivalent performance as in a relational (scalar) data model.

For example, `SELECT variant_get(variant_event, '$.event_ts', 'timestamp') FROM tbl` only needs to access `event_ts`, and the file scan could avoid fetching the rest of the Variant value if this field was shredded into a separate column in the Parquet schema.
Similarly, for the query `SELECT * FROM tbl WHERE variant_get(variant_event, '$.event_type', 'string') = 'signup'`, the scan could first decode the shredded `event_type` column, and only fetch/decode the full Variant event value for rows that pass the filter.

## Variant Metadata

Variant metadata is stored in the top-level Variant group in a binary `metadata` column regardless of whether the Variant value is shredded.
All `value` columns within the Variant must use the same `metadata`.

All fields for a variant, whether shredded or not, must be present in the metadata.

## Value Shredding

Variant values are stored in Parquet fields named `value`.
Each `value` field may have an associated shredded field named `typed_value` that stores the value when it matches a specific type.

For example, a Variant field, `measurement` may be shredded as long values by adding `typed_value` with type `int64`:
```
optional group measurement (VARIANT) {
  required binary metadata;
  optional binary value;
  optional int64 typed_value;
}
```

Both `value` and `typed_value` are optional fields used together to encode a single value.
Values in the two fields must be interpreted according to the following table:

| `value` | `typed_value` | Meaning |
| null            | null          | The value is missing |
| non-null        | null          | The value is present and may be any type, including null |
| null            | non-null      | The value is present and the shredded type |
| non-null        | non-null      | The value is present and a partially shredded object |

An object is _partially shredded_ when the `value` is an object and the `typed_value` is a shredded object.

If both fields are non-null and either is not an object, the value is invalid. Readers must either fail or return the `value`.

### Shredded Value Types

Shredded values must use the following Parquet types:

| Variant Type                | Equivalent Parquet Type      |
|-----------------------------|------------------------------|
| boolean                     | BOOLEAN                      |
| int8                        | INT(8, signed=true)          |
| int16                       | INT(16, signed=true)         |
| int32                       | INT32 / INT(32, signed=true) |
| int64                       | INT64 / INT(64, signed=true) |
| float                       | FLOAT                        |
| double                      | DOUBLE                       |
| decimal4                    | DECIMAL(precision, scale)    |
| decimal8                    | DECIMAL(precision, scale)    |
| decimal16                   | DECIMAL(precision, scale)    |
| date                        | DATE                         |
| timestamp                   | TIMESTAMP(true, MICROS)      |
| timestamp without time zone | TIMESTAMP(false, MICROS)     |
| binary                      | BINARY                       |
| string                      | STRING                       |
| array                       | LIST; see Arrays below       |
| object                      | GROUP; see Objects below     |

#### Primitive Types

Primitive values can be shredded using the equivalent Parquet primitive type from the table above for `typed_object`.

Unless the value is shredded in an object field, `typed_value` or `value` (but not both) must be non-null.

#### Arrays

Arrays can be shredded using a 3-level Parquet list for `typed_value`.

If the value is not an array, `typed_value` must be null.
If the value is an array, `value` must be null.

The list `element` must be a required group that contains a `variant_type` (`binary`) and may contain a shredded `typed_value` field.

For example, a `tags` Variant may be shredded as a list of strings using the following definition:
```
optional group tags (VARIANT) {
  required binary metadata;
  optional binary value;
  optional group typed_value (LIST) {   # must be optional to allow a null list
    repeated group list {
      required group element {          # shredded element
        optional binary value;
        optional binary typed_value (STRING);
      }
    }
  }
}
```

All elements of an array must be non-null, since `array` elements cannote be missing.
Either `typed_value` or `value` (but not both) must be non-null.

#### Objects

Fields of an object can be shredded using a Parquet group for `typed_value` that contains shredded fields.

If the value is not an object, `typed_value` must be null.

If the value is a partially shredded object, the `value` must not contain the shredded fields.
If shredded fields are present in the variant object, it is invalid and readers must either fail or use the values from the `value`.

Each shredded field in the `typed_value` group is represented as a required group that contains optional `value` and `typed_value` fields.
This layout enables readers to skip data based on the field statistics for `value` and `typed_value`.

For example, a Variant `event` field may shred `event_type` (`string`) and `event_ts` (`timestamp`) columns using the following definition:
```
optional group event (VARIANT) {
  required binary metadata;
  optional binary value;                # a variant, expected to be an object
  optional group typed_value {          # shredded fields for the variant object
    required group event_type {         # shredded field for event_type
      optional binary value;
      optional binary typed_value (STRING);
    }
    required group event_ts {           # shredded field for event_ts
      optional binary value;
      optional int64 typed_value (TIMESTAMP(true, MICROS));
    }
  }
}
```

The group for each named field must be required.

A field's `value` and `typed_value` are set to null (missing) to indicate that the field does not exist in the variant.

Statistics for the `typed_value` column can be used for row group or page skipping when `value` is always null.

## Nesting

```
optional group event (VARIANT) {
  required binary metadata;
  optional binary value;
  optional group typed_value {
    required group event_type {
      optional binary value;
      optional binary typed_value (STRING);
    }
    required group event_ts {
      optional binary value;
      optional int64 typed_value (TIMESTAMP(true, MICROS));
    }
    required group location {
      optional binary value;
      optional group typed_value {
        required group latitude {
          optional binary value;
          optional double typed_value;
        }
        required group longitude {
          optional binary value;
          optional double typed_value;
        }
      }
    }
    required group tags {
      optional binary value;
      optional group typed_value (LIST) {
        repeated group list {
          required group element {
            optional binary value;
            optional binary typed_value (STRING);
          }
        }
      }
    }
  }
}
```


| Variant Value | Top-level value | b.variant_value | a.typed_value | a.variant_value | b.object.c.typed_value | b.object.c.variant_value | Notes | 
|---------------|-------------------------|-----------------|---------------|-----------------|------------------------|--------------------------|-------|
| {a: 123, b: {c: "hello"}} | null | null | 123 | null | hello | null | All values shredded |
| {a: 1.23, b: {c: "123"}} | null | null | null | 1.23 | 123 | null | a is not an integer |
| {a: 123, b: {c: null}} | null | null | null | 123 | null | null | b.object.c set to non-null to indicate VariantNull |
| {a: 123, b: {}} | null | null | null | 123 | null | null | b.object.c set to null, to indicate that c is missing |
| {a: 123, d: 456} | {d: 456} | null | 123 | null | null | null | Extra field d is stored as value |
| [{a: 1, b: {c: 2}}, {a: 3, b: {c: 4}}] | [{a: 1, b: {c: 2}}, {a: 3, b: {c: 4}}] | null | null | null | null | null | Not an object |

## Data Skipping

Shredded columns are expected to store statistics in the same format as a normal Parquet column.
In general, the engine can only skip a row group or page if all rows in the `value` field are null, since it is possible for a `variant_get` expression to successfully cast a value from the `variant_value` to the target type.
For example, if `typed_value` is of type `int64`, then the string "123" might be contained in `value`, which would not be reflected in statistics, but could be retained by a filter like `where variant_get(col, "$.field", "long") = 123`.
If `value` is all-null, then the engine can prune pages or row groups based on `typed_value`.
This specification is not strict about what values may be stored in `value` rather than `typed_value`, so it is not safe to skip rows based on `typed_value` unless the corresponding `variant_value` column is all-null, or the engine has specific knowledge of the behavior of the writer that produced the shredded data.

## Reconstructing a Variant

It is possible to recover a full Variant value using a recursive algorithm, where the initial call is to `ConstructVariant` with the top-level fields, which are assumed to be null if they are not present in the schema.

```
# Constructs a Variant from `value`, `object`, `array` and `typed_value`.
# Only one of object, array and typed_value may be non-null.
def ConstructVariant(value, object, array, typed_value):
  if object is null and array is null and typed_value is null and value is null: return VariantNull 
  if object is not null:
    return ConstructObject(value, object)
  elif array is not null:
    return ConstructArray(array)
  elif typed_value is not null:
    return cast(typed_value as Variant)
  else:
    value

# Construct an object from an `object` group, and a (possibly null) Variant value
def ConstructObject(value, object):
  # If value is present and is not an Object, then the result is ambiguous.
  assert(value is null or is_object(variant_value))
  # Null fields in the object are missing from the reconstructed Variant.
  nonnull_object_fields = object.fields.filter(field -> field is not null)
  all_keys = Union(value.keys, non_null_object_fields)
  return VariantObject(all_keys.map { key ->
    if key in object: (key, ConstructVariant(object[key].value, object[key].object, object[key].array, object[key].typed_value))
    else: (key, value[key])
  })

def ConstructArray(array):
  newVariantArray = VariantArray()
  for i in range(array.size):
    newVariantArray.append(ConstructVariant(array[i].value, array[i].object, array[i].array, array[i].typed_value)
```

## Nested Parquet Example

This section describes a more deeply nested example, using a top-level array as the shredding type.

Below is a sample of JSON that would be fully shredded in this example.
It contains an array of objects, containing an `a` field shredded as an array, and a `b` field shredded as an integer.

```
[
  {
    "a": [1, 2, 3],
    "b": 100
  },
  {
    "a": [4, 5, 6],
    "b": 200
  }
]
```


The corresponding Parquet schema with "a" and "b" as leaf types is:

```
optional group variant_col {
 required binary metadata;
 optional binary value;
 optional group array (LIST) {
  repeated group list {
   optional group element {
    optional binary value;
    optional group object {
     optional group a {
      optional binary value;
      optional group array (LIST) {
       repeated group list {
        optional group element {
         optional int64 typed_value;
         optional binary value;
        }
       }
      }
     }
     optional group b {
      optional int64 typed_value;
      optional binary value;
     }
    }
   }
  }
 }
}
```

In the above example schema, if "a" is an array containing a mix of integer and non-integer values, the engine will shred individual elements appropriately into either `typed_value` or `value`.
If the top-level Variant is not an array (for example, an object), the engine cannot shred the value and it will store it in the top-level `value`.
Similarly, if "a" is not an array, it will be stored in the `value` under "a".

Consider the following example:

```
[
  {
    "a": [1, 2, 3],
    "b": 100,
    "c": "unexpected"
  },
  {
    "a": [4, 5, 6],
    "b": 200
  },
  "not an object"
]
```

The second array element can be fully shredded, but the first and third cannot be. The contents of `variant_col.array[*].value` would be as follows:

```
[
  { "c": "unexpected" },
  NULL,
  "not an object"
]
```

## Backward and forward compatibility

Shredding is an optional feature of Variant, and readers must continue to be able to read a group containing only a `value` and `metadata` field.

Any fields in the same group as `typed_value`/`value` that start with `_` (underscore) can be ignored.
This is intended to allow future backwards-compatible extensions.
In particular, the field names `_metadata_key_paths` and any name starting with `_spark` are reserved, and should not be used by other implementations.
Any extra field names that do not start with an underscore should be assumed to be backwards incompatible, and readers should fail when reading such a schema.

Engines without shredding support are not expected to be able to read Parquet files that use shredding.
Since different files may contain conflicting schemas (e.g. a `typed_value` column with incompatible types in two files), it may not be possible to infer or specify a single schema that would allow all Parquet files for a table to be read.
