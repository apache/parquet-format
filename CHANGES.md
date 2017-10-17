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

# Parquet #

### Version 2.4.0 ###

#### Bug

*   [PARQUET-255](https://issues.apache.org/jira/browse/PARQUET-255) - Typo in decimal type specification
*   [PARQUET-322](https://issues.apache.org/jira/browse/PARQUET-322) - Document ENUM as a logical type
*   [PARQUET-412](https://issues.apache.org/jira/browse/PARQUET-412) - Format: Do not shade slf4j-api
*   [PARQUET-419](https://issues.apache.org/jira/browse/PARQUET-419) - Update dev script in parquet-cpp to remove incubator.
*   [PARQUET-655](https://issues.apache.org/jira/browse/PARQUET-655) - The LogicalTypes.md link in README.md points to the old Parquet GitHub repository
*   [PARQUET-1031](https://issues.apache.org/jira/browse/PARQUET-1031) - Fix spelling errors, whitespace, GitHub urls
*   [PARQUET-1032](https://issues.apache.org/jira/browse/PARQUET-1032) - Change link in Encodings.md for variable length encoding
*   [PARQUET-1050](https://issues.apache.org/jira/browse/PARQUET-1050) - The comment of Parquet Format Thrift definition file error
*   [PARQUET-1076](https://issues.apache.org/jira/browse/PARQUET-1076) - [Format] Switch to long key ids in KEYs file
*   [PARQUET-1091](https://issues.apache.org/jira/browse/PARQUET-1091) - Wrong and broken links in README
*   [PARQUET-1102](https://issues.apache.org/jira/browse/PARQUET-1102) - Travis CI builds are failing for parquet-format PRs
*   [PARQUET-1134](https://issues.apache.org/jira/browse/PARQUET-1134) - Release Parquet format 2.4.0
*   [PARQUET-1136](https://issues.apache.org/jira/browse/PARQUET-1136) - Makefile is broken

#### Improvement

*   [PARQUET-371](https://issues.apache.org/jira/browse/PARQUET-371) - Bumps Thrift version to 0.9.3
*   [PARQUET-407](https://issues.apache.org/jira/browse/PARQUET-407) - Incorrect delta-encoding example
*   [PARQUET-428](https://issues.apache.org/jira/browse/PARQUET-428) - Support INT96 and FIXED_LEN_BYTE_ARRAY types
*   [PARQUET-601](https://issues.apache.org/jira/browse/PARQUET-601) - Add support in Parquet to configure the encoding used by ValueWriters
*   [PARQUET-609](https://issues.apache.org/jira/browse/PARQUET-609) - Add Brotli compression to Parquet format
*   [PARQUET-757](https://issues.apache.org/jira/browse/PARQUET-757) - Add NULL type to Bring Parquet logical types to par with Arrow
*   [PARQUET-804](https://issues.apache.org/jira/browse/PARQUET-804) - parquet-format README.md still links to the old Google group
*   [PARQUET-922](https://issues.apache.org/jira/browse/PARQUET-922) - Add index pages to the format to support efficient page skipping
*   [PARQUET-1049](https://issues.apache.org/jira/browse/PARQUET-1049) - Make thrift version a property in pom.xml

#### Task

*   [PARQUET-450](https://issues.apache.org/jira/browse/PARQUET-450) - Small typos/issues in parquet-format documentation
*   [PARQUET-667](https://issues.apache.org/jira/browse/PARQUET-667) - Update committers lists to point to apache website
*   [PARQUET-1124](https://issues.apache.org/jira/browse/PARQUET-1124) - Add new compression codecs to the Parquet spec
*   [PARQUET-1125](https://issues.apache.org/jira/browse/PARQUET-1125) - Add UUID logical type

### Version 2.2.0 ###

* [PARQUET-23](https://issues.apache.org/jira/browse/PARQUET-23): Rename packages and maven coordinates to org.apache
* [PARQUET-119](https://issues.apache.org/jira/browse/PARQUET-119): Add encoding stats to ColumnMetaData
* [PARQUET-79](https://issues.apache.org/jira/browse/PARQUET-79): Streaming thrift API
* [PARQUET-12](https://issues.apache.org/jira/browse/PARQUET-12): New logical types

### Version 2.1.0 ###
* ISSUE [84](https://github.com/Parquet/parquet-format/pull/84): Add metadata in the schema for storing decimals.
* ISSUE [89](https://github.com/Parquet/parquet-format/pull/89): Added statistics to the data page header
* ISSUE [86](https://github.com/Parquet/parquet-format/pull/86): Fix minor formatting, correct some wording under the "Error recovery" se...
* ISSUE [82](https://github.com/Parquet/parquet-format/pull/82): exclude thrift source from jar
* ISSUE [80](https://github.com/Parquet/parquet-format/pull/80): Upgrade maven-shade-plugin to 2.1 to compile with mvn 3.1.1

### Version 2.0.0 ###
* ISSUE [79](https://github.com/Parquet/parquet-format/pull/79): Reorganize encodings and add details
* ISSUE [78](https://github.com/Parquet/parquet-format/pull/78): Added sorted flag to dictionary page headers.
* ISSUE [77](https://github.com/Parquet/parquet-format/pull/77): fix plugin versions
* ISSUE [75](https://github.com/Parquet/parquet-format/pull/75): refactor dictionary encoding
* ISSUE [64](https://github.com/Parquet/parquet-format/pull/64): new data page and stats
* ISSUE [74](https://github.com/Parquet/parquet-format/pull/74): deprecate and remove group_var_int encoding
* ISSUE [76](https://github.com/Parquet/parquet-format/pull/76): add mention of boolean on RLE
* ISSUE [73](https://github.com/Parquet/parquet-format/pull/73): reformat encodings
* ISSUE [71](https://github.com/Parquet/parquet-format/pull/71): refactor documentation for 2.0 encodings
* ISSUE [66](https://github.com/Parquet/parquet-format/pull/66): Block strings
* ISSUE [67](https://github.com/Parquet/parquet-format/pull/67): Add ENUM ConvertedType
* ISSUE [58](https://github.com/Parquet/parquet-format/pull/58): Correct unterminated comment for SortingColumn.
* ISSUE [51](https://github.com/Parquet/parquet-format/pull/51): Add metadata to specify row groups are sorted.

### Version 1.0.0 ###
* ISSUE [46](https://github.com/Parquet/parquet-format/pull/46): Update readme to include 4 byte length in rle columns
* ISSUE [47](https://github.com/Parquet/parquet-format/pull/47): fixed typo in readme.md
* ISSUE [45](https://github.com/Parquet/parquet-format/pull/45): Typo in describing preferred row group size
* ISSUE [43](https://github.com/Parquet/parquet-format/pull/43): add dictionary encoding details
* ISSUE [41](https://github.com/Parquet/parquet-format/pull/41): Update readme with details about RLE encoding
* ISSUE [39](https://github.com/Parquet/parquet-format/pull/39): Added created_by optional file metadata.
* ISSUE [40](https://github.com/Parquet/parquet-format/pull/40): add details about the page size fields
* ISSUE [35](https://github.com/Parquet/parquet-format/pull/35): this embeds and renames the thrift dependency in the jar, allowing people to use a different version of thrift in parallel
* ISSUE [36](https://github.com/Parquet/parquet-format/pull/36): adding the encoding to the dictionary page
* ISSUE [34](https://github.com/Parquet/parquet-format/pull/34): Corrected typo
* ISSUE [32](https://github.com/Parquet/parquet-format/pull/32): Add layout diagram to README and fix typo
* ISSUE [31](https://github.com/Parquet/parquet-format/pull/31): Restore encoding changes
