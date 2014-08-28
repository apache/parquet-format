package parquet.format.event;

import static org.apache.thrift.protocol.TType.BOOL;
import static org.apache.thrift.protocol.TType.BYTE;
import static org.apache.thrift.protocol.TType.DOUBLE;
import static org.apache.thrift.protocol.TType.I16;
import static org.apache.thrift.protocol.TType.I32;
import static org.apache.thrift.protocol.TType.I64;
import static org.apache.thrift.protocol.TType.LIST;
import static org.apache.thrift.protocol.TType.MAP;
import static org.apache.thrift.protocol.TType.SET;
import static org.apache.thrift.protocol.TType.STRING;
import static org.apache.thrift.protocol.TType.STRUCT;

import org.apache.thrift.TException;
import org.apache.thrift.protocol.TList;
import org.apache.thrift.protocol.TMap;
import org.apache.thrift.protocol.TProtocol;
import org.apache.thrift.protocol.TSet;

/**
 * receive thrift events of a given type
 *
 * @author Julien Le Dem
 *
 */
abstract public class TypedConsumer {
  abstract public static class DoubleConsumer extends TypedConsumer {
    protected DoubleConsumer() { super(DOUBLE); }
    abstract public void addDouble(double value);
  }
  abstract public static class ByteConsumer extends TypedConsumer {
    protected ByteConsumer() { super(BYTE); }
    abstract public void addByte(byte value);
  }
  abstract public static class BoolConsumer extends TypedConsumer {
    protected BoolConsumer() { super(BOOL); }
    abstract public void addBool(boolean value);
  }
  abstract public static class I32Consumer extends TypedConsumer {
    protected I32Consumer() { super(I32); }
    abstract public void addI32(int value);
  }
  abstract public static class I64Consumer extends TypedConsumer {
    protected I64Consumer() { super(I64); }
    abstract public void addI64(long value);
  }
  abstract public static class I16Consumer extends TypedConsumer {
    protected I16Consumer() { super(I16); }
    abstract public void addI16(short value);
  }
  abstract public static class StringConsumer extends TypedConsumer {
    protected StringConsumer() { super(STRING); }
    abstract public void addString(String value);
  }
  abstract public static class StructConsumer extends TypedConsumer {
    protected StructConsumer() { super(STRUCT); }
    /**
     * can either delegate to the reader or read the struct from the protocol
     * reader.readStruct(fieldConsumer);
     * @param protocol the underlying protocol
     * @param reader the reader to delegate to
     * @throws TException
     */
    abstract public void addStruct(TProtocol protocol, EventBasedThriftReader reader) throws TException;
  }
  abstract public static class ListConsumer extends TypedConsumer {
    protected ListConsumer() { super(LIST); }
    public void addList(TProtocol protocol, EventBasedThriftReader reader, TList tList) throws TException {
      reader.readListContent(this, tList);
    }
    /**
     * can either delegate to the reader or read the list from the protocol
     * reader.readElement(typedConsumerProvider, elemType);
     * @param protocol the underlying protocol
     * @param reader the reader to delegate to
     * @throws TException
     */
    abstract public void addListElement(TProtocol protocol, EventBasedThriftReader reader, byte elemType) throws TException;
  }
  abstract public static class SetConsumer extends TypedConsumer {
    protected SetConsumer() { super(SET); }
    public void addSet(TProtocol protocol, EventBasedThriftReader reader, TSet tSet) throws TException {
      reader.readSetContent(this, tSet);
    }
    /**
     * can either delegate to the reader or read the set from the protocol
     * reader.readElement(typedConsumerProvider, elemType);
     * @param protocol the underlying protocol
     * @param reader the reader to delegate to
     * @throws TException
     */
    abstract public void addSetElement(
        TProtocol protocol, EventBasedThriftReader reader,
        byte elemType) throws TException;
  }
  abstract public static class MapConsumer extends TypedConsumer {
    protected MapConsumer() { super(MAP); }
    public void addMap(TProtocol protocol, EventBasedThriftReader reader, TMap tMap) throws TException {
      reader.readMapContent(this, tMap);
    }
    /**
     * can either delegate to the reader or read the map from the protocol
     * reader.readElement(keyTypedConsumerProvider, keyType);
     * reader.readElement(valueTypedConsumerProvider, valueType);
     * @param protocol the underlying protocol
     * @param reader the reader to delegate to
     * @throws TException
     */
    abstract public void addMapEntry(
        TProtocol protocol, EventBasedThriftReader reader,
        byte keyType, byte valueType) throws TException;
  }

  public final byte type;
  private TypedConsumer(byte type) {
    this.type = type;
  }
}