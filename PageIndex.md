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

# ColumnIndex Layout to Support Page Skipping

This document describes the format for column index pages in the Parquet
footer. These pages contain statistics for DataPages and can be used to skip
pages when scanning data in ordered and unordered columns.

## Problem Statement
In previous versions of the format, Statistics are stored for ColumnChunks in
ColumnMetaData and for individual pages inside DataPageHeader structs. When
reading pages, a reader had to process the page header to determine
whether the page could be skipped based on the statistics. This means the reader
had to access all pages in a column, thus likely reading most of the column
data from disk.

## Goals
1. Make both range scans and point lookups I/O efficient by allowing direct
   access to pages based on their min and max values. In particular:
    *  A single-row lookup in a row group based on the sort column of that row group
  will only read one data page per the retrieved column.
    * Range scans on the sort column will only need to read the exact data 
      pages that contain relevant data.
    * Make other selective scans I/O efficient: if we have a very selective
      predicate on a non-sorting column, for the other retrieved columns we
      should only need to access data pages that contain matching rows.
2. No additional decoding effort for scans without selective predicates, e.g.,
   full-row group scans. If a reader determines that it does not need to read 
   the index data, it does not incur any overhead.
3. Index pages for sorted columns use minimal storage by storing only the
   boundary elements between pages.

## Non-Goals
* Support for the equivalent of secondary indices, i.e., an index structure
  sorted on the key values over non-sorted data.


## Technical Approach

We add two new per-column structures to the row group metadata:
* ColumnIndex: this allows navigation to the pages of a column based on column
  values and is used to locate data pages that contain matching values for a
  scan predicate
* OffsetIndex: this allows navigation by row index and is used to retrieve
  values for rows identified as matches via the ColumnIndex. Once rows of a
  column are skipped, the corresponding rows in the other columns have to be
  skipped. Hence the OffsetIndexes for each column in a RowGroup are stored
  together.

The new index structures are stored separately from RowGroup, near the footer.  
This is done so that a reader does not have to pay the I/O and deserialization 
cost for reading them if it is not doing selective scans. The index structures'
location and length are stored in ColumnChunk.

 ![Page Index Layout](doc/images/PageIndexLayout.png)

Some observations:
* We don't need to record the lower bound for the first page and the upper
  bound for the last page, because the row group Statistics can provide that.
  We still include those for the sake of uniformity, and the overhead should be
  negligible.
* We store lower and upper bounds for the values of each page. These may be the
  actual minimum and maximum values found on a page, but can also be (more
  compact) values that do not exist on a page. For example, instead of storing
  ""Blart Versenwald III", a writer may set `min_values[i]="B"`,
  `max_values[i]="C"`. This allows writers to truncate large values and writers
  should use this to enforce some reasonable bound on the size of the index
  structures.
* Readers that support ColumnIndex should not also use page statistics. The
  only reason to write page-level statistics when writing ColumnIndex structs
  is to support older readers (not recommended).

For ordered columns, this allows a reader to find matching pages by performing
a binary search in `min_values` and `max_values`. For unordered columns, a
reader can find matching pages by sequentially reading `min_values` and
`max_values`.

For range scans, this approach can be extended to return ranges of rows, page
indices, and page offsets to scan in each column. The reader can then
initialize a scanner for each column and fast forward them to the start row of
the scan.

The `min_values` and `max_values` are calculated based on the `column_orders`
field in the `FileMetaData` struct of the footer.
