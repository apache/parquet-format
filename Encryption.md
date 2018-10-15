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
must not see plaintext data, metadata or encryption keys.
3. Leverage authenticated encryption that allows clients to check integrity of the 
retrieved data - making sure the file (or file parts) had not been replaced with a 
wrong version, or tampered with otherwise.
4. Support column access control - by enabling different encryption keys for different 
columns, and for the footer.
5. Allow for partial encryption - encrypt only column(s) with sensitive data.
6. Work with all compression and encoding mechanisms supported in Parquet.
7. Support multiple encryption algorithms, to account for different security and 
performance requirements.
8. Enable two modes for metadata protection:
   * full protection of file metadata
   * partial protection of file metadata, that allows legacy readers to access unencrypted 
 columns in an encrypted file.
9. Miminize overhead of encryption: in terms of size of encrypted files, and throughput
of write/read operations.


## Technical Approach

Each Parquet module (footer, page headers, pages, column indexes, column metadata) is 
encrypted separately. Then it is possible to fetch and decrypt the footer, find the 
offset of a required page, fetch it and decrypt the data. In this document, the term 
“footer” always refers to the regular Parquet footer - the `FileMetaData` structure, and 
its nested fields (row groups / column chunks).

The results of compression of column pages are encrypted, before being written to the 
output stream. A new Thrift structure, with a column crypto metadata, is added to 
column chunks of the encrypted columns. This metadata provides information about the 
column encryption keys.

The results of Thrift serialization of metadata structures are encrypted, before being 
written to the output stream.

## Encryption algorithms

Parquet encryption algorithms are based on the standard AES ciphers for symmetric 
encryption. AES is supported in Intel and other CPUs with hardware acceleration of 
crypto operations (“AES-NI”) - that can be leveraged by e.g. Java programs 
(automatically via HotSpot), or C++ programs (via EVP-* functions in OpenSSL).

Initially, two algorithms are implemented, one based on a GCM mode of AES, and the other 
on a combination of GCM and CTR modes.

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
write/read throughput. The second Parquet algorithm encrypts the data content (pages) 
with AES-CTR, and the metadata (Thrift structures) with AES-GCM. This allows to encrypt/decrypt 
the bulk of the data faster, while still verifying the metadata integrity and making sure 
the file had not been replaced with a wrong version. However, tampering with the page data 
might go unnoticed. 

The `AesGcmV1` and `AesGcmCtrV1` structures contain an optional `aad_metadata` field that can 
be used by a reader to retrieve the AAD string used for file encryption. The maximal allowed
length of `aad_metadata` is 512 bytes.

Parquet-mr/-cpp implementations use the RBG-based IV construction as defined in the NIST 
SP 800-38D document for the GCM ciphers (section 8.2.2).


### AES_GCM_V1
All modules are encrypted with the AES-GCM cipher. The authentication tags (16 bytes) are 
written after each ciphertext. The IVs (12 bytes) are written before each ciphertext.

### AES_GCM_CTR_V1
Thrift modules are encrypted with the AES-GCM cipher, as described above. 
The pages are encrypted with AES-CTR, where the IVs (16 bytes) are written before each 
ciphertext.


## File Format

The encrypted Parquet files have a different extension - “.parquet.encrypted”.

The encryption is flexible - each column and the footer can be encrypted with the same key, 
with a different key, or not encrypted at all.

The metadata structures (`PageHeader`, `ColumnIndex`, `OffsetIndex`; and sometimes `FileMetaData` and 
`ColumnMetaData`, see below) are encrypted after Thrift serialization. For each structure, 
the encryption buffer is comprised of an IV, ciphertext and tag, as described in the 
Algorithms section. The length of the encryption buffer (a 4-byte little endian) is 
written to the output stream, followed by the buffer itself.

The column pages (data and dictionary) are encrypted after compression. For each page, 
the encryption buffer is comprised of an IV, ciphertext and (in case of AES_GCM_V1) of a 
tag, as described in the Algorithms section. Only the buffer is written to the output 
stream - not need to write the length of the buffer, since the length (size of the page after
compression and encryption) is kept in the page headers.

A `crypto_meta_data` field in set in each `ColumnChunk` in the encrypted columns. 
`ColumnCryptoMetaData` is a union - the actual structure is chosen depending on whether the 
column is encrypted with the footer key, or with a column-specific key. For the latter, 
a key metadata can be specified, with a maximal length of 512. Key metadata is a free-form
byte array that can be used by a reader to retrieve the column encryption key. 

