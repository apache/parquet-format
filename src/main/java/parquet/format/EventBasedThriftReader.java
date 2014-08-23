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
import org.apache.thrift.protocol.TProtocolUtil;
import org.apache.thrift.protocol.TSet;
import org.apache.thrift.protocol.TStruct;
import org.apache.thrift.protocol.TType;

public class EventBasedThriftReader {

  abstract public static class TypedConsumerProvider {
    private RuntimeException error(short id) {
      return new IllegalArgumentException("id " + id + " was not expected");
    }
    public BoolConsumer getBoolEventConsumer(short id) {
      throw error(id);
    };
    public ByteConsumer getByteEventConsumer(short id) {
      throw error(id);
    };
    public DoubleConsumer getDoubleEventConsumer(short id) {
      throw error(id);
    };
    public I16Consumer getI16EventConsumer(short id) {
      throw error(id);
    };
    public I32Consumer getI32EventConsumer(short id) {
      throw error(id);
    };
    public ListConsumer getListEventConsumer(short id) {
      throw error(id);
    };
    public I64Consumer getI64EventConsumer(short id) {
      throw error(id);
    };
    public MapConsumer getMapEventConsumer(short id) {
      throw error(id);
    };
    public SetConsumer getSetEventConsumer(short id) {
      throw error(id);
    };
    public StringConsumer getStringEventConsumer(short id) {
      throw error(id);
    };
    public StructConsumer getStructEventConsumer(short id) {
      throw error(id);
    };
  }

  public static class SkippingFieldConsumer implements FieldConsumer {
    public void addField(TProtocol protocol, EventBasedThriftReader reader, short id, byte type) throws TException {
      TProtocolUtil.skip(protocol, type);
    }
  }

  public static interface FieldConsumer {
    public void addField(TProtocol protocol, EventBasedThriftReader reader, short id, byte type) throws TException;
  }

  abstract public static class TypedConsumer {
    public final byte type;
    public final TFieldIdEnum id;
    protected TypedConsumer(byte type, TFieldIdEnum id) {
      this.type = type;
      this.id = id;
    }
  }
  abstract public static class DoubleConsumer extends TypedConsumer {
    protected DoubleConsumer(TFieldIdEnum e) {
      super(TType.DOUBLE, e);
    }
    abstract public void addDouble(double value);
  }
  abstract public static class ByteConsumer extends TypedConsumer {
    protected ByteConsumer(TFieldIdEnum e) {
      super(TType.BYTE, e);
    }
    abstract public void addByte(byte value);
  }
  abstract public static class BoolConsumer extends TypedConsumer {
    protected BoolConsumer(TFieldIdEnum e) {
      super(TType.BOOL, e);
    }
    abstract public void addBool(boolean value);
  }
  abstract public static class I32Consumer extends TypedConsumer {
    protected I32Consumer(TFieldIdEnum e) {
      super(TType.I32, e);
    }
    abstract public void addI32(int value);
  }
  abstract public static class I64Consumer extends TypedConsumer {
    protected I64Consumer(TFieldIdEnum e) {
      super(TType.I64, e);
    }
    abstract public void addI64(long value);
  }
  abstract public static class I16Consumer extends TypedConsumer {
    protected I16Consumer(TFieldIdEnum e) {
      super(TType.I16, e);
    }
    abstract public void addI16(short value);
  }
  abstract public static class StringConsumer extends TypedConsumer {
    protected StringConsumer(TFieldIdEnum e) {
      super(TType.STRING, e);
    }
    abstract public void addString(String value);
  }
  abstract public static class StructConsumer extends TypedConsumer {
    protected StructConsumer(TFieldIdEnum e) {
      super(TType.STRUCT, e);
    }

    abstract public void addStruct(
        TProtocol protocol, EventBasedThriftReader reader, TStruct tStruct) throws TException;
  }
  abstract public static class ListConsumer extends TypedConsumer {
    protected ListConsumer(TFieldIdEnum e) {
      super(TType.LIST, e);
    }

    public void addList(
        TProtocol protocol, EventBasedThriftReader reader, TList tList) throws TException {
      reader.readListContent(protocol, this, tList);
    }

