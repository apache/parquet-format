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
---
Author: Julien Le Dem
Created: 2025-Aug-7
Name: add BASE64 compression
Issue: https://github.com/apache/parquet-format/issues/NNN
Status: ARCHIVED
Reason: Did not compress
---

# Proposal

**NOTE**: This is an example proposal for use as a template

## Description
Add Base64 to compression algorithms.
This is not backwards compatible as a new compression alg.

## Spec

See [BASE64 spec].

## Evaluation

After trying out in the java implementation, file size doubled on average.
See prototype [here](github.com/julienledem/mypoc)

