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

Parquet files containing sensitive information can be protected by the modular encryption 
mechanism that encrypts and authenticates the file data and metadata - while allowing 
for a regular Parquet functionality (columnar projection, predicate pushdown, encoding 
and compression). 

## 1. Problem Statement
Existing data protection solutions (such as flat encryption of files, in-storage encryption, 
or use of an encrypting storage client) can be applied to Parquet files, but have various 
security or performance issues. An encryption mechanism, integrated in the Parquet format, 
allows for an optimal combination of data security, processing speed and encryption  
granularity.

## 2. Goals
1. Protect Parquet data and metadata by encryption, while enabling selective reads 
(columnar projection, predicate push-down).
2. Implement "client-side" encryption/decryption (storage client). The storage server 
must not see plaintext data, metadata or encryption keys.
3. Leverage authenticated encryption that allows clients to check integrity of the retrieved 
data - making sure the file (or file parts) have not been replaced with a wrong version, or 
tampered with otherwise.
4. Enable different encryption keys for different columns and for the footer.
5. Allow for partial encryption - encrypt only column(s) with sensitive data.
6. Work with all compression and encoding mechanisms supported in Parquet.
7. Support multiple encryption algorithms, to account for different security and performance 
requirements.
8. Enable two modes for metadata protection -
   * full protection of file metadata
   * partial protection of file metadata that allows legacy readers to access unencrypted 
columns in an encrypted file.
9.	Minimize overhead of encryption - in terms of size of encrypted files, and throughput 
of write/read operations.


## 3. Technical Approach
Parquet files are comprised of separately serialized components: page headers, pages, column 
indexes, offset indexes, a footer. Parquet encryption mechanism denotes them as “modules” 
and encrypts each module separately – making it possible to fetch and decrypt the footer, 
find the offset of required pages, fetch the pages and decrypt the data. In this document, 
the term “footer” always refers to the regular Parquet footer - the `FileMetaData` structure, 
and its nested fields (row groups / column chunks).

The results of compression of column pages are encrypted before being written to the output 
stream. A new Thrift structure, with column crypto metadata, is added to column chunks of 
the encrypted columns. This metadata provides information about the column encryption keys.
The results of Thrift serialization of metadata structures are encrypted, before being written 
to the output stream. 

File encryption is flexible - each column and the footer can be encrypted with the same key, 
with a different key, or not encrypted at all.

The file footer can be either encrypted or left as a plaintext. In an encrypted footer mode, 
a new Thrift structure with file crypto metadata is added to the file. This metadata provides 
information about the file encryption algorithm and the footer encryption key. 

In a plaintext footer mode, the contents of the `FileMetaData` structure is visible, but it can 
be optionally signed with a footer key in order to verify its integrity. The `FileMetaData` keeps
the file encryption algorithm, the footer signing key description and a flag indicating whether 
a footer signature is added to the file.

For encrypted columns, the following modules are always encrypted, with the same column key: 
pages and  `PageHeader`s (both dictionary and data), `ColumnIndex`s, `OffsetIndex`s.  If the 
column key is different from the footer key, the `ColumnMetaData` structure is also encrypted 
for this column. 


## 4. Encryption Algorithms and Keys
Parquet encryption algorithms are based on the standard AES ciphers for symmetric encryption. 
AES is supported in Intel and other CPUs with hardware acceleration of crypto operations 
(“AES-NI”) - that can be leveraged, for example, by Java programs (automatically via HotSpot), 
or C++ programs (via EVP-* functions in OpenSSL). Parquet supports all standard AES key sizes: 
128, 192 and 256 bits. 

Initially, two algorithms have been implemented, one based on a GCM mode of AES, and the 
other on a combination of GCM and CTR modes.

AES GCM is an authenticated encryption. Besides the data confidentiality (encryption), it 
supports two levels of integrity verification (authentication): of the data (default), 
and of the data combined with an optional AAD (“additional authenticated data”). The 
default authentication allows to make sure the data has not been tampered with. An AAD 
is a free text to be signed, together with the data. The user can, for example, pass the 
file name with its version (or creation timestamp) as an AAD input, to verify that the 
file has not been replaced with an older version. The details of AAD creation and usage are 
provided in the section 4.4.

