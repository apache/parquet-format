---
Author: Julien Le Dem
Created: 2025-Aug-7
Name: add BASE64 compression
Issue: https://github.com/apache/parquet-format/issues/NNN
Status: ARCHIVED
Reason: Did not compress
---

# Proposal

## Description
Add Base64 to compression algorithms.
This is not backwards compatible as a new compression alg.

## Spec

See [BASE64 spec].

## Evaluation

After trying out in the java implementation, file size doubled on average.
See prototype [here](github.com/julienledem/mypoc)

