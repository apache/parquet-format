package parquet.format.event;

import static java.util.Collections.unmodifiableMap;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import org.apache.thrift.TBase;
import org.apache.thrift.TException;
import org.apache.thrift.TFieldIdEnum;
import org.apache.thrift.protocol.TList;
import org.apache.thrift.protocol.TProtocol;
import org.apache.thrift.protocol.TProtocolUtil;

import parquet.format.event.TypedConsumer.BoolConsumer;
import parquet.format.event.TypedConsumer.ByteConsumer;
import parquet.format.event.TypedConsumer.DoubleConsumer;
import parquet.format.event.TypedConsumer.I16Consumer;
import parquet.format.event.TypedConsumer.I32Consumer;
import parquet.format.event.TypedConsumer.I64Consumer;
import parquet.format.event.TypedConsumer.ListConsumer;
import parquet.format.event.TypedConsumer.MapConsumer;
import parquet.format.event.TypedConsumer.SetConsumer;
import parquet.format.event.TypedConsumer.StringConsumer;
import parquet.format.event.TypedConsumer.StructConsumer;

/**
 * Entry point for reading thrift in a streaming fashion
 *
 * @author Julien Le Dem
 *
 */
public class Consumers {

  public static interface Consumer<T> {
    void add(T t);
  }

  public static class DelegatingFieldConsumer implements FieldConsumer {
    private static class DelegateContext {

      private final TFieldIdEnum id;
      private final TypedConsumer typedConsumer;
      private final TypedConsumerProvider provider;

      DelegateContext(TFieldIdEnum id, TypedConsumer typedConsumer, TypedConsumerProvider provider) {
        super();
        this.id = id;
        this.typedConsumer = typedConsumer;
        this.provider = provider;
      }

      void validate(byte type) throws TException {
        if (typedConsumer.type != type) {
          throw new TException(
              "Incorrect type in stream for field " + id.getFieldName() + ". "
                  + "Expected " + typedConsumer.type
                  + " but got " + type);
        }
      }

    }

    private final Map<Short, DelegateContext> contexts;
    private final FieldConsumer defaultFieldEventConsumer;

    private DelegatingFieldConsumer(FieldConsumer defaultFieldEventConsumer, Map<Short, DelegateContext> contexts) {
      this.defaultFieldEventConsumer = defaultFieldEventConsumer;
      this.contexts = unmodifiableMap(contexts);
    }

    private DelegatingFieldConsumer() {
      this(new SkippingFieldConsumer());
    }

    private DelegatingFieldConsumer(FieldConsumer defaultFieldEventConsumer) {
      this(defaultFieldEventConsumer, Collections.<Short, DelegateContext>emptyMap());
    }

    public DelegatingFieldConsumer onField(TFieldIdEnum e, final DoubleConsumer consumer) {
      return this.addContext(e, consumer, new TypedConsumerProvider() {
        @Override
        public DoubleConsumer getDoubleConsumer(short id) {
          return consumer;
        }
      });
    }
    public DelegatingFieldConsumer onField(TFieldIdEnum e, final ByteConsumer consumer) {
      return this.addContext(e, consumer, new TypedConsumerProvider() {
        @Override
        public ByteConsumer getByteConsumer(short id) {
          return consumer;
        }
      });
    }
    public DelegatingFieldConsumer onField(TFieldIdEnum e, final BoolConsumer consumer) {
      return this.addContext(e, consumer, new TypedConsumerProvider() {
        @Override
        public BoolConsumer getBoolConsumer(short id) {
          return consumer;
        }
      });
    }
    public DelegatingFieldConsumer onField(TFieldIdEnum e, final StructConsumer consumer) {
      return this.addContext(e, consumer, new TypedConsumerProvider() {
        @Override
        public StructConsumer getStructConsumer(short id) {
          return consumer;
        }
      });
    }
    public DelegatingFieldConsumer onField(TFieldIdEnum e, final I16Consumer consumer) {
      return this.addContext(e, consumer, new TypedConsumerProvider() {
        @Override
        public I16Consumer getI16Consumer(short id) {
          return consumer;
        }
      });
    }
    public DelegatingFieldConsumer onField(TFieldIdEnum e, final I32Consumer consumer) {
      return this.addContext(e, consumer, new TypedConsumerProvider() {
        @Override
        public I32Consumer getI32Consumer(short id) {
          return consumer;
        }
      });
    }
    public DelegatingFieldConsumer onField(TFieldIdEnum e, final I64Consumer consumer) {
      return this.addContext(e, consumer, new TypedConsumerProvider() {
        @Override
        public I64Consumer getI64Consumer(short id) {
          return consumer;
        }
      });
    }
    public DelegatingFieldConsumer onField(TFieldIdEnum e, final StringConsumer consumer) {
      return this.addContext(e, consumer, new TypedConsumerProvider() {
        @Override
        public StringConsumer getStringConsumer(short id) {
          return consumer;
        }
      });
    }
    public DelegatingFieldConsumer onField(TFieldIdEnum e, final ListConsumer consumer) {
      return this.addContext(e, consumer, new TypedConsumerProvider() {
        @Override
        public ListConsumer getListConsumer(short id) {
          return consumer;
        }
      });
    }
    public DelegatingFieldConsumer onField(TFieldIdEnum e, final SetConsumer consumer) {
      return this.addContext(e, consumer, new TypedConsumerProvider() {
        @Override
        public SetConsumer getSetConsumer(short id) {
          return consumer;
        }
      });
    }
    public DelegatingFieldConsumer onField(TFieldIdEnum e, final MapConsumer consumer) {
      return this.addContext(e, consumer, new TypedConsumerProvider() {
        @Override
        public MapConsumer getMapConsumer(short id) {
          return consumer;
        }
      });
    }

