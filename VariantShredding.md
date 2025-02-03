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
This process is **shredding**.

Shredding enables the use of Parquet's columnar representation for more compact data encoding, column statistics for data skipping, and partial projections.

For example, the query `SELECT variant_get(event, '$.event_ts', 'timestamp') FROM tbl` only needs to load field `event_ts`, and if that column is shredded, it can be read by columnar projection without reading or deserializing the rest of the `event` Variant.
Similarly, for the query `SELECT * FROM tbl WHERE variant_get(event, '$.event_type', 'string') = 'signup'`, the `event_type` shredded column metadata can be used for skipping and to lazily load the rest of the Variant.

## Variant Metadata

Variant metadata is stored in the top-level Variant group in a binary `metadata` column regardless of whether the Variant value is shredded.

All `value` columns within the Variant must use the same `metadata`.
All field names of a Variant, whether shredded or not, must be present in the metadata.

## Value Shredding

Variant values are stored in Parquet fields named `value`.
Each `value` field may have an associated shredded field named `typed_value` that stores the value when it matches a specific type.
When `typed_value` is present, readers **must** reconstruct shredded values according to this specification.

For example, a Variant field, `measurement` may be shredded as long values by adding `typed_value` with type `int64`:
```
required group measurement (VARIANT) {
  required binary metadata;
  optional binary value;
  optional int64 typed_value;
}
```

The Parquet columns used to store variant metadata and values must be accessed by name, not by position.

The series of measurements `34, null, "n/a", 100` would be stored as:

| Value   | `metadata`       | `value`               | `typed_value` |
|---------|------------------|-----------------------|---------------|
| 34      | `01 00` v1/empty | null                  | `34`          |
| null    | `01 00` v1/empty | `00` (null)           | null          |
| "n/a"   | `01 00` v1/empty | `13 6E 2F 61` (`n/a`) | null          |
| 100     | `01 00` v1/empty | null                  | `100`         |

Both `value` and `typed_value` are optional fields used together to encode a single value.
Values in the two fields must be interpreted according to the following table:

| `value`  | `typed_value` | Meaning                                                     |
|----------|---------------|-------------------------------------------------------------|
| null     | null          | The value is missing; only valid for shredded object fields |
| non-null | null          | The value is present and may be any type, including null    |
| null     | non-null      | The value is present and is the shredded type               |
| non-null | non-null      | The value is present and is a partially shredded object     |

An object is _partially shredded_ when the `value` is an object and the `typed_value` is a shredded object.
Writers must not produce data where both `value` and `typed_value` are non-null, unless the Variant value is an object.

If a Variant is missing in a context where a value is required, readers must return a Variant null (`00`): basic type 0 (primitive) and physical type 0 (null).
For example, if a Variant is required (like `measurement` above) and both `value` and `typed_value` are null, the returned `value` must be `00` (Variant null).

### Shredded Value Types

Shredded values must use the following Parquet types:

| Variant Type                | Equivalent Parquet Type           |
|-----------------------------|-----------------------------------|
| boolean                     | BOOLEAN                           |
| int8                        | INT(8, signed=true)               |
| int16                       | INT(16, signed=true)              |
| int32                       | INT32 / INT(32, signed=true)      |
| int64                       | INT64 / INT(64, signed=true)      |
| float                       | FLOAT                             |
| double                      | DOUBLE                            |
| decimal4                    | INT32 / DECIMAL(precision, scale) |
| decimal8                    | INT64 / DECIMAL(precision, scale) |
| decimal16                   | DECIMAL(precision, scale)         |
| date                        | DATE                              |
| time                        | TIME(false, MICROS)               |
| timestamp with time zone    | TIMESTAMP(true, MICROS|NANOS)     |
| timestamp without time zone | TIMESTAMP(false, MICROS|NANOS)    |
| binary                      | BINARY                            |
| string                      | BINARY / STRING                   |
| uuid                        | FIXED_LEN_BYTE_ARRAY[16] / UUID   |
| array                       | LIST; see Arrays below            |
| object                      | GROUP; see Objects below          |

#### Primitive Types

Primitive values can be shredded using the equivalent Parquet primitive type from the table above for `typed_value`.

