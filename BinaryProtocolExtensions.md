# Binary Protocol Extensions

The extension mechanism of the `binary` Thrift field-id `32767` has some desirable properties:

* Existing readers will ignore these extensions without any modifications  
* Existing readers will ignore the extension bytes with little processing overhead  
* The content of the extension is freeform and can be encoded in any format. This format is not restricted to Thrift.  
* Extensions can be appended to existing Thrift serialized structs [without requiring Thrift libraries](#appending-extensions-to-thrift) for manipulation (or changes to the thrift IDL).

Because only one field-id is reserved the extension bytes themselves require disambiguation; otherwise readers will not be able to decode extensions safely. This is left to implementers which MUST put enough unique state in their extension bytes for disambiguation. This can be relatively easily achieved by adding a [UUID](https://en.wikipedia.org/wiki/Universally\_unique\_identifier) at the start or end of the extension bytes. The extension does not specify a disambiguation mechanism to allow more flexibility to implementers.

Putting everything together in an example, if we would extend `FileMetaData` it would look like this on the wire.

    N-1 bytes | Thrift compact protocol encoded FileMetadata (minus \0 thrift stop field)
    4 bytes   | 08 FF FF 01 (long form header for 32767: binary)
    1-5 bytes | ULEB128(M) encoded size of the extension
    M bytes   | extension bytes
    1 byte    | \0 (thrift stop field)

The choice to reserve only one field-id has an additional (and frankly unintended) property. It creates scarcity in the extension space and disincentivizes vendors from keeping their extensions private. As a vendor having an extension means one cannot use it in tandem with other extensions from other vendors even if such extensions are publicly known. The easiest path of interoperability and ability to further experiment is to push an extension through standardization and continue experimenting with other ideas internally on top of the (now) standardized version.

#### Path to standardization

So far the above specification shows how different vendors can add extensions without stepping on each other's toes. As long as extensions are private this works out ok.

Unavoidably (and desirably) some extensions will make it into the official specification. Depending on the nature of the extension, migration can take different paths. While it is out of the scope of this document to design all such migrations, we illustrate some of these paths in the [examples](#examples).

## Examples

To illustrate the applicability of the extension mechanism we provide examples of fictional extensions to Parquet and how migration can play out if/when the community decides to adopt them in the official specification.

### Footer

A variant of `FileMetaData` encoded in Flatbuffers is introduced. This variant is more performant and can scale to very wide tables, something that current Thrift `FileMetaData` struggles with.

In its private form the footer of a Parquet file will look like so:

    N-1 bytes | Thrift compact protocol encoded FileMetadata (minus \0 thrift stop field)
    4 bytes   | 08 FF FF 01 (long form header for 32767: binary)
    1-5 bytes | ULEB128(K+28) encoded size of the extension
    K bytes   | Flatbuffers representation (v0) of FileMetaData
    4 bytes   | little-endian crc32(flatbuffer)
    4 bytes   | little-endian size(flatbuffer)
    4 bytes   | little-endian crc32(size(flatbuffer))
    16 bytes  | some-UUID
    1 byte    | \0 (thrift stop field)
    4 bytes   | PAR1

some-UUID is some UUID picked for this extension and it is used throughout (possibly internal) experimentation. It is put at the end to allow detection of the extension when parsed in reverse. The little-endian sizes and crc32s are also to the end to facilitate efficient parsing the footer in reverse without requiring parsing the Thrift compact protocol that precedes it.

At some point the experiments conclude and the extension shared publicly with the community. The extension is proposed for inclusion to the standard with a migration plan to replace the existing `FileMetaData`.

The community reviews the proposal and (potentially) proposes changes to the Flatbuffers IDL representation. In addition, because this extension is a *replacement* of an existing struct, it must:

1. have some way of being extended in the future much like what it replaces. Because the extension mechanism only allows for a single extension, without this in place we cannot have footer extensions during the migration.  
2. consider its intermediate form where both the **Thrift** `FileMetaData` and the **FlatBuffers** `FileMetaData` will be present.  
3. consider its final form where the long form header for `32767: binary` may not be present.

Once the design is ratified the new `FileMetaData` encoding is made final with the following migration plan. For the next N years writers will write both the Thrift and the flatbuffer `FileMetaData`. It will look much like its private form except the flatbuffer IDL may be different:

    N-1 bytes | Thrift compact protocol encoded FileMetadata (minus \0 thrift stop field)
    4 bytes   | 08 FF FF 01 (long form header for 32767: binary)
    1-5 bytes | ULEB128(K+28) encoded size of the extension
    K bytes   | Flatbuffers representation (v1) of FileMetaData
    4 bytes   | little-endian crc32(flatbuffer)
    4 bytes   | little-endian size(flatbuffer)
    4 bytes   | little-endian crc32(size(flatbuffer))
    16 bytes  | some-other-UUID
    1 byte    | \0 (thrift stop field)
    4 bytes   | PAR1

After the migration period, the end of the Parquet file may look like this:

    K bytes   | Flatbuffers representation (v1) of FileMetaData
    4 bytes   | little-endian crc32(flatbuffer)
    4 bytes   | little-endian size(flatbuffer)
    4 bytes   | little-endian crc32(size(flatbuffer))
    4 bytes   | PAR3

In this example, we see several design decisions for the extension at play:

* There is a new some-other-UUID for the accepted change to the standard and now the Thrift `FileMetaData` cannot be extended itself.  
* The length of the footer and the crc32 of the length itself, guarantees that new readers will not overshoot reading bytes in case of corrupt bits in these critical 8 bytes of the file.  
* The crc32 of the flatbuffer representation enhances Parquet to have crc32 for metadata as well which is arguably more important than crc32 for data.  
* The new encoding itself, which MUST contain some way to be extended in the future (much like Thrift does with this specification).

### Encoding

The community experiments with a new encoding extension. At the same time they want to keep the newly encoded Parquet files open for everyone to read. So they add a new encoding via an extension to the `ColumnMetaData` struct. The extension stores offsets in the Parquet file where the new and duplicate encoded data for this column lives. The new writer carefully places all the new encodings at the start of the row group and all the old encodings at the end of the row group. This layout minimizes disruption for readers unaware of the new encodings.

In its private form Parquet files look like so:

    4 bytes   | PAR1
              |             | Column b (new encoding)
              |             | Column c (new encoding)
    R bytes   |  Row Group  | Column a
              |     0       | Column d
              |             | Column b (old encoding)
              |             | Column c (old encoding)
              |             | FileMetaData
              |             | ColumnMetaData: a
              |             | ColumnMetaData: b
    F bytes   |             | <extension-blob with offsets to new encoding>
              |             | ColumnMetaData: c
              |             | <extension-blob with offsets to new encoding>
              |             | ColumnMetaData: d
    4 bytes   | PAR1

The custom reader is compiled with thrift IDL with a binary for field with id 32767. This is done to become extension aware and inspect the extension bytes looking for the UUID disambiguator. If that’s found it decodes the offsets from the rest of the bytes and reads the region of the file containing the new encoding.

If/when the encoding is ratified, it is added to the official specification as an additional type in `Encodings` at which point the extension is no longer necessary, nor the duplicated data in the row group.

## Appending extensions to thrift

```c++
void AppendUleb(uint32_t x, std::string* out) {
  while (true) {
    uint8_t c = x & 0x7F;
    if (x < 0x80) return out->push_back(c);
    out->push_back(c + 0x80);
    x >>= 7;
  }
};

std::string AppendExtension(std::string thrift, const std::string& ext) {
  thrift.back() = '\x08';      // replace stop field with binary type
  AppendUleb(32767, &thrift);  // field-id
  AppendUleb(ext.size(), &thrift);
  thrift += ext;
  thrift += '\x00';  // add the stop field
  return thrift;
}
```