    private DelegatingFieldConsumer addContext(TFieldIdEnum e, TypedConsumer typedConsumer, TypedConsumerProvider fieldConsumer) {
      Map<Short, DelegateContext> newContexts = new HashMap<Short, DelegateContext>(contexts);
      newContexts.put(e.getThriftFieldId(), new DelegateContext(e, typedConsumer, fieldConsumer));
      return new DelegatingFieldConsumer(defaultFieldEventConsumer, newContexts);
    }

    private DelegateContext getDelegate(short id) {
      return contexts.get(id);
    }

    @Override
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

  public static DelegatingFieldConsumer fieldConsumer() {
    return new DelegatingFieldConsumer();
  }

  public static <T extends TBase<T,? extends TFieldIdEnum>> ListConsumer listOf(Class<T> c, final Consumer<List<T>> consumer) {
    return new DelegatingListConsumer<T>(c) {
      @Override
      protected void addList(List<T> l) {
        consumer.add(l);
      }
    };
  }

  public static <T extends TBase<T,? extends TFieldIdEnum>> ListConsumer listElementsOf(Class<T> c, final Consumer<T> consumer) {
    return new DelegatingListElementsConsumer<T>(c) {
      @Override
      protected void addToList(T t) {
        consumer.add(t);
      }
    };
  }
}

abstract class DelegatingListConsumer<T extends TBase<T,? extends TFieldIdEnum>> extends DelegatingListElementsConsumer<T> {

  private List<T> list;

  protected DelegatingListConsumer(Class<T> c) {
    super(c);
  }

  @Override
  public void addList(TProtocol protocol, EventBasedThriftReader reader, TList tList) throws TException {
    list = new ArrayList<T>();
    super.addList(protocol, reader, tList);
    addList(list);
  }

  protected void addToList(T t) {
    list.add(t);
  };

  abstract protected void addList(List<T> l);

}

abstract class DelegatingStructConsumer extends StructConsumer {
  private FieldConsumer c;
  protected DelegatingStructConsumer(FieldConsumer c) {
    this.c = c;
  }
  @Override
  public void addStruct(TProtocol protocol, EventBasedThriftReader reader) throws TException {
    reader.readStruct(protocol, c);
  }
}

class SkippingFieldConsumer implements FieldConsumer {
  public void addField(TProtocol protocol, EventBasedThriftReader reader, short id, byte type) throws TException {
    TProtocolUtil.skip(protocol, type);
  }
}

abstract class DelegatingListElementsConsumer<T extends TBase<T,? extends TFieldIdEnum>> extends ListConsumer {

  private TBaseStructConsumer<T> elementConsumer;

  protected DelegatingListElementsConsumer(Class<T> c) {
    this.elementConsumer = new TBaseStructConsumer<T>(c) {
      protected void addObject(T t) {
        addToList(t);
      }
    };
  }

  abstract protected void addToList(T t);

  @Override
  public void addListElement(TProtocol protocol, EventBasedThriftReader reader, byte elemType) throws TException {
    elementConsumer.addStruct(protocol, reader);
  }
}

abstract class TBaseStructConsumer<T extends TBase<T, ? extends TFieldIdEnum>> extends StructConsumer {

  private final Class<T> c;

  public TBaseStructConsumer(Class<T> c) {
    this.c = c;
  }

  @Override
  public void addStruct(TProtocol protocol, EventBasedThriftReader reader) throws TException {
    T o = newObject();
    o.read(protocol);
    addObject(o);
  }

  protected T newObject() {
    try {
      return c.newInstance();
    } catch (InstantiationException e) {
      throw new RuntimeException(c.getName(), e);
    } catch (IllegalAccessException e) {
      throw new RuntimeException(c.getName(),e);
    }
  }

  abstract protected void addObject(T t);
}