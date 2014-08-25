package parquet.format.event;

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
 * To provide a consumer based on the field id
 *
 * @author Julien Le Dem
 *
 */
abstract public class TypedConsumerProvider {
  private RuntimeException error(short id, String type) {
    return new IllegalArgumentException("id " + id + " was not expected for type " + type);
  }
  public BoolConsumer getBoolConsumer(short id)     { throw error(id, "BOOL");   }
  public ByteConsumer getByteConsumer(short id)     { throw error(id, "BYTE");   }
  public DoubleConsumer getDoubleConsumer(short id) { throw error(id, "DOUBLE"); }
  public I16Consumer getI16Consumer(short id)       { throw error(id, "I16");    }
  public I32Consumer getI32Consumer(short id)       { throw error(id, "I32");    }
  public ListConsumer getListConsumer(short id)     { throw error(id, "LIST");   }
  public I64Consumer getI64Consumer(short id)       { throw error(id, "I64");    }
  public MapConsumer getMapConsumer(short id)       { throw error(id, "MAP");    }
  public SetConsumer getSetConsumer(short id)       { throw error(id, "SET");    }
  public StringConsumer getStringConsumer(short id) { throw error(id, "STRING"); }
  public StructConsumer getStructConsumer(short id) { throw error(id, "STRUCT"); }
}