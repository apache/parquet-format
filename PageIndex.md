# ColumnIndex Layout to Support Page Skipping

This documents describes the format for column index pages in the Parquet
footer. These pages contain statistics for DataPages and can be used to skip
pages when scanning data in ordered and unordered columns.

## Problem Statement
In the current format, Statistics are stored for ColumnChunks in ColumnMetaData
and for individual pages inside DataPageHeader structs. When reading pages, a
reader has to process the page header in order to determine whether the page
can be skipped based on the statistics. This means the reader has to access all
pages in a column, thus likely reading most of the column data from disk.

## Goals
1. Make both range scans and point lookups I/O efficient by allowing direct
   access to pages based on their min and max values. In particular:
1. A single-row lookup in a rowgroup based on the sort column of that rowgroup
   will only read one data page per retrieved column.
    * Range scans on the sort column will only need to read the exact data
      pages that contain relevant data.
    * Make other selective scans I/O efficient: if we have a very selective
      predicate on a non-sorting column, for the other retrieved columns we
      should only need to access data pages that contain matching rows.
1. No additional decoding effort for scans without selective predicates, e.g.,
   full-row group scans. If a reader determines that it does not need to read
   the index data, it does not incur any overhead.
1. Index pages for sorted columns use minimal storage by storing only the
   boundary elements between pages.

## Non-Goals
* Support for the equivalent of secondary indices, ie, an index structure
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

The new index structures are stored separately from RowGroup, near the footer,
so that a reader does not have to pay the I/O and deserialization cost for
reading the them if it is not doing selective scans. The index structures'
location and length are stored in ColumnChunk.

 ![Page Index Layout](doc/images/PageIndexLayout.png)

Some observations:
* We don't need to record the lower bound for the first page and the upper
  bound for the last page, because the row group Statistics can provide that.
  We still include those for the sake of uniformity, and the overhead should be
  negligible.
* Readers that support ColumnIndex should not also use page statistics. The
  only reason to write page-level statistics when writing ColumnIndex structs
  is to support older readers (not recommended).

This allows a reader to find matching pages by performing a binary search in
`min_values`. For unordered columns, a reader can find matching pages by
sequentially reading `min_values` and `max_values`.

Let T = (S, A, B) be a table with three columns. T is sorted on S and has a
ColumnIndex with `min_values` populated. Pseudocode for a full point lookup
with S = v looks like this:

    idx = lower_bound(S.column_index.min_values, v) // BinarySearch

    if idx = 0: return empty set

    page_offset := S.offset_index.page_locations[idx - 1].offset
    row := Find value in DataPage at page_offset using binary search

    For column c : (A, B):
      c_idx := lower_bound(c.offset_index.page_locations.first_row_index, row)
      c_page_offset := c.offset_index.page_locations[c_idx].offset
      c_row_offset := c.offset_index.page_locations[c_idx + 1].first_row_index - row
      c_value := file[c_page_offset + type_size(C) * c_row_offset]

For range scans this approach can be extended to return ranges of rows, page
indices, and page offsets to scan in each column. The reader can then
initialize a scanner for each column and fast forward them to the start row of
the scan.



