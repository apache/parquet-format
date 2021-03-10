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
be compressed for better space efficiency. The Parquet format supports
several compression covering different areas in the compression ratio /
processing cost spectrum.

The detailed specifications of compression codecs are maintained externally
by their respective authors or maintainers, which we reference hereafter.

For all compression codecs except the deprecated `LZ4` codec, the raw data
of a (data or dictionary) page is fed *as-is* to the underlying compression
library, without any additional framing or padding.  The information required
for precise allocation of compressed and decompressed buffers is written
in the `PageHeader` struct.

## Codecs

### UNCOMPRESSED

No-op codec.  Data is left uncompressed.

### SNAPPY

A codec based on the
[Snappy compression format](https://github.com/google/snappy/blob/master/format_description.txt).
If any ambiguity arises when implementing this format, the implementation
provided by Google Snappy [library](https://github.com/google/snappy/)
is authoritative.

### GZIP

A codec based on the GZIP format (not the closely-related "zlib" or "deflate"
formats) defined by [RFC 1952](https://tools.ietf.org/html/rfc1952).
If any ambiguity arises when implementing this format, the implementation
provided by the [zlib compression library](https://zlib.net/) is authoritative.

### LZO

A codec based on or interoperable with the
[LZO compression library](http://www.oberhumer.com/opensource/lzo/).

### BROTLI

A codec based on the Brotli format defined by
[RFC 7932](https://tools.ietf.org/html/rfc7932).
If any ambiguity arises when implementing this format, the implementation
provided by the  [Brotli compression library](https://github.com/google/brotli)
is authoritative.

### LZ4

A **deprecated** codec loosely based on the LZ4 compression algorithm,
but with an additional undocumented framing scheme.  The framing is part
of the original Hadoop compression library and was historically copied
first in parquet-mr, then emulated with mixed results by parquet-cpp.

It is strongly suggested that implementors of Parquet writers deprecate
this compression codec in their user-facing APIs, and advise users to
switch to the newer, interoperable `LZ4_RAW` codec.

### ZSTD

A codec based on the Zstandard format defined by
[RFC 8478](https://tools.ietf.org/html/rfc8478).  If any ambiguity arises
when implementing this format, the implementation provided by the
[ZStandard compression library](https://facebook.github.io/zstd/)
is authoritative.

### LZ4_RAW

A codec based on the [LZ4 block format](https://github.com/lz4/lz4/blob/dev/doc/lz4_Block_format.md).
If any ambiguity arises when implementing this format, the implementation
provided by the [LZ4 compression library](http://www.lz4.org/) is authoritative.
