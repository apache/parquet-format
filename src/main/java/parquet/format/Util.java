package parquet.format;

import static parquet.format.FileMetaData._Fields.CREATED_BY;
import static parquet.format.FileMetaData._Fields.KEY_VALUE_METADATA;
import static parquet.format.FileMetaData._Fields.NUM_ROWS;
import static parquet.format.FileMetaData._Fields.ROW_GROUPS;
import static parquet.format.FileMetaData._Fields.SCHEMA;
import static parquet.format.FileMetaData._Fields.VERSION;
import static parquet.format.event.Consumers.fieldConsumer;
import static parquet.format.event.Consumers.listElementsOf;
import static parquet.format.event.Consumers.listOf;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.List;

import org.apache.thrift.TBase;
import org.apache.thrift.TException;
import org.apache.thrift.protocol.TCompactProtocol;
import org.apache.thrift.transport.TIOStreamTransport;

import parquet.format.event.Consumers;
import parquet.format.event.Consumers.Consumer;
import parquet.format.event.EventBasedThriftReader;
import parquet.format.event.TypedConsumer.I32Consumer;
import parquet.format.event.TypedConsumer.I64Consumer;
import parquet.format.event.TypedConsumer.StringConsumer;

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

  public static void readFileMetaData(InputStream from, FileMetaDataObserver observer) throws IOException {
    readFileMetaData(from, observer, false);
  }

  private static final EventBasedThriftReader eventBasedThriftReader = new EventBasedThriftReader();

  public static void readFileMetaData(InputStream from, final FileMetaDataObserver observer, boolean skipRowGroups) throws IOException {
    try {
      Consumers.DelegatingFieldConsumer eventConsumer = fieldConsumer()
      .onField(VERSION, new I32Consumer() {
        @Override
        public void addI32(int value) {
          observer.setVersion(value);
        }
      }).onField(SCHEMA, listOf(SchemaElement.class, new Consumer<List<SchemaElement>>() {
        @Override
        public void add(List<SchemaElement> schema) {
          observer.setSchema(schema);
        }
      })).onField(NUM_ROWS, new I64Consumer() {
        @Override
        public void addI64(long value) {
          observer.setNumRows(value);
        }
      }).onField(KEY_VALUE_METADATA, listElementsOf(KeyValue.class, new Consumer<KeyValue>() {
        @Override
        public void add(KeyValue kv) {
          observer.addKeyValueMetaData(kv);
        }
      })).onField(CREATED_BY, new StringConsumer() {
        @Override
        public void addString(String value) {
          observer.setCreatedBy(value);
        }
      });
      if (!skipRowGroups) {
        eventConsumer = eventConsumer.onField(ROW_GROUPS, listElementsOf(RowGroup.class, new Consumer<RowGroup>() {
          @Override
          public void add(RowGroup rowGroup) {
            observer.addRowGroup(rowGroup);
          }
        }));
      }
      eventBasedThriftReader.readStruct(protocol(from), eventConsumer);

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
