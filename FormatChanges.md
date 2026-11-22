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

Changing the Format
====

## Scope

When making a change to the Parquet Format, we have to manage problems that
arise from the reader and the writer implementing a different version of the
spec.

This document defines categories of changes to the Parquet Format, and proposes
a set of criteria to evaluate future potential changes.

Changes which are forward compatible do not adversely impact the user and are easier to standardize.
Partially compatible changes are encouraged with a preference for consumers to error out when
un-parsable data is observed. Changes which would produce an incorrect read
require a PAR magic number version change and should be done sparingly.

## Definitions

A change to the Parquet format can have the following properties:

**Compatibility**: We narrow this down to producing the exact same tabular data
while possibly ignoring secondary data structures (like bloom filters, indices,
stats, …). Compatible implies Correct.

- *Backward compatibility*: new readers can read files written by older writers.
- *Forward compatibility*: old readers can read files written by newer writers.

**Correctness**: Avoid reading incorrect data unknowingly.

- *Incorrect read*: a reader producing different data than the writer intended.
- *Correct failed read*: a reader producing an error when it can not read the
  data in the file.

**Partial Compatibility**: when the reader can read a subset of the file (and
knows which subset).

- If only the subset of columns supported is accessed, then the read is
  successful.
- The reader can elect to read only the subset of the data it understands
  depending on the use case.

![Categories of changes: compatible, or incompatible. Incompatible changes cause either an incorrect read or a correct failed read, and a correct failed read is either partially compatible or fully incompatible.](doc/images/FormatChangeCategories.svg)

## Dealing with incompatible changes

### Backward compatibility

New readers are aware of all the past specs and therefore backward compatibility is usually required.

Occasionally, we may drop support of a feature for technical reasons (ex:
dropping LZO support for read because of the additional complexity of linking
libraries). This is usually for features that are practically not used anymore
(or close). In such a case, new readers should fail with a clear error and not
produce correctness issues.

### Forward compatibility

Old readers, however, are not aware of future spec changes.

#### Reader behavior

Ordered by desirability:

| Name | Possible behaviors of the reader | When used | Example | User experience |
|------|----------------------------------|-----------|---------|-----------------|
| **Correct Read** | Reads data correctly.<br>Sometimes ignores supplemental data structures it doesn't know about. | This is the most frequent case for forward compatibility. We add new features that do not prevent old readers from reading the data correctly even though they might not take advantage of those new features. | You can read the data correctly and not understand bloom filters or statistics. | **Forward compatible**: The format evolves seamlessly. |
| **Correct Partial Read** | Reads correctly a subset of the columns as long as the unsupported columns don't need to be accessed and correctly fails otherwise. | When a feature cannot be introduced without breaking forward compatibility (ex: new encoding), old readers are able to read files and columns that do not use that new feature and know they can not read the ones that do and why. | [ALP Encoding](Encodings.md#ALP): Old readers can read all the columns that don't use this encoding that applies only to floating point columns. | **Forward incompatible but correct**: Old readers will explain failed reads and preserve correctness.<br>New writers can be configured to hold off on using new features until all readers support it. |
| **Correct Failure to Read** | Can't read data at all but understands why. | When a feature cannot be introduced without breaking file-level compatibility, old readers know they can not read the file. | Changing the footer format. The reader has no granular information and fails on the magic number change. | Same as Correct Partial Read: **Forward incompatible but correct**. |
| **Best Effort Read** | Reads the subset of data it understands and ignores the rest. | Similar to Correct Partial Reads. In cases where this does not lead to data loss, readers can elect to read only the subset of the file they can read correctly. This is different from a correct partial read as a "select \*" would return only the columns it understands instead of failing for not reading a subset of the columns. | "Select \*" ignoring columns encoded in ALP and returning the subset of the file that is readable. | **Forward incompatible best effort**: Old readers can elect to read in best effort the subset of the data. Not reading incorrect data but would lead to dropping data if the output was saved without understanding the difference with "correct partial read". |
| **Incorrect Read** | Reads data but unknowingly misinterprets it. | When an old reader reads incorrect data because a semantic change is indistinguishable and they have no way to know their read is incorrect.<br>**This should never happen.** | Semantic changes to an existing field like stats. We avoid this case at all costs. | **Incorrect**: Silently reading the data incorrectly. |

### Evaluation system for changes to Parquet

When making a change to the format we optimize for that user experience.

Making changes to the Parquet format falls in 3 categories:

- **Forward compatible**: Correct Read
- **Forward incompatible**:
  - The metadata describes what can be read and not read: the reader decides
    between Correct Partial Read and Best Effort Read.
  - The metadata doesn't describe what can be read and not read (this happens
    for example with the new footer format): Correct Failure to Read.
- We don't make semantic changes that would cause old readers to produce an
  Incorrect Read.

![Decision flow for a change: if it can be made forward compatible, it results in a Correct Read. Otherwise, if the metadata can tell old readers what and why they can not read, it results in a Correct Partial Read or Best Effort Read. Otherwise the magic number must be incremented, resulting in a Correct Failure to Read. If not, the result is an Incorrect Read. Except for a footer format change, we will prefer finding a way to either make it forward compatible or described by the metadata.](doc/images/FormatChangeDecisionTree.svg)

In particular that means that we avoid changing the semantics of an existing
field. For example changing a sort order that changes the min-max statistics.
Instead it can be made forward compatible by adding new metadata fields. Making
a forward compatible change like this is usually preferable to breaking
correctness or forcing a magic number increment.

See also [Extensibility](README.md#extensibility) for the places in
the format designed for compatible extensions.
