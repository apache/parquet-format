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

A Bloom filter[1] is a compact data structure that overapproximates a set. It can respond
to membership queries with either "definitely no" or "probably yes", where the probability
of false positives is configured when the filter is initialized. Bloom filters do not have
false negatives.

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

First, the block Bloom filter algorithm from Putze et al.'s "Cache-, Hash- and
Space-Efficient Bloom filters"[2] is used. This divides a filter into many tiny Bloom
filters, each one of which is called a "block". In Parquet's initial implementation, each
block is 256 bits. When inserting or finding a value, part of the hash of that value is
used to index into the array of blocks and pick a single one. This single block is then
used for the remaining part of the operation.

Second, within each block, this implementation uses the folklore split Bloom filter
technique, as described in section 2.1 of "Network Applications of Bloom Filters: A
Survey"[5]. This divides the 256 bits in each block up into eight contiguous 32-bit lanes
and sets or checks one bit in each lane.

#### Algorithm
In the initial algorithm, the most significant 32 bits from the hash value are used as the
index to select a block from bitset. The lower 32 bits of the hash value, along with eight
constant salt values, are used to compute the bit to set in each lane of the block. The
salt and lower 32 bits are combined using the multiply-shift[3] hash function:

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
The function used to hash values in the initial implementation is xxHash[4], using
the least-significant 64 bits version of the function on the x86-64 platform. Note that
the function produces different values on different architectures, so implementors must
be careful to use the version specific to x86-64. That function can be emulated on
different platforms without difficulty.

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

#### File Format
The Bloom filter data of a column is stored at the beginning of its column chunk in the
row group. The column chunk metadata contains the Bloom filter offset. The Bloom filter is
stored with a header containing the size of the filter in bytes, the algorithm, and the
hash function.

### Reference
1. [Bloom filter introduction at Wiki](https://en.wikipedia.org/wiki/Bloom_filter)
2. [Cache-, Hash- and Space-Efficient Bloom Filters](http://algo2.iti.kit.edu/documents/cacheefficientbloomfilters-jea.pdf)
3. [A Reliable Randomized Algorithm for the Closest-Pair Problem](http://www.diku.dk/~jyrki/Paper/CP-11.4.1997.ps)
4. [xxHash](https://cyan4973.github.io/xxHash/)
5. [Network Applications of Bloom Filters: A Survey](https://www.eecs.harvard.edu/~michaelm/postscripts/im2005b.pdf)
