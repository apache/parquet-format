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
Query engines encode each Variant value in a self-describing format, and store it as a group containing `value` and `metadata` binary fields in Parquet.
Since data is often partially homogenous, it can be beneficial to extract certain fields into separate Parquet columns to further improve performance.
We refer to this process as **shredding**.
Each Parquet file remains fully self-describing, with no additional metadata required to read or fully reconstruct the Variant data from the file.
Combining shredding with a binary residual provides the flexibility to represent complex, evolving data with an unbounded number of unique fields while limiting the size of file schemas, and retaining the performance benefits of a columnar format.

This document focuses on the shredding semantics, Parquet representation, implications for readers and writers, as well as the Variant reconstruction.
For now, it does not discuss which fields to shred, user-facing API changes, or any engine-specific considerations like how to use shredded columns.
The approach builds upon the [Variant Binary Encoding](VariantEncoding.md), and leverages the existing Parquet specification.

At a high level, we replace the `value` field of the Variant Parquet group with one or more fields called `object`, `array`, `typed_value`, and `variant_value`.
These represent a fixed schema suitable for constructing the full Variant value for each row.

Shredding allows a query engine to reap the full benefits of Parquet's columnar representation, such as more compact data encoding, min/max statistics for data skipping, and I/O and CPU savings from pruning unnecessary fields not accessed by a query (including the non-shredded Variant binary data).
Without shredding, any query that accesses a Variant column must fetch all bytes of the full binary buffer.
With shredding, we can get nearly equivalent performance as in a relational (scalar) data model.

For example, `select variant_get(variant_col, ‘$.field1.inner_field2’, ‘string’) from tbl` only needs to access `inner_field2`, and the file scan could avoid fetching the rest of the Variant value if this field was shredded into a separate column in the Parquet schema.
Similarly, for the query `select * from tbl where variant_get(variant_col, ‘$.id’, ‘integer’) = 123`, the scan could first decode the shredded `id` column, and only fetch/decode the full Variant value for rows that pass the filter.

# Parquet Example

Consider the following Parquet schema together with how Variant values might be mapped to it.
Notice that we represent each shredded field in `object` as a group of two fields, `typed_value` and `variant_value`.
We extract all homogenous data items of a certain path into `typed_value`, and set aside incompatible data items in `variant_value`.
Intuitively, incompatibilities within the same path may occur because we store the shredding schema per Parquet file, and each file can contain several row groups.
Selecting a type for each field that is acceptable for all rows would be impractical because it would require buffering the contents of an entire file before writing.

Typically, the expectation is that `variant_value` exists at every level as an option, along with one of `object`, `array` or `typed_value`.
If the actual Variant value contains a type that does not match the provided schema, it is stored in `variant_value`.
An `variant_value` may also be populated if an object can be partially represented: any fields that are present in the schema must be written to those fields, and any missing fields are written to `variant_value`.

The `metadata` column is unchanged from its unshredded representation, and may be referenced in `variant_value` fields in the shredded data.

```
optional group variant_col {
 required binary metadata;
 optional binary variant_value;
 optional group object {
  optional group a {
   optional binary variant_value;
   optional int64 typed_value;
  }
  optional group b {
   optional binary variant_value;
   optional group object {
    optional group c {
      optional binary variant_value;
      optional binary typed_value (STRING);
    }
   }
  }
 }
}
```

| Variant Value | Top-level variant_value | b.variant_value | a.typed_value | a.variant_value | b.object.c.typed_value | b.object.c.variant_value | Notes | 
|---------------|-------------------------|-----------------|---------------|-----------------|------------------------|--------------------------|-------|
| {a: 123, b: {c: “hello”}} | null | null | 123 | null | hello | null | All values shredded |
| {a: 1.23, b: {c: “123”}} | null | null | null | 1.23 | 123 | null | a is not an integer |
| {a: 123, b: {c: null}} | null | null | 123 | null | null | null | b.object.c set to non-null to indicate VariantNull |
| {a: 123, b: {}} | null | null | 123 | null | null | null | b.object.c set to null, to indicate that c is missing |
| {a: 123, d: 456} | {d: 456} | null | 123 | null | null | null | Extra field d is stored as variant_value |
| [{a: 1, b: {c: 2}}, {a: 3, b: {c: 4}}] | [{a: 1, b: {c: 2}}, {a: 3, b: {c: 4}}] | null | null | null | null | null | Not an object |

# Parquet Layout

The `array` and `object` fields represent Variant array and object types, respectively.
Arrays must use the three-level list structure described in [LogicalTypes.md](LogicalTypes.md).

An `object` field must be a group.
Each field name of this inner group corresponds to the Variant value's object field name.
Each inner field's type is a recursively shredded variant value: that is, the fields of each object field must be one or more of `object`, `array`, `typed_value` or `variant_value`.