    abstract public void addListElement(TProtocol protocol, EventBasedThriftReader reader, byte elemType) throws TException;
  }
  abstract public static class SetConsumer extends TypedConsumer {
    protected SetConsumer(TFieldIdEnum e) {
      super(TType.SET, e);
    }

    public void addSet(TProtocol protocol, EventBasedThriftReader reader, TSet tSet) throws TException {
      reader.readSetContent(protocol, this, tSet);
    }

    abstract public void addSetElement(TProtocol protocol, EventBasedThriftReader reader, byte elemType) throws TException;
  }
  abstract public static class MapConsumer extends TypedConsumer {
    protected MapConsumer(TFieldIdEnum e) {
      super(TType.MAP, e);
    }

    public void addMap(TProtocol protocol, EventBasedThriftReader reader, TMap tMap) throws TException {
      reader.readMapContent(protocol, this, tMap);
    }

    abstract public void addMapEntry(
        TProtocol protocol, EventBasedThriftReader reader,
        byte keyType, byte valueType) throws TException;
  }

  public static class DelegatingFieldConsumer implements FieldConsumer {
    private static class DelegateContext {

      private final TypedConsumer typedConsumer;
      private final TypedConsumerProvider provider;

      DelegateContext(TypedConsumer typedConsumer, TypedConsumerProvider provider) {
        super();
        this.typedConsumer = typedConsumer;
        this.provider = provider;
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
    private final FieldConsumer defaultFieldEventConsumer;

    private DelegatingFieldConsumer(FieldConsumer defaultFieldEventConsumer, Map<Short, DelegateContext> contexts) {
      this.defaultFieldEventConsumer = defaultFieldEventConsumer;
      this.contexts = Collections.unmodifiableMap(contexts);
    }

    public DelegatingFieldConsumer() {
      this(new SkippingFieldConsumer());
    }

    public DelegatingFieldConsumer(FieldConsumer defaultFieldEventConsumer) {
      this(defaultFieldEventConsumer, Collections.<Short, DelegateContext>emptyMap());
    }

    public DelegatingFieldConsumer addContext(final DoubleConsumer consumer) {
      return this.addContext(consumer, new TypedConsumerProvider() {
        @Override
        public DoubleConsumer getDoubleEventConsumer(short id) {
          return consumer;
        }
      });
    }
    public DelegatingFieldConsumer addContext(final ByteConsumer consumer) {
      return this.addContext(consumer, new TypedConsumerProvider() {
        @Override
        public ByteConsumer getByteEventConsumer(short id) {
          return consumer;
        }
      });
    }
    public DelegatingFieldConsumer addContext(final BoolConsumer consumer) {
      return this.addContext(consumer, new TypedConsumerProvider() {
        @Override
        public BoolConsumer getBoolEventConsumer(short id) {
          return consumer;
        }
      });
    }
    public DelegatingFieldConsumer addContext(final StructConsumer consumer) {
      return this.addContext(consumer, new TypedConsumerProvider() {
        @Override
        public StructConsumer getStructEventConsumer(short id) {
          return consumer;
        }
      });
    }
    public DelegatingFieldConsumer addContext(final I16Consumer consumer) {
      return this.addContext(consumer, new TypedConsumerProvider() {
        @Override
        public I16Consumer getI16EventConsumer(short id) {
          return consumer;
        }
      });
    }
    public DelegatingFieldConsumer onField(final I32Consumer consumer) {
      return this.addContext(consumer, new TypedConsumerProvider() {
        @Override
        public I32Consumer getI32EventConsumer(short id) {
          return consumer;
        }
      });
    }
    public DelegatingFieldConsumer onField(final I64Consumer consumer) {
      return this.addContext(consumer, new TypedConsumerProvider() {
        @Override
        public I64Consumer getI64EventConsumer(short id) {
          return consumer;
        }
      });
    }
    public DelegatingFieldConsumer onField(final StringConsumer consumer) {
      return this.addContext(consumer, new TypedConsumerProvider() {
        @Override
        public StringConsumer getStringEventConsumer(short id) {
          return consumer;
        }
      });
    }
    public DelegatingFieldConsumer onField(final ListConsumer consumer) {
      return this.addContext(consumer, new TypedConsumerProvider() {
        @Override
        public ListConsumer getListEventConsumer(short id) {
          return consumer;
        }
      });
    }
    public DelegatingFieldConsumer addContext(final SetConsumer consumer) {
      return this.addContext(consumer, new TypedConsumerProvider() {
        @Override
        public SetConsumer getSetEventConsumer(short id) {
          return consumer;
        }
      });
    }
    public DelegatingFieldConsumer addContext(final MapConsumer consumer) {
      return this.addContext(consumer, new TypedConsumerProvider() {
        @Override
        public MapConsumer getMapEventConsumer(short id) {
          return consumer;
        }
      });
    }

    private DelegatingFieldConsumer addContext(TypedConsumer typedConsumer, TypedConsumerProvider fieldConsumer) {
      Map<Short, DelegateContext> newContexts = new HashMap<Short, DelegateContext>(contexts);
      newContexts.put(typedConsumer.id.getThriftFieldId(), new DelegateContext(typedConsumer, fieldConsumer));
      return new DelegatingFieldConsumer(defaultFieldEventConsumer, newContexts);
    }

    private DelegateContext getDelegate(short id) {
      return contexts.get(id);
    }

    public void addField(
        TProtocol protocol,
        EventBasedThriftReader reader,
        short id, byte type) throws TException {
      DelegateContext delegate = getDelegate(id);
      if (delegate != null) {
        delegate.validate(type);
        reader.readField(protocol, delegate.provider, id, type);
      } else {
        defaultFieldEventConsumer.addField(protocol, reader, id, type);
      }
    }

  }

