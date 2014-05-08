# Parquet #

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