Similarly the elements of an `array` must be a group containing one or more of `object`, `array`, `typed_value` or `variant_value`.

Each leaf in the schema can store an arbitrary Variant value.
It contains an `variant_value` binary field and a `typed_value` field.
If non-null, `variant_value` represents the value stored as a Variant binary.
The `typed_value` field may be any type that has a corresponding Variant type.
For each value in the data, at most one of the `typed_value` and `variant_value` may be non-null.
A writer may omit either field, which is equivalent to all rows being null.

Dictionary IDs in a `variant_value` field refer to entries in the top-level `metadata` field.

For an `object`, a null field means that the field does not exist in the reconstructed Variant object.
All elements of an `array` must be non-null, since array elements cannote be missing.

| typed_value | variant_value | Meaning |
|-------------|----------------|---------|
| null | null | Field is Variant Null (not missing) in the reconstructed Variant. |
| null | non-null | Field may be any type in the reconstructed Variant. |
| non-null | null | Field has this column’s type in the reconstructed Variant. |
| non-null | non-null | Invalid |

The `typed_value` may be absent from the Parquet schema for any field, which is equivalent to its value being always null (in which case the shredded field is always stored as a Variant binary).
By the same token, `variant_value` may be absent, which is equivalent to their value being always null (in which case the field will always have the value Null or have the type of the `typed_value` column).

# Unshredded values

If all values can be represented at a given level by whichever of `object`, `array`, or `typed_value` is present, `variant_value` is set to null.

If a value cannot be represented by whichever of `object`, `array`, or `typed_value` is present in the schema, then it is stored in `variant_value`, and the other fields are set to null.
In the Parquet example above, if field `a` was an object or array, or a non-integer scalar, it would be stored in `variant_value`.

If a value is an object, and the `object` field is present but does not contain all of the fields in the value, then any remaining fields are stored in an object in `variant_value`.
In the Parquet example above, if field `b` was an object of the form `{"c": 1, "d": 2}"`, then the object `{"d": 2}` would be stored in `variant_value`, and the `c` field would be shredded recursively under `object.c`.

Note that an array is always fully shredded if there is an `array` field, so the above consideration for `object` is not relevant for arrays: only one of `array` or `variant_value` may be non-null at a given level.

# Using variant_value vs. typed_value

In general, it is desirable to store values in the `typed_value` field rather than the `variant_value` whenever possible.
This will typically improve encoding efficiency, and allow the use of Parquet statistics to filter at the row group or page level.
In the best case, the `variant_value` fields are all null and the engine does not need to read them (or it can omit them from the schema on write entirely).
There are two main motivations for including the `variant_value` column:

1) In a case where there are rare type mismatches (for example, a numeric field with rare strings like “n/a”), we allow the field to be shredded, which could still be a significant performance benefit compared to fetching and decoding the full value/metadata binary.
2) Since there is a single schema per file, there would be no easy way to recover from a type mismatch encountered late in a file write. Parquet files can be large, and buffering all file data before starting to write could be expensive. Including a variant column for every field guarantees we can adhere to the requested shredding schema.

# Top-level metadata

Any values stored in a shredded `variant_value` field may have dictionary IDs referring to the metadata.
There is one metadata value for the entire Variant record, and that is stored in the top-level `metadata` field.
This means any `variant_value` values in the shredded representation is only the "value" portion of the [Variant Binary Encoding](VariantEncoding.md).

The metadata is kept at the top-level, instead of shredding the metadata with the shredded variant values because:
* Simplified shredding scheme and specification. No need for additional struct-of-binary values, or custom concatenated binary scheme for `variant_value`.
* Simplified and good performance for write shredding. No need to rebuild the metadata, or re-encode IDs for `variant_value`.
* Simplified and good performance for Variant reconstruction. No need to re-encode IDs for `variant_value`.

# Data Skipping

Shredded columns are expected to store statistics in the same format as a normal Parquet column.
In general, the engine can only skip a row group or page if all rows in the `variant_value` field are null, since it is possible for a `variant_get` expression to successfully cast a value from the `variant_value` to the target type.
For example, if `typed_value` is of type `int64`, then the string “123” might be contained in `variant_value`, which would not be reflected in statistics, but could be retained by a filter like `where variant_get(col, “$.field”, “long”) = 123`.
If `variant_value` is all-null, then the engine can prune pages or row groups based on `typed_value`.
This specification is not strict about what values may be stored in `variant_value` rather than `typed_value`, so it is not safe to skip rows based on `typed_value` unless the corresponding `variant_value` column is all-null, or the engine has specific knowledge of the behavior of the writer that produced the shredded data.

# Shredding Semantics

