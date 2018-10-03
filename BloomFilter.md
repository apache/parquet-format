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
In current format, statistic filter and dictionary filter are used for predicate pushdown. Statistic
filter use min/max to filter out values not in range while it can not filter out value within range
but not in set. Dictionary filter can effectively filter out value not in set but it maybe not
enabled since dictionary encoding can be fall back to plain encoding when the overhead threshold
is reached. Therefore, when performing predicate push down against a column with large cardinality,
there is no effective filter with a high probability.

A Bloom filter[1] is a compact data structure to indicate whether an element is a member of a set.
It maintains a bitset initially sets to 0. Once an element is added to the set, it sets several
related bits in bitset to 1. One can query element by checking all of the related bits value.
If all of related bits are set to 1, it means this element is possibly exist in set, otherwise means
the element is definitely not in set. Since the size of Bloom filter is compact and can be controlled
through false positive rate, we can use it as an alternative filter to cover the case of large
cardinality column.

### Goal
* Add a Bloom filter utility which can be used in project.
 
* Implement row group filter base on Bloom Filter. In particular, selective queries with predicate
read Bloom filter data and evaluate predicate to determine whether to skip row group or not.

* No additional I/O overhead when executing queries on other columns without Bloom filter enabled or
non selective queries.

### Technical Approach
The Bloom filter in Parquet is implemented using blocked Bloom filter algorithm from Putze et al.'s
"Cache-, Hash- and Space-Efficient Bloom filters"[2]. Instead of setting bits by calculating index
with different hash functions in standard Bloom filter, the blocked Bloom filter uses a single hash
function to choose a precomputed pattern from a table (called a block or a tiny Bloom filter) of
random k-bit pattern of width w bytes. In many cases, the table fits into a single cache line or
smaller, and the related operation can take advantage of SIMD instructions. In this implementation,
we use a 32-byte table and 8-bit pattern. More specifically, it will set 8 bits in a 32-byte block,
one bit in each 32-bit word.

#### Algorithm
In this blocked Bloom filter implementation, the algorithm use higher 32 bits from hash value in
little endian order as index to select a block from bitset. The lower 32 bits of hash value along
with eight SALT values are used to compute bit pattern to set bits. Multiply-shift[3] schema is used
to construct the bit pattern as shown in following:

```c
// 8 SALT values used to compute bit pattern
static const uint32_t SALT[8] = {0x47b6137bU, 0x44974d91U, 0x8824ad5bU, 0xa2b7289dU, 0x705495c7U,
 0x2df1424bU, 0x9efc4947U, 0x5c6bfb31U};

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
    mask[i] = 0x1U << mask[i];
  }
}

```

#### Hash Function
The hash function used in this implementation is MurmurHash3[4] created by Austin Appleby, it
yields a 32-bit or 128-bit value. When producing 128-bit values, the x86 platform and x64 platform
yield different values as the optimization consideration. Here we use least significant 64 bits
value from the little endian result of 128-bit version on x64 platform.


#### Build a Bloom filter
To build a blocked Bloom filter, it needs to specify the size of Bloom filter bitset. The optimal
size of a Bloom filter can be calculated according to the number of column distinct values in a
row group and an expected false positive probability value. The formula is shown as:

```c
// m: the size of blocked Bloom filter bitset
// n: the number of distinct values of the column in a row group
// p: the expected false positive probability value
		m = -8 * n / log(1 - pow(p, 1.0 / 8));
```

#### File Format
This implementation stores the Bloom filter data of column at the beginning of its column chunk
in the row group. The column chunk metadata contains the Bloom filter offset.

```
struct ColumnMetaData {
  ...
  /** Byte offset from beginning of file **/
  14: optional i64 bloom_filter_offset;
}
```
The Bloom filter is stored with a header and followed bitset. The header is defined as below:
```
struct BloomFilterHeader {

  /** The size of bitset in bytes, must be a  power of 2 and larger than 32**/
  1: required i32 numBytes;

  /** The algorithm for setting bits. **/
  2: required BloomFilterAlgorithm bloomFilterAlgorithm;

  /** The hash function used for bloom filter. **/
  3: required BloomFilterHash bloomFilterHash;
}
```
### Reference
1. [Bloom filter introduction at Wiki](https://en.wikipedia.org/wiki/Bloom_filter)
2. [Cache-, Hash- and Space-Efficient Bloom Filters](http://algo2.iti.kit.edu/documents/cacheefficientbloomfilters-jea.pdf)
3. [A Reliable Randomized Algorithm for the Closest-Pair Problem](http://www.diku.dk/~jyrki/Paper/CP-11.4.1997.ps)
4. [Murmur Hash at Wiki](https://en.wikipedia.org/wiki/MurmurHash)


