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

  public void readField(TProtocol protocol, TypedConsumerProvider p, short id, byte type) throws TException {
    switch (type) {
    case TType.BOOL:
      p.getBoolConsumer(id).addBool(protocol.readBool());
      break;
    case TType.BYTE:
      p.getByteConsumer(id).addByte(protocol.readByte());
      break;
    case TType.DOUBLE:
      p.getDoubleConsumer(id).addDouble(protocol.readDouble());
      break;
    case TType.ENUM:
      throw new UnsupportedOperationException("ENUM?"); // just int
//      addEnum(field.id, protocol.readEnum());
    case TType.I16:
      p.getI16Consumer(id).addI16(protocol.readI16());
      break;
    case TType.I32:
      p.getI32Consumer(id).addI32(protocol.readI32());
      break;
    case TType.I64:
      p.getI64Consumer(id).addI64(protocol.readI64());
      break;
    case TType.LIST:
      readList(protocol, p.getListConsumer(id));
      break;
    case TType.MAP:
      readMap(protocol, p.getMapConsumer(id));
      break;
    case TType.SET:
      readSet(protocol, p.getSetConsumer(id));
      break;
    case TType.STOP:
      throw new UnsupportedOperationException("STOP?");
    case TType.STRING:
      p.getStringConsumer(id).addString(protocol.readString());
      break;
    case TType.STRUCT:
      p.getStructConsumer(id).addStruct(protocol, this);
      break;
    default:
      throw new UnsupportedOperationException("Unknown type " + type + " for field " + id);
    }
  }

  public void readStruct(TProtocol protocol, FieldConsumer c) throws TException {
    protocol.readStructBegin();
    readStructContent(protocol, c);
    protocol.readStructEnd();
  }

  public void readStructContent(TProtocol protocol, FieldConsumer c) throws TException {
    TField field;
    while (true) {
      field = protocol.readFieldBegin();
      if (field.type == TType.STOP) {
        break;
      }
      c.addField(protocol, this, field.id, field.type);
    }
  }

  public void readSet(TProtocol protocol, SetConsumer setEventConsumer)
      throws TException {
    setEventConsumer.addSet(protocol, this, protocol.readSetBegin());
    protocol.readSetEnd();
  }

  public void readSetContent(TProtocol protocol, SetConsumer eventConsumer, TSet tSet)
      throws TException {
    for (int i = 0; i < tSet.size; i++) {
      eventConsumer.addSetElement(protocol, this, tSet.elemType);
    }
  }

  public void readMap(TProtocol protocol, MapConsumer mapEventConsumer)
      throws TException {
    mapEventConsumer.addMap(protocol, this, protocol.readMapBegin());
    protocol.readMapEnd();
  }

  public void readMapContent(TProtocol protocol, MapConsumer eventConsumer, TMap tMap)
      throws TException {
    for (int i = 0; i < tMap.size; i++) {
      eventConsumer.addMapEntry(protocol, this, tMap.keyType, tMap.valueType);
    }
  }

  public void readList(TProtocol protocol, ListConsumer listEventConsumer)
      throws TException {
    listEventConsumer.addList(protocol, this, protocol.readListBegin());
    protocol.readListEnd();
  }

  public void readListContent(TProtocol protocol, ListConsumer eventConsumer, TList tList)
      throws TException {
    for (int i = 0; i < tList.size; i++) {
      eventConsumer.addListElement(protocol, this, tList.elemType);
    }
  }
}