Sometimes, a hardware acceleration of AES is unavailable (e.g. in Java 8). Then AES crypto 
operations are implemented in software, and can be somewhat slow, becoming a performance 
bottleneck in certain workloads. AES CTR is a regular (not authenticated) cipher. It is 
faster than GCM cipher, since it doesn’t perform integrity verification and doesn’t 
calculate the authentication tag. Actually, GCM is a combination of CTR cipher and an 
authentication layer  called GMAC. For applications running without AES acceleration 
and willing to compromise on content verification, CTR cipher can provide a boost in 
Parquet write/read throughput. The second Parquet algorithm encrypts the data content 
(pages) with CTR, and the metadata (Thrift structures) with GCM. This allows to encrypt/decrypt 
the bulk of the data faster, while still verifying the metadata integrity and making 
sure the file has not been replaced with a wrong version. However, tampering with the 
page data might go unnoticed.

The initialization vectors (IVs) in GCM and CTR ciphers must be unique for each encrypted 
stream. The CTR IVs are comprised of two parts: a unique nonce (“number used once”) and 
an initial counter field; both must be passed to the CTR cipher upon stream initialization. 
The GCM creates a CTR cipher internally, and passes an IV comprised of a nonce (passed to 
the GCM cipher upon stream initialization) and an initial counter field constructed internally 
by the GCM cipher according to the GCM specification (NIST SP 800-38D).
Parquet encryption uses the RBG-based (random bit generator) nonce construction as defined in 
the NIST SP 800-38D document, section 8.2.2. Notice: the NIST SP 800-38D specifies the GCM 
cipher and uses a term “IV” for what is called “nonce” in the Parquet encryption design.

An input to AES CTR encryption is an encryption key, a 16-byte IV and a plaintext. The output
is a ciphertext with the length equal to that of plaintext (for non-padding encryption).

An input to AES GCM encryption is an encryption key, a 12-byte nonce and a plaintext. The output
is a ciphertext with the length equal to that of plaintext (for non-padding encryption), and 
a 16-byte authentication tag used to verify the ciphertext integrity.


### 4.1 AES_GCM_V1 encryption algorithm
This Parquet algorithm encrypts all modules by the GCM cipher, without padding. The details of
no-padding encryption are provided in the Appendix section. Unique 
nonces are generated for each ciphertext. The nonce length is 12 bytes (96 bits). The NIST 
specification requires a “random field” to fill all 12 bytes and an arbitrary “free field” 
to be empty for this nonce length (section 8.2.2). Parquet uses the option 1 for RGB implementation - 
"The random field shall .. consist of an output string of r(i) bits from an approved RBG with a 
sufficient security strength". That is, a fresh random field must be generated for each nonce - 
as opposed to the option 2 in the same spec - "or the result of applying the r(i)–bit incrementing 
function to the random field of the preceding <nonce> for the given key"


### 4.2 AES_GCM_CTR_V1 encryption algorithm
In this Parquet algorithm, all Thrift modules are encrypted with the GCM cipher, as described above. 

The pages are encrypted by a CTR cipher without padding. Unique nonces are generated for 
each ciphertext, with the nonce length of 12 bytes. All 12 bytes are constructed with an 
RBG option 1 as described for the AES_GCM_V1 algorithm. The module encryption and decryption 
is performed with a 16 byte IV comprised of the nonce and a 4-byte initial counter field. The 
first 31 bits of the initial counter field are set to 0, the last bit is set to 1. 

### 4.3 Encryption key metadata
A wide variety of services and tools for management of encryption keys exist in the 
industry today. Public clouds offer different key management services (KMS), and 
organizational IT systems either build proprietary key managers in-house or adopt open source 
tools for on-premises deployment. Besides the diversity of management tools, there are many 
ways to generate and handle the keys themselves (generate Data keys inside KMS – or locally 
upon data encryption; use Data keys only, or use Master keys to encrypt/wrap the Data keys; 
store the wrapped key material inside the data file, or at a separate location; etc). There 
is also a large variety of authorization and certification methods, required to control the 
access to encryption keys.