  public void readStruct(TProtocol protocol, FieldConsumer c) throws TException {
    protocol.readStructBegin();
    readStructContent(protocol, c);
    protocol.readStructEnd();
  }

  public void readField(TProtocol protocol, TypedConsumerProvider p, short id, byte type) throws TException {
    switch (type) {
    case TType.BOOL:
      p.getBoolEventConsumer(id).addBool(protocol.readBool());
      break;
    case TType.BYTE:
      p.getByteEventConsumer(id).addByte(protocol.readByte());
      break;
    case TType.DOUBLE:
      p.getDoubleEventConsumer(id).addDouble(protocol.readDouble());
      break;
    case TType.ENUM:
      throw new UnsupportedOperationException("ENUM?"); // just int
//      addEnum(field.id, protocol.readEnum());
    case TType.I16:
      p.getI16EventConsumer(id).addI16(protocol.readI16());
      break;
    case TType.I32:
      p.getI32EventConsumer(id).addI32(protocol.readI32());
      break;
    case TType.I64:
      p.getI64EventConsumer(id).addI64(protocol.readI64());
      break;
    case TType.LIST:
      p.getListEventConsumer(id).addList(protocol, this, protocol.readListBegin());
      protocol.readListEnd();
      break;
    case TType.MAP:
      p.getMapEventConsumer(id).addMap(protocol, this, protocol.readMapBegin());
      protocol.readMapEnd();
      break;
    case TType.SET:
      p.getSetEventConsumer(id).addSet(protocol, this, protocol.readSetBegin());
      protocol.readSetEnd();
      break;
    case TType.STOP:
      throw new UnsupportedOperationException("STOP?");
    case TType.STRING:
      p.getStringEventConsumer(id).addString(protocol.readString());
      break;
    case TType.STRUCT:
      p.getStructEventConsumer(id).addStruct(protocol, this, protocol.readStructBegin());
      protocol.readStructEnd();
      break;
    default:
      throw new UnsupportedOperationException("Unknown type " + type + " for field " + id);
    }
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

  public void readSetContent(
      TProtocol protocol, SetConsumer eventConsumer, TSet tSet) throws TException {
    for (int i = 0; i < tSet.size; i++) {
      eventConsumer.addSetElement(protocol, this, tSet.elemType);
    }
  }

  public void readMapContent(
      TProtocol protocol, MapConsumer eventConsumer, TMap tMap) throws TException {
    for (int i = 0; i < tMap.size; i++) {
      eventConsumer.addMapEntry(protocol, this, tMap.keyType, tMap.valueType);
    }
  }

  public void readListContent(
      TProtocol protocol, ListConsumer eventConsumer,
      TList tList) throws TException {
    for (int i = 0; i < tList.size; i++) {
      eventConsumer.addListElement(protocol, this, tList.elemType);
    }
  }

}
