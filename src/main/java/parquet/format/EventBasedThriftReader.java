package parquet.format;

import java.util.Collections;
import java.util.HashMap;
import java.util.Map;

import org.apache.thrift.TException;
import org.apache.thrift.TFieldIdEnum;
import org.apache.thrift.protocol.TField;
import org.apache.thrift.protocol.TList;
import org.apache.thrift.protocol.TMap;
import org.apache.thrift.protocol.TProtocol;
import org.apache.thrift.protocol.TSet;
import org.apache.thrift.protocol.TStruct;
import org.apache.thrift.protocol.TType;

public class EventBasedThriftReader {

  abstract public static class FieldEventConsumer {

    private RuntimeException error(short id) {
      return new IllegalArgumentException("id " + id + " was not expected");
    }

    public BoolEventConsumer getBoolEventConsumer(short id) {
      throw error(id);
    };
    public ByteEventConsumer getByteEventConsumer(short id) {
      throw error(id);
    };
    public DoubleEventConsumer getDoubleEventConsumer(short id) {
      throw error(id);
    };
    public I16EventConsumer getI16EventConsumer(short id) {
      throw error(id);
    };
    public I32EventConsumer getI32EventConsumer(short id) {
      throw error(id);
    };
    public ListEventConsumer getListEventConsumer(short id) {
      throw error(id);
    };
    public I64EventConsumer getI64EventConsumer(short id) {
      throw error(id);
    };
    public MapEventConsumer getMapEventConsumer(short id) {
      throw error(id);
    };
    public SetEventConsumer getSetEventConsumer(short id) {
      throw error(id);
    };
    public StringEventConsumer getStringEventConsumer(short id) {
      throw error(id);
    };
    public StructEventConsumer getStructEventConsumer(short id) {
      throw error(id);
    };

    public void addField(TProtocol protocol, EventBasedThriftReader reader, short id, byte type) throws TException {
      reader.readField(protocol, this, id, type);
    }

  }

  abstract public static class TypedEventConsumer {
    public final byte type;
    public final TFieldIdEnum id;
    protected TypedEventConsumer(byte type, TFieldIdEnum id) {
      this.type = type;
      this.id = id;
    }
  }
  abstract public static class DoubleEventConsumer extends TypedEventConsumer {
    protected DoubleEventConsumer(TFieldIdEnum e) {
      super(TType.DOUBLE, e);
    }
    abstract public void addDouble(double value);
  }
  abstract public static class ByteEventConsumer extends TypedEventConsumer {
    protected ByteEventConsumer(TFieldIdEnum e) {
      super(TType.BYTE, e);
    }
    abstract public void addByte(byte value);
  }
  abstract public static class BoolEventConsumer extends TypedEventConsumer {
    protected BoolEventConsumer(TFieldIdEnum e) {
      super(TType.BOOL, e);
    }
    abstract public void addBool(boolean value);
  }
  abstract public static class I32EventConsumer extends TypedEventConsumer {
    protected I32EventConsumer(TFieldIdEnum e) {
      super(TType.I32, e);
    }
    abstract public void addI32(int value);
  }
  abstract public static class I64EventConsumer extends TypedEventConsumer {
    protected I64EventConsumer(TFieldIdEnum e) {
      super(TType.I64, e);
    }
    abstract public void addI64(long value);
  }
  abstract public static class I16EventConsumer extends TypedEventConsumer {
    protected I16EventConsumer(TFieldIdEnum e) {
      super(TType.I16, e);
    }
    abstract public void addI16(short value);
  }
  abstract public static class StringEventConsumer extends TypedEventConsumer {
    protected StringEventConsumer(TFieldIdEnum e) {
      super(TType.STRING, e);
    }
    abstract public void addString(String value);
  }
  abstract public static class StructEventConsumer extends TypedEventConsumer {
    protected StructEventConsumer(TFieldIdEnum e) {
      super(TType.STRUCT, e);
    }