Parquet is not limited to a single KMS, key generation/wrapping method, or authorization service. 
Instead, Parquet provides a developer with a simple interface (key_metadata byte array, and a 
key retrieval callback) that can be utilized for implementation of any key management scheme. 
For example, the key_metadata can keep a serialized

   * String ID of a Data encryption key (for direct key retrieval from a KMS).
   * Wrapped Data key, and string ID of a Master key. The Data key is generated randomly and 
   wrapped either remotely in a KMS, or locally after retrieving the Master key from KMS. Wrapping 
   format depends on the KMS and can be a JSON string, or a base64 encoded byte array in a case of 
   local wrapping.
   * Short ID (counter) of a key inside the Parquet data file. The Data key is wrapped with a 
   Master key using one of the options described above – but the resulting key material is stored 
   separately, outside the data file, and will be retrieved using the counter and file path.
   * Any of the three above, plus a string ID of the KMS instance (in case there are many).
   * Random string - useful for creation of footer keys in organizations not willing to authenticate 
   and connect all readers to a KMS. The footer key is generated as F(key_metadata), where F is an 
   algorithm unknown outside organization. These keys are less secure than KMS-managed keys, but 
   better than using no keys at all in plaintext footers, see a discussion in the sections 5.3 and 5.4.
   Key metadata can also be empty - in a case the encryption keys are fully managed by the caller 
   code, and passed explicitly to Parquet for the footer and each encrypted column.

### 4.4 Additional Authenticated Data
The AES GCM cipher in the basic mode protects against byte replacement inside a ciphertext, 
but can't prevent replacement of one ciphertext with another (encrypted with the same key). 
This can be solved by the AAD mode, using different AADs for different ciphertexts. Parquet 
modular encryption uses the AAD mode to protect against swapping ciphertext modules inside 
a file, between files - or against swapping full files (for example, replacement of a file 
with an old version). Obviously, the AAD must reflect the identity of a file and of the modules 
inside the file.

Parquet constructs a module AAD from two components: an optional AAD_Prefix - a string provided 
by the user for the file, and an AAD_Suffix, built internally for each GCM-encrypted module 
inside the file. The AAD prefix should reflect the target identity that helps to detect file 
swapping (simple example - table name with a date and partition), e.g., "employees_23_05_2018.part0"). 
The AAD suffix reflects the internal identity of modules inside the file, which for example 
prevents replacement of column pages in row group 0 by pages from the same column in row 
group 1 (when columns are encrypted with the CGM cipher). The module AAD is a direct concatenation 
of the prefix and suffix parts.

#### 4.4.1 AAD_Prefix
A file writer passes an optional AAD_Prefix string upon file creation, that allows to differentiate 
it from other files and datasets. The reader should know this string apriori, or should be able to 
retrieve and verify it, using a convention accepted in the organization. An optional aad_metadata 
can be specified in a file - to help a reader retrieve the AAD 
prefix string used for file enciphering. The aad_metadata  field can be empty, since readers might 
know apriori a right AAD_Prefix for each file. Alternatively, the aad_metadata  can contain hints 
that help readers to get the right AAD prefix. Yet another option is to keep the AAD_Prefix itself 
inside the aad_metadata field – in that case, the readers must be able to verify it independently, 
since this field is not protected in a storage, and can be changed or filled by an attacker.

Here go a number of examples of AAD_Prefix creation and management in an organization:

   * An organization uses a convention is to build an AAD_Prefix from the table name/ID, date and 
   a partition . For example, a writer of a May 23 version of an employee table will use 
   "employees_23_05_2018.partN" as an AAD prefix (and as the file name) for each table file. 
   The reader that needs to process the May 23 table, knows the AAD must be "employees_23_05_2018.partN" 
   in each corresponding table file. This approach doesn’t use the aad_metadata field.
   * A similar convention, but the date format (and other details) can be variable. Then the 
   format is kept in aad_metadata field, for example as "MM_DD_YY.partitionN". The reader will 
   know the AAD prefixes are "employees_05_23_18.partition0" etc.
   * The aad_metadata field contains the AAD prefix itself. In this case, the reader must be able 
   to verify its validity. For example, if the AAD prefix stored in aad_metadata is "employees_23May2018.part0001", 
   the reader should know it is fine, but if the aad_metadata stores "employees_23May2016.part0001" - 
   the version is wrong.
   * The AAD_Prefix is generated as a random string. Together with a file name, it is sent by the file 
   writer to a trusted metadata service, deployed in the organization. The reader, that needs to parse a 
   certain version of a table, authenticates the service and gets the list of table files and their AAD prefixes.
   * Frameworks above Parquet create table integrity tools that manage the file AAD prefixes. For example, 
   a framework table writer can create a signature file that contains the table ID, file list/number and 
   the file AAD prefixes. The AAD prefixes can be either explicit (eg random) or derived from 
   the table ID and file name/number. The signature file is signed with a secret key (private or symmetric), and 
   stored next to the table files, or in another location known to the readers. The 
   readers get the public or symmetric key, verify the signature file and get the AAD prefixes for the table files 
   (potentially, along with file names/paths).
   
