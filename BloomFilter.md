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

Parquet Bloom Filter
===
### Problem statement
In their current format, column statistics and dictionaries can be used for predicate
pushdown. Statistics include minimum and maximum value, which can be used to filter out
values not in the range. Dictionaries are more specific, and readers can filter out values
that are between min and max but not in the dictionary. However, when there are too many
distinct values, writers sometimes choose not to add dictionaries because of the extra
space they occupy. This leaves columns with large cardinalities and widely separated min
and max without support for predicate pushdown.

A [Bloom filter](https://en.wikipedia.org/wiki/Bloom_filter) is a compact data structure that
overapproximates a set. It can respond to membership queries with either "definitely no" or
"probably yes", where the probability of false positives is configured when the filter is
initialized. Bloom filters do not have false negatives.

Because Bloom filters are small compared to dictionaries, they can be used for predicate
pushdown even in columns with high cardinality and when space is at a premium.

### Goal
* Enable predicate pushdown for high-cardinality columns while using less space than
  dictionaries.

* Induce no additional I/O overhead when executing queries on columns without Bloom
  filters attached or when executing non-selective queries.

### Technical Approach
The initial Bloom filter algorithm in Parquet is implemented using a combination of two
Bloom filter techniques.

First, the block Bloom filter algorithm from Putze et al.'s [Cache-, Hash- and Space-Efficient
Bloom filters](http://algo2.iti.kit.edu/documents/cacheefficientbloomfilters-jea.pdf) is used.
The block Bloom filter consists of a sequence of small Bloom filters, each of which can fit
into one cache-line. For best performance, those small Bloom filters are loaded into memory
cache-line-aligned. For each potential element, the first hash value selects the Bloom filter block
to be used. Additional hash values are then used to set or test bits as usual, but only inside
this one block. As for Parquet's initial implementation, each block is 256 bits. When inserting or
finding value, the first hash of that value is used to index into the array of blocks and pick a
single one. This single block is then used for the remaining part of the operation.

Second, the remaining part of the operation within the single block uses the folklore split Bloom
filter technique, as described in section 2.1 of [Network Applications of Bloom Filters:
A Survey](https://www.eecs.harvard.edu/~michaelm/postscripts/im2005b.pdf). Instead of having one
array of size `m` shared among all the hash functions, each hash function has a range of `m/k`
consecutive bit locations disjoint from all the others. The total number of bits is still
<em>m</em>, but the bits are divided equally among the `k` hash functions. This approach
can be useful for implementation reasons, for example, dividing the bits among the hash functions
may make parallelization of array accesses easier and take utilization of SSE. As for Parquet's
implementation, it divides the 256 bits in each block up into eight contiguous 32-bit lanes and
sets or checks one bit in each lane.

#### Algorithm
In the initial algorithm, the most significant 32 bits from the hash value are used as the
index to select a block from bitset. The lower 32 bits of the hash value, along with eight
constant salt values, are used to compute the bit to set in each lane of the block. The
salt and lower 32 bits are combined using the
[multiply-shift](http://www.diku.dk/~jyrki/Paper/CP-11.4.1997.ps) hash function:

```c
// 8 SALT values used to compute bit pattern
static const uint32_t SALT[8] = {0x47b6137bU, 0x44974d91U, 0x8824ad5bU, 0xa2b7289dU,
  0x705495c7U, 0x2df1424bU, 0x9efc4947U, 0x5c6bfb31U};

// key: the lower 32 bits of hash result
// mask: the output bit pattern for a tiny Bloom filter
void Mask(uint32_t key, uint32_t mask[8]) {
  for (int i = 0; i < 8; ++i) {
    mask[i] = key * SALT[i];
  }
  for (int i = 0; i < 8; ++i) {
    mask[i] = mask[i] >> 27;
  }
  for (int i = 0; i < 8; ++i) {
    mask[i] = UINT32_C(1) << mask[i];
  }
}

```

#### Hash Function
The function used to hash values in the initial implementation is
[xxHash](https://cyan4973.github.io/xxHash/), using the least-significant 64 bits version of the
function on the x86-64 platform. Note that the function produces different values on different
architectures, so implementors must be careful to use the version specific to x86-64. That function
can be emulated on different platforms without difficulty.

#### Build a Bloom filter
The fact that exactly eight bits are checked during each lookup means that these filters
are most space efficient when used with an expected false positive rate of about
0.5%. This is achieved when there are about 11.54 bits for every distinct value inserted
into the filter.

To calculate the size the filter should be for another false positive rate `p`, use the
following formula. The output is in bits per distinct element:

```c
-8 / log(1 - pow(p, 1.0 / 8));
```

In the real scenario, the size of the Bloom filter and the false positive rate may vary from
different implementations. It is recommended to set false positive to 1% so that a Bloom filter
with 1.2MB size can contain one million distinct values, which should satisfy most cases according
to default row group size. It is also recommended to expose the ability for setting these
parameters to end users.

#### File Format
The Bloom filter data of a column, which contains the size of the filter in bytes, the algorithm,
the hash function and the Bloom filter bitset, is stored near the footer. The Bloom filter data
offset is stored in column chunk metadata.

#### Encryption
The Bloom filter offset is stored in column chunk metadata which will be encrypted with the column
key when encryption is enabled. The Bloom filter data itself should also be encrypted with column
key as well if encryption is enabled.

