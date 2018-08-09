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

# Parquet Modular Encryption

Parquet files, containing sensitive information, can be protected by the modular
encryption mechanism, that encrypts and authenticates the file data and metadata - 
while allowing for a regular Parquet functionality (columnar projection, 
predicate pushdown, encoding and compression). The mechanism also enables column access 
control, via support for encryption of different columns with different keys.

## Problem Statement
The existing data protection solutions (such as flat encryption of files, in-storage 
encryption, or a use of an encrypting storage client) can be applied to Parquet files,
but have various security or performance issues. An encryption mechanism, integrated in
the Parquet format, allows for an optimal combination of data security, processing
speed and access control granularity.


## Goals
1. Protect Parquet data and metadata by encryption, while enabling selective reads 
(columnar projection, predicate push-down).
2. Implement "client-side" encryption/decryption (storage client). The storage server 
must not see a plaintext data, metadata or the encryption keys.
3. Leverage authenticated encryption that allows clients to check integrity of the 
retrieved data - making sure the file (or file parts) had not been replaced with a 
wrong version, or tampered with otherwise.
4. Support column access control - by enabling different encryption keys for different 
columns, and for the footer.
5. Allow for partial encryption - encrypt only column(s) with sensitive data.
6. Work with all compression and encoding mechanisms supported in Parquet.
7. Support multiple encryption algorithms, to account for different security and 
performance requirements.


## Non-Goals
* Key management
Keys, arbitrary key metadata and key retrieval callbacks are provided to Parquet API as input 
parameters. Key storage, DEK encryption with KEK (data- and key-encryption keys), re-keying 
etc, are out of scope and should be done above Parquet. Parquet accepts explicit keys, and 
also provides tools to store key metadata inside the file (upon encryption), and to call 
key retrieval callbacks with this metadata (upon decryption).



## Technical Approach

Each Parquet module (footer, page headers, pages, column indexes, column metadata) is 
encrypted separately. Then it is possible to fetch and decrypt the footer, find the 
offset of a required page, fetch it and decrypt the data. In this document, the term 
“footer” always refers to the regular Parquet footer - the `FileMetaData` structure, and 
its nested fields (`RowGroup`s / `ColumnChunk`s).

The results of compression of column pages are encrypted, before being written to the 
output stream. A new Thrift structure, with a column crypto metadata, is added to 
`ColumnChunk`s of the encrypted columns. This metadata provides information about the 
column encryption keys.

The results of Thrift serialization of metadata structures are encrypted, before being 
written to the output stream.

A new Thrift structure, with a file crypto metadata,  is written after the (encrypted) 
Parquet footer, at the end of the file. This structure is not encrypted. It provides 
information about the footer encryption key, the algorithm used to encrypt the file, etc.

## Encryption algorithms

Parquet encryption algorithms are based on the standard AES ciphers for symmetric encryption. 
AES is supported in Intel and other CPUs with hardware acceleration of 
crypto operations (“AES-NI”) - that can be leveraged by e.g. Java programs (automatically 
via HotSpot), or C++ programs (via EVP-* functions in OpenSSL).

Initially, two algorithms are implemented, one based on AES-GCM cipher, and the other on a 
combination of AES-GCM and AES-CTR ciphers.

AES-GCM is an authenticated encryption. Besides the data confidentiality (encryption), it 
supports two levels of integrity verification / authentication: of the data (default), and 
of the data combined with an optional AAD (“additional authenticated data”). The default 
authentication allows to make sure the data has not been tampered with. An AAD is a free 
text to be signed, together with the data. The user can, for example, pass the file name 
with its version (or creation timestamp) as the AAD, to verify the file has not been 
replaced with an older version.

Sometimes, a hardware acceleration of AES is unavialable (e.g. in Java 8). Then AES crypto 
operations are implemented in software, and can be somewhat slow, becoming a performance 
bottleneck in certain workloads. AES-CTR is a regular (not authenticated) cipher.  
It is faster than AES-GCM, since it doesn’t perform integrity verification and doesn’t 
calculate the authentication tag. For applications running without AES acceleration and 
willing to compromise on content verification, AES-CTR can provide a boost in Parquet 
writing/reading throughput. The second Parquet algorithm encrypts the data content (pages) 
with AES-CTR, and the metadata (Thrift structures) with AES-GCM. This allows to encrypt/decrypt 
the bulk of the data faster, while still verifying the metadata integrity and making sure 
the file had not been replaced with a wrong version. However, tampering with the page data 
might go unnoticed. 