#### 4.4.2 AAD_Suffix
Sometimes, a number of encrypted columns have their file offset either directly visible or possible to 
infer from other metadata. This might be exploited for attacks on file integrity - such as replacement 
of column pages in row group 0 by pages from the same column in row group 1. Also, if an encryption 
key is re-used in multiple files and the user has not provided a unique AAD_Prefix for each file – an 
attacker can swap modules between the files. While these attacks succeed under rare conditions and in 
any case don't harm data confidentiality - they can be prevented by using an internally generated file 
and module identity as a part of GCM AAD formation in Parquet. 

The AAD_Suffix is built by direct concatenation of the following parts: 
1.	[All modules] random byte array (file identifier): variable length
2.	[All modules] module type: 1 byte
3.	[All modules except footer] row group ordinal: 2 byte short (little endian)
4.	[All modules except footer] column name ordinal: 2 byte short (little endian)
5.	[Data page and header only]: page ordinal: 2 byte short (little endian)

The following module types are defined:  

   * Footer (0)
   * ColumnMetaData (1)
   * Data Page (2)
   * Dictionary Page (3)
   * Data PageHeader (4)
   * Dictionary PageHeader (5)
   * ColumnIndex (6)
   * IndexOffset (7)


|                      |File ID     | Module type | Row group ordinal | Column ordinal | Page ordinal|
|----------------------|------------|-------------|-------------------|----------------|-------------|
| Footer               |     V      |    V (0)    |         X         |       X        |      X      |
| ColumnMetaData       |     V      |    V (1)    |         V         |       V        |      X      |
| Data Page            |     V      |    V (2)    |         V         |       V        |      V      |
| Dictionary Page      |     V      |    V (3)    |         V         |       V        |      X      |
| Data PageHeader      |     V      |    V (4)    |         V         |       V        |      V      |
| Dictionary PageHeader|     V      |    V (5)    |         V         |       V        |      X      |
| ColumnIndex          |     V      |    V (6)    |         V         |       V        |      X      |
| IndexOffset          |     V      |    V (7)    |         V         |       V        |      X      |



## 5. File Format
Parquet file encryption algorithm is specified in a union of the following Thrift structures:

```c
struct AesGcmV1 {
  /** Retrieval metadata of AAD prefix **/
  1: optional binary aad_metadata

  /** Unique file identifier part of AAD suffix **/
  2: optional binary aad_file_unique
}

struct AesGcmCtrV1 {
  /** Retrieval metadata of AAD prefix **/
  1: optional binary aad_metadata

  /** Unique file identifier part of AAD suffix **/
  2: optional binary aad_file_unique
}

union EncryptionAlgorithm {
  1: AesGcmV1 AES_GCM_V1
  2: AesGcmCtrV1 AES_GCM_CTR_V1
}
```
 

The metadata structures: `PageHeader`, `ColumnIndex`, `ColumnMetaData`, `OffsetIndex` and `FileMetaData`  
are encrypted after Thrift serialization with the GCM cipher. For each structure, the encryption 
buffer is comprised of a nonce, ciphertext and tag, described in the Algorithms section. The column pages 
(data and dictionary) are encrypted after compression. With the AES_GCM_V1 algorithm, a page encryption 
buffer is comprised of a nonce, ciphertext and tag. The length of the encryption buffer 
(a 4-byte little endian) is written to the output stream, followed by the buffer itself.

|length (4 bytes) | nonce (12 bytes) | ciphertext (length-28 bytes) | tag (16 bytes) |
|-----------------|------------------|------------------------------|----------------|


With the AES_GCM_CTR_V1 algorithm, a page encryption buffer is comprised of a nonce and ciphertext, 
described in the Algorithms section. The length of the encryption buffer 
(a 4-byte little endian) is written to the output stream, followed by the buffer itself.

|length (4 bytes) | nonce (12 bytes) | ciphertext (length-12 bytes) |
|-----------------|------------------|------------------------------|


A `crypto_meta_data` field is set in each ColumnChunk in the encrypted columns. ColumnCryptoMetaData 
is a union - the actual structure is chosen depending on whether the column is encrypted with the 
footer key, or with a column-specific key. For the latter, a key metadata can be specified.