    abstract public void addStruct(
        TProtocol protocol, EventBasedThriftReader reader, TStruct tStruct) throws TException;
  }
  abstract public static class ListEventConsumer extends TypedEventConsumer {
    protected ListEventConsumer(TFieldIdEnum e) {
      super(TType.LIST, e);
    }

    public void addList(
        TProtocol protocol, EventBasedThriftReader reader, TList tList) throws TException {
      reader.readListContent(protocol, this, tList);
    }

    abstract public void addListElement(TProtocol protocol, EventBasedThriftReader reader, byte elemType) throws TException;
  }
  abstract public static class SetEventConsumer extends TypedEventConsumer {
    protected SetEventConsumer(TFieldIdEnum e) {
      super(TType.SET, e);
    }

    public void addSet(TProtocol protocol, EventBasedThriftReader reader, TSet tSet) throws TException {
      reader.readSetContent(protocol, this, tSet);
    }

    abstract public void addSetElement(TProtocol protocol, EventBasedThriftReader reader, byte elemType) throws TException;
  }
  abstract public static class MapEventConsumer extends TypedEventConsumer {
    protected MapEventConsumer(TFieldIdEnum e) {
      super(TType.MAP, e);
    }

    public void addMap(TProtocol protocol, EventBasedThriftReader reader, TMap tMap) throws TException {
      reader.readMapContent(protocol, this, tMap);
    }

    abstract public void addMapEntry(
        TProtocol protocol, EventBasedThriftReader reader,
        byte keyType, byte valueType) throws TException;
  }


  public static class DelegatingFieldEventConsumer extends FieldEventConsumer {
    private static class DelegateContext {

      private final TypedEventConsumer typedConsumer;
      private final FieldEventConsumer fieldConsumer;

      DelegateContext(TypedEventConsumer typedConsumer, FieldEventConsumer fieldConsumer) {
        super();
        this.typedConsumer = typedConsumer;
        this.fieldConsumer = fieldConsumer;
      }

      void validate(byte type) throws TException {
        if (typedConsumer.type != type) {
          throw new TException(
              "Incorrect type in stream for field " + typedConsumer.id.getFieldName() + ". "
                  + "Expected " + typedConsumer.type
                  + " but got " + type);
        }
      }

    }

    private final Map<Short, DelegateContext> contexts;

    private DelegatingFieldEventConsumer(Map<Short, DelegateContext> contexts) {
      this.contexts = Collections.unmodifiableMap(contexts);
    }

    public DelegatingFieldEventConsumer() {
      this.contexts = Collections.emptyMap();
    }

    public DelegatingFieldEventConsumer addContext(final StructEventConsumer consumer) {
      return this.addContext(consumer, new FieldEventConsumer() {
        @Override
        public StructEventConsumer getStructEventConsumer(short id) {
          return consumer;
        }
      });
    }

    public DelegatingFieldEventConsumer addContext(final I16EventConsumer consumer) {
      return this.addContext(consumer, new FieldEventConsumer() {
        @Override
        public I16EventConsumer getI16EventConsumer(short id) {
          return consumer;
        }
      });
    }

    public DelegatingFieldEventConsumer addContext(final I32EventConsumer consumer) {
      return this.addContext(consumer, new FieldEventConsumer() {
        @Override
        public I32EventConsumer getI32EventConsumer(short id) {
          return consumer;
        }
      });
    }

    public DelegatingFieldEventConsumer addContext(final I64EventConsumer consumer) {
      return this.addContext(consumer, new FieldEventConsumer() {
        @Override
        public I64EventConsumer getI64EventConsumer(short id) {
          return consumer;
        }
      });
    }

    public DelegatingFieldEventConsumer addContext(final StringEventConsumer consumer) {
      return this.addContext(consumer, new FieldEventConsumer() {
        @Override
        public StringEventConsumer getStringEventConsumer(short id) {
          return consumer;
        }
      });
    }

    public DelegatingFieldEventConsumer addContext(final ListEventConsumer consumer) {
      return this.addContext(consumer, new FieldEventConsumer() {
        @Override
        public ListEventConsumer getListEventConsumer(short id) {
          return consumer;
        }
      });
    }

