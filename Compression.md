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

# Parquet compression definitions

This document contains the specification of all supported compression codecs.

## Overview

Parquet allows the data block inside dictionary pages and data pages to
be compressed for better space efficiency.  The Parquet specification allows
several compression codecs, most of which are optional to implement.  Only the
`UNCOMPRESSED` codec is mandatory.

The detailed specifications of compression codecs are maintained externally
by the respective software projects, which we reference hereafter.

For all compression codecs except the deprecated `LZ4` codec, the raw data
of a (data or dictionary) page is fed *as-is* to the underlying compression
library, without any additional framing or padding.  The information required
for precise allocation of compressed and decompressed buffers is written
in the `PageHeader` struct.

## Codecs

### UNCOMPRESSED

No-op codec.  Data is left uncompressed.

### SNAPPY

A codec based on or interoperable with the
[Snappy compression library](https://github.com/google/snappy).

### GZIP

A codec based on or interoperable with the `gzip` format (not the
closely-related `zlib` format) defined by the
[zlib compression library](https://zlib.net/).

### LZO

A codec based on or interoperable with the
[LZO compression library](http://www.oberhumer.com/opensource/lzo/).

### BROTLI

A codec based on or interoperable with the
[Brotli compression library](https://github.com/google/brotli).

### LZ4

A **deprecated** codec loosely based on the LZ4 compression algorithm,
but with an additional undocumented framing scheme.  The framing is part
of the original Hadoop compression library and was historically copied
first in parquet-mr, then emulated with mixed results by parquet-cpp.

It is strongly suggested that implementors of Parquet writers deprecate
this compression codec in their user-facing APIs, and advise users to
switch to the newer, interoperable `LZ4_RAW` codec.

### ZSTD

A codec based on or interoperable with the
[ZStandard compression library](https://facebook.github.io/zstd/).

### LZ4_RAW

A codec based on or interoperable with the LZ4 block format defined by the
[LZ4 compression library](http://www.lz4.org/).
