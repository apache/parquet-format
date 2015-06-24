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

Parquet statistics definitions
===
This file contains the specification of all supported encodings.

### Bloom filter statistics

Supported Types: Integer

The bloom filter is stored per block which is used to filter some blocks when reading the parquet file.

#### Background for bloom filter
In short, bloom filter maintains a bit set which is set to 1 for all bits. Once one entry added to the filter, it will use the hash functions to set several bits to 1. Using thge same hash functions,
we can see if a new entry is already included checking all of the related bits value. If all of them are set to 1, it means this entry is already added, otherwise not.
In this way we can use the bloom filter to skip some data in block level for parquet. From the Wikipedia, you can see the definition of bloom filter as follows:
```An empty Bloom filter is a bit array of m bits, all set to 0.
There must also be k different hash functions defined, each of which maps or hashes some set element to one of the m array positions with a uniform random distribution.```
To construct a bloom filter, two parameters are required:
* _m_: Number of bits
* _k_: Number of hash function
These two parameters could be approximated by two other parameters (The formulas are available in the [Wikipedia](https://en.wikipedia.org/wiki/Bloom_filter)):

* _f_: abbreviation for false positive probability
* _n_: the number of elements being filtered

The code snippet for the data structure of bloom filter is mainly referred from [Apache Hive](https://hive.apache.org/) project and the implementation of bloom filter from [Guava](http://code.google.com/p/guava-libraries/).

### The structure of bloom filter in parquet-format
In the statistics, we have the following information for bloom filter.
```
list<i64> bitSet: the bit set storing the generated bit values using added entries
i32 numBits; number of bit which is evaluated in the way discussed in the previous section
i32 numHashFunctions; number of hash functions to generate the bit from the encountering entries
```

#### Implementation of the bloom filter in parquet-mr
Currently we support two bloom filter strategies. One is using two 32bit hash functions and another is using all 128 bits of Murmur3 128 when hashing. The first one is mentioned in "Less Hashing, Same Performance: Building a Better Bloom Filter" by Kirsch et.al. From abstract 'only two hash functions are necessary to effectively implement a Bloom filter without any loss in the asymptotic false positive probability' Lets split up 64-bit hashcode into two 32-bit hash codes and employ the technique mentioned in the above paper

#### Build a bloom filter in the parquet-mr
To build a bloom filter, users need to add the following four configurations:

* _parquet.enable.bloom.filter_: Whether to enable the bloom filter
* _parquet.bloom.filter.fpp.value_: The value of FPP (Abbr. false positive probability)
* _parquet.bloom.filter.fpp.provided_: As the fpp is optional, so this configuration is not required and the default value is 0.05
* _parquet.expected.entries_: The expected entries number

These configurations are grouped into BloomFilterOpts. The class BloomFilterBuilder could use BloomFilterOpts to build a BloomFilter. And the bloom filter is supported only in some of the basic data type. For example, it doesn¡¯t make sense to enable bloom filter for a bool type. Addressing this concern, the supported Statistics needs to implement the interface BloomFilterStatistics.

#### How BloomFilter works in Parquet
The bloom filter is part of the statistics like Min/Max Statistics.
For EQ operation, you could check if one entry is included in the row group.
You could refer to the code snippet in StatisticsFilter. If the number isn't within the range or not include in the bloom filter, it will be dropped.

#### How to enable it in Hive side
Besides the bloom filter related configuration, you need to add the parameters to enable predicate pushing down as well.

```
SET hive.optimize.ppd=true;
SET hive.optimize.index.filter=true;
```

#### Examples
Assume you have 12, 14, 16 and 17 in one block. And you are executing the statement `SELECT * FROM tble_name WHERE id > 11 AND id < 17` on the table `tble_name` defined in the structure `(id Int, value Int)`.
For Min/Max statistics, this block will not be skipped in the reader initial stage since it accepts the Statistics filter.
If you have bloom filter enabled, this block will be dropped since the bit set stored in the bloom stats doesn't have all bits 16 required.