    private DelegatingFieldEventConsumer addContext(TypedEventConsumer typedConsumer, FieldEventConsumer fieldConsumer) {
      Map<Short, DelegateContext> newContexts = new HashMap<Short, DelegateContext>(contexts);
      newContexts.put(typedConsumer.id.getThriftFieldId(), new DelegateContext(typedConsumer, fieldConsumer));
      return new DelegatingFieldEventConsumer(newContexts);
    }

    private DelegateContext getDelegate(short id) {
      return contexts.get(id);
    }

    public void addField(
        TProtocol protocol,
        EventBasedThriftReader reader,
        short id, byte type) throws TException {
      DelegateContext delegate = getDelegate(id);
      delegate.validate(type);
      reader.readField(protocol, delegate.fieldConsumer, id, type);
    }

  }

  public void readStruct(TProtocol protocol, FieldEventConsumer c) throws TException {
    protocol.readStructBegin();
    readStructContent(protocol, c);
    protocol.readStructEnd();
  }

  public void readField(TProtocol protocol, FieldEventConsumer c, short id, byte type) throws TException {
    switch (type) {
    case TType.BOOL:
      c.getBoolEventConsumer(id).addBool(protocol.readBool());
      break;
    case TType.BYTE:
      c.getByteEventConsumer(id).addByte(protocol.readByte());
      break;
    case TType.DOUBLE:
      c.getDoubleEventConsumer(id).addDouble(protocol.readDouble());
      break;
    case TType.ENUM:
      throw new UnsupportedOperationException("ENUM?"); // just int
//      addEnum(field.id, protocol.readEnum());
    case TType.I16:
      c.getI16EventConsumer(id).addI16(protocol.readI16());
      break;
    case TType.I32:
      c.getI32EventConsumer(id).addI32(protocol.readI32());
      break;
    case TType.I64:
      c.getI64EventConsumer(id).addI64(protocol.readI64());
      break;
    case TType.LIST:
      c.getListEventConsumer(id).addList(protocol, this, protocol.readListBegin());
      protocol.readListEnd();
      break;
    case TType.MAP:
      c.getMapEventConsumer(id).addMap(protocol, this, protocol.readMapBegin());
      protocol.readMapEnd();
      break;
    case TType.SET:
      c.getSetEventConsumer(id).addSet(protocol, this, protocol.readSetBegin());
      protocol.readSetEnd();
      break;
    case TType.STOP:
      throw new UnsupportedOperationException("STOP?");
    case TType.STRING:
      c.getStringEventConsumer(id).addString(protocol.readString());
      break;
    case TType.STRUCT:
      c.getStructEventConsumer(id).addStruct(protocol, this, protocol.readStructBegin());
      protocol.readStructEnd();
      break;
    default:
      throw new UnsupportedOperationException("Unknown type " + type + " for field " + id);
    }
  }

  public void readStructContent(TProtocol protocol, FieldEventConsumer c) throws TException {
    TField field;
    while (true) {
      field = protocol.readFieldBegin();
      if (field.type == TType.STOP) {
        break;
      }
      c.addField(protocol, this, field.id, field.type);
    }
  }

  public void readSetContent(
      TProtocol protocol, SetEventConsumer eventConsumer, TSet tSet) throws TException {
    for (int i = 0; i < tSet.size; i++) {
      eventConsumer.addSetElement(protocol, this, tSet.elemType);
    }
  }

  public void readMapContent(
      TProtocol protocol, MapEventConsumer eventConsumer, TMap tMap) throws TException {
    for (int i = 0; i < tMap.size; i++) {
      eventConsumer.addMapEntry(protocol, this, tMap.keyType, tMap.valueType);
    }
  }

  public void readListContent(
      TProtocol protocol, ListEventConsumer eventConsumer,
      TList tList) throws TException {
    for (int i = 0; i < tList.size; i++) {
      eventConsumer.addListElement(protocol, this, tList.elemType);
    }
  }

}
