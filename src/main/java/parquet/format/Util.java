package parquet.format;

import static org.apache.thrift.protocol.TType.I32;
import static org.apache.thrift.protocol.TType.I64;
import static org.apache.thrift.protocol.TType.LIST;
import static org.apache.thrift.protocol.TType.STRING;
import static parquet.format.FileMetaData._Fields.CREATED_BY;
import static parquet.format.FileMetaData._Fields.KEY_VALUE_METADATA;
import static parquet.format.FileMetaData._Fields.NUM_ROWS;
import static parquet.format.FileMetaData._Fields.ROW_GROUPS;
import static parquet.format.FileMetaData._Fields.SCHEMA;
import static parquet.format.FileMetaData._Fields.VERSION;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.ArrayList;
import java.util.List;

import org.apache.thrift.TBase;
import org.apache.thrift.TException;
import org.apache.thrift.protocol.TCompactProtocol;
import org.apache.thrift.protocol.TField;
import org.apache.thrift.protocol.TList;
import org.apache.thrift.protocol.TProtocol;
import org.apache.thrift.protocol.TProtocolUtil;
import org.apache.thrift.protocol.TType;
import org.apache.thrift.transport.TIOStreamTransport;

import parquet.format.EventBasedThriftReader.*;

/**
 * Utility to read/write metadata
 * We use the TCompactProtocol to serialize metadata
 *
 * @author Julien Le Dem
 *
 */
public class Util {

  public static void writePageHeader(PageHeader pageHeader, OutputStream to) throws IOException {
    write(pageHeader, to);
  }

  public static PageHeader readPageHeader(InputStream from) throws IOException {
    return read(from, new PageHeader());
  }

  public static void writeFileMetaData(parquet.format.FileMetaData fileMetadata, OutputStream to) throws IOException {
    write(fileMetadata, to);
  }

  public static FileMetaData readFileMetaData(InputStream from) throws IOException {
    return read(from, new FileMetaData());
  }

  public static abstract class FileMetaDataObserver {

    abstract public void setVersion(int version);

    abstract public void setSchema(List<SchemaElement> schema);

    abstract public void setNumRows(long numRows);

    abstract public void addRowGroup(RowGroup rowGroup);

    abstract public void addKeyValueMetaData(KeyValue kv);

    abstract public void setCreatedBy(String createdBy);

  }

  public static void readFileMetaData(InputStream from, final FileMetaDataObserver observer) throws IOException {
    try {
      new EventBasedThriftReader().readStruct(protocol(from), new DelegatingFieldEventConsumer()
      .addContext(new I32EventConsumer(VERSION) {
        @Override
        public void addI32(int value) {
          observer.setVersion(value);
        }
      }).addContext(new ListEventConsumer(SCHEMA) {
        private List<SchemaElement> schema;
        @Override
        public void addList(TProtocol protocol, EventBasedThriftReader reader, TList tList) throws TException {
          this.schema = new ArrayList<SchemaElement>(tList.size);
          reader.readListContent(protocol, this, tList);
          observer.setSchema(this.schema);
        }

        @Override
        public void addListElement(
            TProtocol protocol, EventBasedThriftReader reader, byte elemType) throws TException {
          SchemaElement e = new SchemaElement();
          e.read(protocol);
          schema.add(e);
        }
      }).addContext(new I64EventConsumer(NUM_ROWS) {
        @Override
        public void addI64(long value) {
          observer.setNumRows(value);
        }
      }).addContext(new ListEventConsumer(KEY_VALUE_METADATA) {
        @Override
        public void addList(TProtocol protocol, EventBasedThriftReader reader, TList tList) throws TException {
          reader.readListContent(protocol, this, tList);
        }
        @Override
        public void addListElement(
            TProtocol protocol, EventBasedThriftReader reader, byte elemType) throws TException {
          KeyValue kv = new KeyValue();
          kv.read(protocol);
          observer.addKeyValueMetaData(kv);
        }
      }).addContext(new StringEventConsumer(CREATED_BY) {
        @Override
        public void addString(String value) {
          observer.setCreatedBy(value);
        }
      }).addContext(new ListEventConsumer(ROW_GROUPS) {
        @Override
        public void addList(TProtocol protocol, EventBasedThriftReader reader, TList tList) throws TException {
          reader.readListContent(protocol, this, tList);
        }
        @Override
        public void addListElement(TProtocol protocol, EventBasedThriftReader reader, byte elemType) throws TException {
          RowGroup e = new RowGroup();
          e.read(protocol);
          observer.addRowGroup(e);
        }
      }));

    } catch (TException e) {
      throw new IOException("can not read FileMetaData: " + e.getMessage(), e);
    }
  }

  private static TCompactProtocol protocol(OutputStream to) {
    return new TCompactProtocol(new TIOStreamTransport(to));
  }

  private static TCompactProtocol protocol(InputStream from) {
    return new TCompactProtocol(new TIOStreamTransport(from));
  }

  private static <T extends TBase<?,?>> T read(InputStream from, T tbase) throws IOException {
    try {
      tbase.read(protocol(from));
      return tbase;
    } catch (TException e) {
      throw new IOException("can not read " + tbase.getClass() + ": " + e.getMessage(), e);
    }
  }

  private static void write(TBase<?, ?> tbase, OutputStream to) throws IOException {
    try {
      tbase.write(protocol(to));
    } catch (TException e) {
      throw new IOException("can not write " + tbase, e);
    }
  }
}