Parquet file footer, and its nested structures, contain sensitive information - ranging 
from a secret data (column statistics) to other information that can be exploited by an 
attacker (e.g. schema, num_values, key_value_metadata, column data offset and size, encoding and crypto_meta_data). 
This information is automatically protected when the footer and secret columns are encrypted 
with the same key. In other cases - when column(s) and the footer are encrypted with 
different keys; or column(s) are encrypted and the footer is not - an extra measure is 
required to protect the column-specific information in the file footer. In these cases, 
the column-specific information (kept in `ColumnMetaData` structures) is split from the 
footer, by utilizing the `required i64 file_offset` parameter in the `ColumnChunk` 
structure. This allows to serialize each `ColumnMetaData` structure separately, and encrypt 
it with a column-specific key, thus protecting the column stats and other metadata. 

### Encrypted footer mode

In files with sensitive column data, a good security practice is to encrypt not only the 
secret columns, but also the file footer metadata, with a separate footer key. This hides
the file schema / column names, number of rows, key-value properties, column sort order, 
column data offset and size, list of encrypted columns and metadata of the column encryption keys. 
It also makes the footer tamper-proof.

The columns encrypted with the same key as the footer, don't split the ColumnMetaData from the 
ColumnChunks, leaving it at the original location, `optional ColumnMetaData meta_data`. This field
is not set for columns enrypted with a column-specific key.

A Thrift-serialized `FileCryptoMetaData` structure is written after the footer. It contains 
information on the file encryption algorithm and on the footer (offset in 
the file, and an optional key metadata, with a maximal length of 512). Then 
the length of this structure is written, as a 4-byte little endian integer. Then a final 
magic string, "PARE".

Only the `FileCryptoMetaData` is written as a plaintext, all other file parts are protected
(as needed) with appropriate keys.

 ![File Layout - Encrypted footer](doc/images/FileLayoutEncryptionEF.jpg)

### Plaintext footer mode

This mode allows legacy Parquet versions (released before the encryption support) to access unencrypted 
columns in encrypted files - at a price of leaving certain metadata fields unprotected in these files 
(not encrypted or tamper-proofed). The plaintext footer mode can be useful during a transitional period 
in organizations 
where some frameworks can't be upgraded to a new Parquet library for a while. Data writers will
upgrade and run with a new Parquet version, producing encrypted files in this mode. Data readers, 
working with a sensitive data, will also upgrade to a new Parquet library. But other readers that
don't need the sensitive columns, can continue working with an older Parquet version. They will be 
able to access plaintext columns in encrypted files. A legacy reader, trying to access a sensitive 
column data in a ".parquet.encrypted" file with a plaintext footer, will get an  exception. More
specifically, a Thrift parsing exception on an encrypted `PageHeader` structure. Again, using legacy
Parquet readers for encrypted files is a temporary solution.

In the plaintext footer mode, the `optional ColumnMetaData meta_data` is set in the `ColumnChunk` 
structure for all columns, but is stripped of the statistics for the sensitive (encrypted) columns. 
These statistics are available for new readers with the column key - they fetch the split ColumnMetaData, 
and decrypt it to get all metadata values. The legacy readers are not aware of the split metadata, 
they parse the embedded field as usual. While they can't read the data of the encrypted columns, they 
read the metadata to exract the offset and size of the column data - required for input vectorization
(see the next section).

An `encryption_algorithm` field is set at the FileMetaData structure. Then the footer is written as usual, 
followed by its length (4-byte little endian integer) and a final magic string, "PAR1".

 ![File Layout: Plaintext footer](doc/images/FileLayoutEncryptionPF.jpg)


### New fields for vectorized readers

Apache Spark and other vectorized readers slice a file by using the information on offset
and size of each row group. In the legacy readers, this is done by running over a list of all column chunks
in a row group, reading the relevant information from the column metadata, adding up the size values
and picking the offset of the first column as the row group offset. However, vectorization
needs only a row group metadata, not metadata of individual columns. Also, in files written in an
encrypted footer mode, the column metadata is not available to readers without the column key. Therefore, 
two new fields are added to the
`RowGroup` structure - `file_offset` and `total_compressed_size` - that are set upon file
writing, and allow vectorized readers to query a file even if keys to certain columns are
not available ('hidden columns'). Naturally, the query itself should not try to access the 
hidden column data.

## Encryption overhead

The size overhead of Parquet modular encryption is negligible, since the most of the encryption 
operations are performed on pages (the minimal unit of Parquet data storage and compression). The
overhead order of magnitude is adding ~ 1 byte per each 10,000 bytes of original data.

The throughput overhead of Parquet modular encryption depends on whether AES enciphering is done
in software or hardware. In both cases, performing encryption on full pages (~1MB buffers) instead of
on much smaller individual data values causes AES to work at its maximal speed. Preliminary tests
show Parquet modular encryption throughput overhead to be up to a few percents in Java 9 workloads.