Unless the value is shredded as an object (see [Objects](#objects)), `typed_value` or `value` (but not both) must be non-null.

#### Arrays

Arrays can be shredded by using a 3-level Parquet list for `typed_value`.

If the value is not an array, `typed_value` must be null.
If the value is an array, `value` must be null.

The list `element` must be a required group.
The `element` group can contain `value` and `typed_value` fields.
The element's `value` field stores the element as Variant-encoded `binary` when the `typed_value` is not present or cannot represent it.
The `typed_value` field may be omitted when not shredding elements as a specific type.
When `typed_value` is omitted, `value` must be `required`.

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

All elements of an array must be present (not missing) because the `array` Variant encoding does not allow missing elements.
That is, either `typed_value` or `value` (but not both) must be non-null.
Null elements must be encoded in `value` as Variant null: basic type 0 (primitive) and physical type 0 (null).

The series of `tags` arrays `["comedy", "drama"], ["horror", null], ["comedy", "drama", "romance"], null` would be stored as:

| Array                            | `value`     | `typed_value `| `typed_value...value` | `typed_value...typed_value`    |
|----------------------------------|-------------|---------------|-----------------------|--------------------------------|
| `["comedy", "drama"]`            | null        | non-null      | [null, null]          | [`comedy`, `drama`]            |
| `["horror", null]`               | null        | non-null      | [null, `00`]          | [`horror`, null]               |
| `["comedy", "drama", "romance"]` | null        | non-null      | [null, null, null]    | [`comedy`, `drama`, `romance`] |
| null                             | `00` (null) | null          |                       |                                |

#### Objects

Fields of an object can be shredded using a Parquet group for `typed_value` that contains shredded fields.

If the value is an object, `typed_value` must be non-null.
If the value is not an object, `typed_value` must be null.
Readers can assume that a value is not an object if `typed_value` is null and that `typed_value` field values are correct; that is, readers do not need to read the `value` column if `typed_value` fields satisfy the required fields.

Each shredded field in the `typed_value` group is represented as a required group that contains optional `value` and `typed_value` fields.
The `value` field stores the value as Variant-encoded `binary` when the `typed_value` cannot represent the field.
This layout enables readers to skip data based on the field statistics for `value` and `typed_value`.

The `value` column of a partially shredded object must never contain fields represented by the Parquet columns in `typed_value` (shredded fields).
Readers may always assume that data is written correctly and that shredded fields in `typed_value` are not present in `value`.
As a result, reads when a field is defined in both `value` and a `typed_value` shredded field may be inconsistent.

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

The group for each named field must use repetition level `required`.

A field's `value` and `typed_value` are set to null (missing) to indicate that the field does not exist in the variant.
To encode a field that is present with a null value, the `value` must contain a Variant null: basic type 0 (primitive) and physical type 0 (null).

When both `value` and `typed_value` for a field are non-null, engines should fail.
If engines choose to read in such cases, then the `typed_value` column must be used.
Readers may always assume that data is written correctly and that only `value` or `typed_value` is defined.
As a result, reads when both `value` and `typed_value` are defined may be inconsistent with optimized reads that require only one of the columns.

The table below shows how the series of objects in the first column would be stored:

| Event object                                                                       | `value`                           | `typed_value` | `typed_value.event_type.value` | `typed_value.event_type.typed_value` | `typed_value.event_ts.value` | `typed_value.event_ts.typed_value` | Notes                                            |
|------------------------------------------------------------------------------------|-----------------------------------|---------------|--------------------------------|--------------------------------------|------------------------------|------------------------------------|--------------------------------------------------|
| `{"event_type": "noop", "event_ts": 1729794114937}`                                | null                              | non-null      | null                           | `noop`                               | null                         | 1729794114937                      | Fully shredded object                            |
| `{"event_type": "login", "event_ts": 1729794146402, "email": "user@example.com"}`  | `{"email": "user@example.com"}`   | non-null      | null                           | `login`                              | null                         | 1729794146402                      | Partially shredded object                        |
| `{"error_msg": "malformed: ..."}`                                                  | `{"error_msg", "malformed: ..."}` | non-null      | null                           | null                                 | null                         | null                               | Object with all shredded fields missing          |
| `"malformed: not an object"`                                                       | `malformed: not an object`        | null          |                                |                                      |                              |                                    | Not an object (stored as Variant string)         |
| `{"event_ts": 1729794240241, "click": "_button"}`                                  | `{"click": "_button"}`            | non-null      | null                           | null                                 | null                         | 1729794240241                      | Field `event_type` is missing                    |
| `{"event_type": null, "event_ts": 1729794954163}`                                  | null                              | non-null      | `00` (field exists, is null)   | null                                 | null                         | 1729794954163                      | Field `event_type` is present and is null        |
| `{"event_type": "noop", "event_ts": "2024-10-24"`                                  | null                              | non-null      | null                           | `noop`                               | `"2024-10-24"`               | null                               | Field `event_ts` is present but not a timestamp  |
| `{ }`                                                                              | null                              | non-null      | null                           | null                                 | null                         | null                               | Object is present but empty                      |
| null                                                                               | `00` (null)                       | null          |                                |                                      |                              |                                    | Object/value is null                             |
| missing                                                                            | null                              | null          |                                |                                      |                              |                                    | Object/value is missing                          |
| INVALID                                                                            | `{"event_type": "login"}`         | non-null      | null                           | `login`                              | null                         | 1729795057774                      | INVALID: Shredded field is present in `value`    |
| INVALID                                                                            | `"a"`                             | non-null      | null                           | null                                 | null                         | null                               | INVALID: `typed_value` is present for non-object |
| INVALID                                                                            | `02 00` (object with 0 fields)    | null          |                                |                                      |                              |                                    | INVALID: `typed_value` is null for object        |

Invalid cases in the table above must not be produced by writers.
Readers must return an object when `typed_value` is non-null containing the shredded fields.

## Nesting

The `typed_value` associated with any Variant `value` field can be any shredded type, as shown in the sections above.

For example, the `event` object above may also shred sub-fields as object (`location`) or array (`tags`).

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

# Data Skipping

Statistics for `typed_value` columns can be used for file, row group, or page skipping when `value` is always null (missing).

When the corresponding `value` column is all nulls, all values must be the shredded `typed_value` field's type.
Because the type is known, comparisons with values of that type are valid.
`IS NULL`/`IS NOT NULL` and `IS NAN`/`IS NOT NAN` filter results are also valid.

Comparisons with values of other types are not necessarily valid and data should not be skipped.

Casting behavior for Variant is delegated to processing engines.
For example, the interpretation of a string as a timestamp may depend on the engine's SQL session time zone.

## Reconstructing a Shredded Variant

It is possible to recover an unshredded Variant value using a recursive algorithm, where the initial call is to `construct_variant` with the top-level Variant group fields.

```python
def construct_variant(metadata: Metadata, value: Variant, typed_value: Any) -> Variant:
    """Constructs a Variant from value and typed_value"""
    if typed_value is not None:
        if isinstance(typed_value, dict):
            # this is a shredded object
            object_fields = {
                name: construct_variant(metadata, field.value, field.typed_value)
                for (name, field) in typed_value
            }

            if value is not None:
                # this is a partially shredded object
                assert isinstance(value, VariantObject), "partially shredded value must be an object"
                assert typed_value.keys().isdisjoint(value.keys()), "object keys must be disjoint"

                # union the shredded fields and non-shredded fields
                return VariantObject(metadata, object_fields).union(VariantObject(metadata, value))

            else:
                return VariantObject(metadata, object_fields)

        elif isinstance(typed_value, list):
            # this is a shredded array
            assert value is None, "shredded array must not conflict with variant value"

            elements = [
                construct_variant(metadata, elem.value, elem.typed_value)
                for elem in list(typed_value)
            ]
            return VariantArray(metadata, elements)

        else:
            # this is a shredded primitive
            assert value is None, "shredded primitive must not conflict with variant value"

            return primitive_to_variant(typed_value)

    elif value is not None:
        return Variant(metadata, value)

    else:
        # value is missing
        return None

def primitive_to_variant(typed_value: Any): Variant:
    if isinstance(typed_value, int):
        return VariantInteger(typed_value)
    elif isinstance(typed_value, str):
        return VariantString(typed_value)
    ...
```


## Backward and forward compatibility

Shredding is an optional feature of Variant, and readers must continue to be able to read a group containing only `value` and `metadata` fields.

Engines that do not write shredded values must be able to read shredded values according to this spec or must fail.

Different files may contain conflicting shredding schemas.
That is, files may contain different `typed_value` columns for the same Variant with incompatible types.
It may not be possible to infer or specify a single shredded schema that would allow all Parquet files for a table to be read without reconstructing the value as a Variant.