```c
struct EncryptionWithFooterKey {
}

struct EncryptionWithColumnKey {
  /** Column path in schema **/
  1: required list<string> path_in_schema
  
  /** Retrieval metadata of the column-specific key **/
  2: optional binary column_key_metadata
}

union ColumnCryptoMetaData {
  1: EncryptionWithFooterKey ENCRYPTION_WITH_FOOTER_KEY
  2: EncryptionWithColumnKey ENCRYPTION_WITH_COLUMN_KEY
}

struct ColumnChunk {
...
  /** Crypto metadata of encrypted columns **/
  8: optional ColumnCryptoMetaData crypto_meta_data
}
```

The row group ordinal, required for AAD_Suffix calculation, is set in the RowGroup structure:

```c
struct RowGroup {
...
  /** Row group ordinal in the file **/
  7: optional i16 ordinal
}
```

### 5.1 Protection of column metadata
The Parquet file footer, and its nested structures, contain sensitive information - ranging 
from a secret data (column statistics) to other information that can be exploited by an 
attacker (e.g. schema, num_values, key_value_metadata, column data offset and size, encoding 
and crypto_meta_data). This information is automatically protected when the footer and 
secret columns are encrypted with the same key. In other cases - when column(s) and the 
footer are encrypted with different keys; or column(s) are encrypted and the footer is not, 
an extra measure is required to protect the column-specific information in the file footer. 
In these cases, the `ColumnMetaData` structures are Thrift-serialized separately and encrypted 
 with the AES GCM cipher and a column-specific key, thus protecting the column stats and 
 other metadata. The encrypted buffer is kept in an `optional binary encrypted_column_metadata` 
 field in the `ColumnChunk`.

```c
struct ColumnChunk {
...
  
  /** Column metadata for this chunk.. **/
  3: optional ColumnMetaData meta_data
..

  /** Encrypted column metadata for this chunk **/
  9: optional binary encrypted_column_metadata
}
```


### 5.2 Encrypted footer mode
In files with sensitive column data, a good security practice is to encrypt not only the 
secret columns, but also the file footer metadata. This hides the file schema / column names, 
number of rows, key-value properties, column sort order, information on encrypted columns 
(name, data offset, data size) and metadata of the column encryption keys. 

The columns encrypted with the same key as the footer leave the column metadata at the original 
location, `optional ColumnMetaData meta_data` in the `ColumnChunk` structure.  
This field is not set for columns encrypted with a column-specific key - instead, the `ColumnMetaData`
is encrypted with the column key, and written to the `encrypted_column_metadata` field in the
`ColumnChunk` structure, as described in the section 5.1.

A Thrift-serialized `FileCryptoMetaData` structure is written before the encrypted footer. 
It contains information on the file encryption algorithm and on the footer key metadata. Then 
the combined length of this structure and of the encrypted footer is written as a 4-byte 
little endian integer, followed by a final magic string, "PARE". The same magic bytes are 
written at the beginning of the file (offset 0). Parquet readers start file parsing by 
reading and checking the magic string. Therefore, the encrypted footer mode uses a new 
magic string ("PARE") in order to instruct readers to look for a file crypto metadata 
at the end of the file - and also to immediately inform legacy readers (expecting ‘PAR1’ 
bytes) that they can’t parse this file.

```c
/** Crypto metadata for files with encrypted footer **/
struct FileCryptoMetaData {
  /** 
   * Encryption algorithm. Note that this field is only used for files
   * with encrypted footer. Files with plaintext footer store the algorithm id
   * inside footer (FileMetaData structure).
   */
  1: required EncryptionAlgorithm encryption_algorithm
    
  /** Retrieval metadata of key used for encryption of footer, 
   *  and (possibly) columns **/
  2: optional binary footer_key_metadata
}
```

<!-- 
 ![File Layout - Encrypted footer](doc/images/FileLayoutEncryptionEF.jpg)
   -->
 
 
### 5.3 Plaintext footer mode
This mode allows legacy Parquet versions (released before the encryption support) to access 
unencrypted columns in encrypted files - at a price of leaving certain metadata fields 
unprotected in these files. 

The plaintext footer mode can be useful during a transitional period in organizations where 
some frameworks can't be upgraded to a new Parquet library for a while. Data writers will 
upgrade and run with a new Parquet version, producing encrypted files in this mode. Data 
readers working with sensitive data will also upgrade to a new Parquet library. But other 
readers that don't need the sensitive columns, can continue working with an older Parquet 
version. They will be able to access plaintext columns in encrypted files. A legacy reader, 
trying to access a sensitive column data in an encrypted file with a plaintext footer, will 
get an exception. More specifically, a Thrift parsing exception on an encrypted page header  
structure. Again, using legacy Parquet readers for encrypted files is a temporary solution.