### AES_GCM_V1
All modules are encrypted with the AES-GCM cipher. The authentication tags (16 bytes) are 
written after each ciphertext. The IVs (12 bytes) are either written before each ciphertext, 
or split into two parts: a fixed part (n bytes) written in the FileCryptoMetaData structure 
(iv_prefix field), and a variable part (12-n bytes: counter, random, etc) written before 
each ciphertext.

### AES_GCM_CTR_V1
Thrift modules are encrypted with the AES-GCM cipher, as described before. The pages are 
encrypted with AES-CTR, where the IVs (16 bytes) are either written before each ciphertext, 
or split into two parts: a fixed part (n bytes) written in the FileCryptoMetaData structure 
(iv_prefix field), and a variable part (16-n bytes: counter, random, etc) written before 
each ciphertext.



## File Format

The encrypted Parquet files have a different magic string (“PARE”), and an extension 
(“parquet.encrypted”).

The encryption is flexible - each column and the footer can encrypted with the same key, 
with a different key, or not encrypted at all.

The metadata structures (`FileMetaData`, `PageHeader`, `ColumnIndex`; and sometimes 
`ColumnMetaData`, see below) are encrypted after Thrift serialization. For each structure, 
the encryption buffer is comprised of an IV, ciphertext and tag, as described in the 
Algorithms section. The length of the encryption buffer (a 4-byte little endian) is 
written to the output stream, followed by the buffer itself.

The column pages (data and dictionary) are encrypted after compression. For each page, 
the encryption buffer is comprised of an IV, ciphertext and (in case of AES_GCM_V1) of a 
tag, as described in the Algorithms section. Only the buffer is written to the output 
stream - not need to write the length of the buffer, since the length is kept in the page 
headers.

A `crypto_meta_data` field in set in each `ColumnChunk` in the encrypted columns. 
`ColumnCryptoMetaData` is a union, the actual structure is chosen depending on whether the 
column is encrypted with the footer key, or with a column-specific key. For the latter, 
a key metadata can be specified, with a maximal length of 256.

Parquet file footer, and its nested structures, contain sensitive information - ranging 
from a secret data (column statistics) to other information that can be exploited by an 
attacker (e.g. schema, num_values, key_value_metadata, column encoding and crypto_meta_data). 
This information is automatically protected when the footer and secret columns are encrypted 
with the same key. In other cases - when column(s) and the footer are encrypted with 
different keys; or column(s) are encrypted and the footer is not - an extra measure is 
required to protect the column-specific information in the file footer. In these cases, 
the column-specific information (kept in `ColumnMetaData` structures) is split from the 
footer, by utilizing the existing `required i64 file_offset` parameter in the `ColumnChunk` 
structure, and ignoring the `optional ColumnMetaData meta_data` parameter in the same 
structure. This allows to serialize each `ColumnMetaData` structure separately, and encrypt 
it with a column-specific key, thus protecting the column stats and other metadata. 

The crypto metadata of columns is also protected, with the footer key, since it is set 
in the `ColumnChunk`s that are a part of the footer. For example, the footer information 
on which columns are plaintext and which are encrypted, with what key, etc - is invisible 
without a footer key. 

In files with sensitive column data, a good security practice is to encrypt not only the 
secret columns, but also the file footer, with a separate footer key. To recap, this hides
the file schema, number of rows, key-value properties, column names, column sort order, 
list of encrypted columns and metadata of the column encryption keys.

A Thrift-serialized `FileCryptoMetaData` structure is written after the footer, and contains 
information on the file encryption algorithm, on the footer (encrypted or not; offset in 
the file; optional key metadata, with a maximal length of 256) and the IV prefix. Then 
the length of this structure is written, as a 4-byte little endian integer. Then the final 
magic string.

Only the `FileCryptoMetaData` is written as a plaintext, all other file parts are encrypted 
(as needed) with appropriate keys.