Reconstruction of Variant value from a shredded representation is not expected to produce a bit-for-bit identical binary to the original unshredded value.
For example, in a reconstructed Variant value, the order of object field values may be different from the original binary.
This is allowed since the [Variant Binary Encoding](VariantEncoding.md#object-field-id-order-and-uniqueness) does not require an ordering of the field values, but the field IDs will still be ordered lexicographically according to the corresponding field names.

The physical representation of scalar values may also be different in the reconstructed Variant binary.
In particular, the [Variant Binary Encoding](VariantEncoding.md) considers all integer and decimal representations to represent a single logical type.
This flexibility enables shredding to be applicable in more scenarios, while maintaining all information and values losslessly.
As a result, it is valid to shred a decimal into a decimal column with a different scale, or to shred an integer as a decimal, as long as no numeric precision is lost.
For example, it would be valid to write the value 123 to a Decimal(9, 2) column, but the value 1.234 would need to be written to the `variant_value` column.
When reconstructing, it would be valid for a reader to reconstruct 123 as an integer, or as a Decimal(9, 2).
Engines should not depend on the physical type of a Variant value, only the logical type.

On the other hand, shredding as a different logical type is not allowed.
For example, the integer value 123 could not be shredded to a string `typed_value` column as the string "123", since that would lose type information.
It would need to be written to the `variant_value` column.

# Reconstructing a Variant

It is possible to recover a full Variant value using a recursive algorithm, where the initial call is to `ConstructVariant` with the top-level fields, which are assumed to be null if they are not present in the schema.

```
# Constructs a Variant from `variant_value`, `object`, `array` and `typed_value`.
# Only one of object, array and typed_value may be non-null.
def ConstructVariant(variant_value, object, array, typed_value):
  if object is null and array is null and typed_value is null and variant_value is null: return VariantNull 
  if object is not null:
    return ConstructObject(variant_value, object)
  elif array is not null:
    return ConstructArray(array)
  elif typed_value is not null:
    return cast(typed_value as Variant)
  else:
    variant_value

# Construct an object from an `object` group, and a (possibly null) Variant variant_value
def ConstructObject(variant_value, object):
  # If variant_value is present and is not an Object, then the result is ambiguous.
  assert(variant_value is null or is_object(variant_value))
  # Null fields in the object are missing from the reconstructed Variant.
  nonnull_object_fields = object.fields.filter(field -> field is not null)
  all_keys = Union(variant_value.keys, non_null_object_fields)
  return VariantObject(all_keys.map { key ->
    if key in object: (key, ConstructVariant(object[key].variant_value, object[key].object, object[key].array, object[key].typed_value))
    else: (key, variant_value[key])
  })

def ConstructArray(array):
  newVariantArray = VariantArray()
  for i in range(array.size):
    newVariantArray.append(ConstructVariant(array[i].variant_value, array[i].object, array[i].array, array[i].typed_value)
```

# Nested Parquet Example

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


The corresponding Parquet schema with “a” and “b” as leaf types is:

```
optional group variant_col {
 required binary metadata;
 optional binary variant_value;
 optional group array (LIST) {
  repeated group list {
   optional group element {
    optional binary variant_value;
    optional group object {
     optional group a {
      optional binary variant_value;
      optional group array (LIST) {
       repeated group list {
        optional group element {
         optional int64 typed_value;
         optional binary variant_value;
        }
       }
      }
     }
     optional group b {
      optional int64 typed_value;
      optional binary variant_value;
     }
    }
   }
  }
 }
}
```

In the above example schema, if “a” is an array containing a mix of integer and non-integer values, the engine will shred individual elements appropriately into either `typed_value` or `variant_value`.
If the top-level Variant is not an array (for example, an object), the engine cannot shred the value and it will store it in the top-level `variant_value`.
Similarly, if "a" is not an array, it will be stored in the `variant_value` under "a".

Consider the following example:

```
[
  {
    "a": [1, 2, 3],
    "b": 100,
    “c”: “unexpected”
  },
  {
    "a": [4, 5, 6],
    "b": 200
  },
  “not an object”
]
```

The second array element can be fully shredded, but the first and third cannot be. The contents of `variant_col.array[*].variant_value` would be as follows:

```
[
  { “c”: “unexpected” },
  NULL,
  “not an object”
]
```

# Backward and forward compatibility

Shredding is an optional feature of Variant, and readers must continue to be able to read a group containing only a `value` and `metadata` field.

Any fields in the same group as `typed_value`/`variant_value` that start with `_` (underscore) can be ignored.
This is intended to allow future backwards-compatible extensions.
In particular, the field names `_metadata_key_paths` and any name starting with `_spark` are reserved, and should not be used by other implementations.
Any extra field names that do not start with an underscore should be assumed to be backwards incompatible, and readers should fail when reading such a schema.

Engines without shredding support are not expected to be able to read Parquet files that use shredding.
Since different files may contain conflicting schemas (e.g. a `typed_value` column with incompatible types in two files), it may not be possible to infer or specify a single schema that would allow all Parquet files for a table to be read.