In the plaintext footer mode, the `optional ColumnMetaData meta_data` is set in the `ColumnChunk`
structure for all columns, but is stripped of the statistics for the sensitive (encrypted) 
columns. These statistics are available for new readers with the column key - they decrypt 
the `encrypted_column_metadata` field, described in the section 5.1, and parse it to get statistics 
and all other metadata values. The legacy readers are not aware of the encrypted metadata field; 
they parse the regular (plaintext) field as usual. While they can't read the data of the encrypted 
columns, they read the metadata to extract the offset and size of the column data - required for 
input vectorization (see the section 5.4).

The plaintext footer can be signed with a footer key in order to prevent tampering with the 
`FileMetaData` contents.  

The plaintext footer mode sets the following fields in the the FileMetaData structure:

```c
struct FileMetaData {
...
  /** 
   * Encryption algorithm. Note that this field is set only in encrypted files
   * with plaintext footer. Files with encrypted footer store the algorithm id
   * in FileCryptoMetaData structure.
   */
  8: optional EncryptionAlgorithm encryption_algorithm

  /** 
   * Set only for encrypted files with a plaintext footer. 
   * true if footer signature is written in the file. 
   */
  9: optional bool signed_footer

  /** 
   * Retrieval metadata of key used for signing the footer. 
   * Set only for encrypted files with a plaintext and signed footer. 
   */ 
  10: optional binary footer_signing_key_metadata
}
```
 
The `FileMetaData` structure is Thrift-serialized and written to the output stream.

The footer signing is done by encrypting the serialized `FileMetaData` structure with the 
AES GCM algorithm - using the footer key, and an AAD constructed according to the instructions 
of the section 4.4. Only the nonce and GCM tag are stored in the file – as a 28-byte 
fixed-length array, written right after  the footer itself. The ciphertext is not stored, 
because it is not required for footer integrity verification by readers.

| nonce (12 bytes) |  tag (16 bytes) |
|------------------|-----------------|


The plaintext footer and an optional signature are followed by a 4-byte little endian integer 
that contains either footer length, or a combined length of the footer and its 28-byte 
signature if the footer is signed. A final magic string, "PAR1", is written at the end of the 
file. The same magic string is written at the beginning of the file (offset 0). The magic bytes 
for plaintext footer mode are ‘PAR1’ to allow legacy readers to read projections of the file 
that do not include encrypted columns.

<!-- 
 ![File Layout - Encrypted footer](doc/images/FileLayoutEncryptionPF.jpg)
   -->

 
### 5.4 New fields for vectorized readers
Apache Spark and other vectorized readers slice a file by using information on the offset 
and size of each row group. In the legacy readers, this is done by running over a list of 
all column chunks in a row group, reading the relevant information from the column metadata, 
adding up the size values and picking the offset of the first column as the row group offset. 
However, vectorization needs only a row group metadata, and not the metadata of individual 
columns. Also, in files written in an encrypted footer mode, the column metadata is not 
available to readers without the column key. Therefore, two new fields are added to the 
`RowGroup` structure - `file_offset` and `total_compressed_size` that are set upon file writing, 
and allow vectorized readers to query a file even if keys to certain columns are not 
available ('hidden columns'). Naturally, the query itself should not try to access the 
hidden column data.

```c
struct RowGroup {
...
  /** Byte offset from beginning of file to first page (data or dictionary)
   * in this row group **/
  5: optional i64 file_offset

  /** Total byte size of all compressed (and potentially encrypted) column data 
   *  in this row group **/
  6: optional i64 total_compressed_size
}
```

## 6. Encryption Overhead
The size overhead of Parquet modular encryption is negligible, since most of the encryption 
operations are performed on pages (the minimal unit of Parquet data storage and compression). 
The overhead order of magnitude is adding 1 byte per each ~30,000 bytes of original compressed 
data.

The throughput overhead of Parquet modular encryption depends on whether AES enciphering is 
done in software or hardware. In both cases, performing encryption on full pages (~1MB buffers) 
instead of on much smaller individual data values causes AES to work at its maximal speed. 
Preliminary tests show Parquet modular encryption throughput overhead to be up to a few 
percents in Java 9 workloads.


## Appendix: No Padding Encryption 

<place holder, will fill on Sunday>

```c
val last_key_block = ...
val last_ciphertext_block = new byte[last_block.length]
for (i in range(0, last_block.length)) {
  last_ciphertext_block[i] = last_key_block[i] ^ last_block[i];
}
```
