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
import parquet.format.event.TypedConsumer.ListConsumer;
import parquet.format.event.TypedConsumer.StructConsumer;

/**
 * Entry point for reading thrift in a streaming fashion
 *
 * @author Julien Le Dem
 *
 */
public class Consumers {

  /**
   * To consume objects coming from a DelegatingFieldConsumer
   * @author Julien Le Dem
   *
   * @param <T> the type of consumed objects
   */
  public static interface Consumer<T> {
    void add(T t);
  }

  /**
   * Delegates reading the field to TypedConsumers.
   * There is one TypedConsumer per thrift type.
   * use {@link DelegatingFieldConsumer#onField(TFieldIdEnum, BoolConsumer)} et al. to consume specific thrift fields.
   * @see Consumers#fieldConsumer()
   * @author Julien Le Dem
   *
   */
  public static class DelegatingFieldConsumer implements FieldConsumer {
    private static class DelegateContext {

      private final TFieldIdEnum id;
      private final TypedConsumer typedConsumer;

      DelegateContext(TFieldIdEnum id, TypedConsumer typedConsumer) {
        super();
        this.id = id;
        this.typedConsumer = typedConsumer;
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

    public DelegatingFieldConsumer onField(TFieldIdEnum e, TypedConsumer typedConsumer) {
      Map<Short, DelegateContext> newContexts = new HashMap<Short, DelegateContext>(contexts);
      newContexts.put(e.getThriftFieldId(), new DelegateContext(e, typedConsumer));
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
        reader.readElement(delegate.typedConsumer, type);
      } else {
        defaultFieldEventConsumer.addField(protocol, reader, id, type);
      }
    }
  }

  /**
   * call onField on the resulting DelegatingFieldConsumer to handle individual fields
   * @return a new DelegatingFieldConsumer
   */
  public static DelegatingFieldConsumer fieldConsumer() {
    return new DelegatingFieldConsumer();
  }

  /**
   * To consume a list of elements
   * @param c the type of the list content
   * @param consumer the consumer that will receive the list
   * @return a ListConsumer that can be passed to the DelegatingListConsumer
   */
  public static <T extends TBase<T,? extends TFieldIdEnum>> ListConsumer listOf(Class<T> c, final Consumer<List<T>> consumer) {
    return new DelegatingListConsumer<T>(c) {
      @Override
      protected void addList(List<T> l) {
        consumer.add(l);
      }
    };
  }

  /**
   * To consume list elements one by one
   * @param c the type of the list content
   * @param consumer the consumer that will receive the elements
   * @return a ListConsumer that can be passed to the DelegatingListConsumer
   */
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
    reader.readStruct(c);
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