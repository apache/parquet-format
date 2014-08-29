package parquet.format.event;

import org.apache.thrift.TException;
import org.apache.thrift.protocol.TField;
import org.apache.thrift.protocol.TList;
import org.apache.thrift.protocol.TMap;
import org.apache.thrift.protocol.TProtocol;
import org.apache.thrift.protocol.TSet;
import org.apache.thrift.protocol.TType;

import parquet.format.event.TypedConsumer.ListConsumer;
import parquet.format.event.TypedConsumer.MapConsumer;
import parquet.format.event.TypedConsumer.SetConsumer;

/**
 * Event based reader for Thrift
 *
 * @author Julien Le Dem
 *
 */
public final class EventBasedThriftReader {

  private final TProtocol protocol;

  /**
   * @param protocol the protocol to read from
   */
  public EventBasedThriftReader(TProtocol protocol) {
    this.protocol = protocol;
  }

  /**
   * Reads the content of a field from the underlying protocol.
   * gets the TypedConsumer corresponding to the provided type and passes the value.
   * @param p the Typed Consumer Provider to pass the value to
   * @param type the type of the field
   * @throws TException
   */
  public void readElement(TypedConsumer c, byte type) throws TException {
    c.read(protocol, this);
  }

  /**
   * reads a Struct from the underlying protocol and passes the field events to the FieldConsumer
   * @param c the field consumer
   * @throws TException
   */
  public void readStruct(FieldConsumer c) throws TException {
    protocol.readStructBegin();
    readStructContent(c);
    protocol.readStructEnd();
  }

  /**
   * reads the content of a struct (fields) from the underlying protocol and passes the events to c
   * @param c the field consumer
   * @throws TException
   */
  public void readStructContent(FieldConsumer c) throws TException {
    TField field;
    while (true) {
      field = protocol.readFieldBegin();
      if (field.type == TType.STOP) {
        break;
      }
      c.addField(protocol, this, field.id, field.type);
    }
  }

  /**
   * reads the set content (elements) from the underlying protocol and passes the events to the set event consumer
   * @param eventConsumer the consumer
   * @param tSet the set descriptor
   * @throws TException
   */
  public void readSetContent(SetConsumer eventConsumer, TSet tSet)
      throws TException {
    for (int i = 0; i < tSet.size; i++) {
      eventConsumer.addSetElement(protocol, this, tSet.elemType);
    }
  }

  /**
   * reads the map content (key values) from the underlying protocol and passes the events to the map event consumer
   * @param eventConsumer the consumer
   * @param tMap the map descriptor
   * @throws TException
   */
  public void readMapContent(MapConsumer eventConsumer, TMap tMap)
      throws TException {
    for (int i = 0; i < tMap.size; i++) {
      eventConsumer.addMapEntry(protocol, this, tMap.keyType, tMap.valueType);
    }
  }

  /**
   * reads the list content (elements) from the underlying protocol and passes the events to the list event consumer
   * @param eventConsumer the consumer
   * @param tList the list descriptor
   * @throws TException
   */
  public void readListContent(ListConsumer eventConsumer, TList tList)
      throws TException {
    for (int i = 0; i < tList.size; i++) {
      eventConsumer.addListElement(protocol, this, tList.elemType);
    }
  }
}