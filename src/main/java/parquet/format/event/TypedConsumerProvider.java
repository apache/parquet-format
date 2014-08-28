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
  private RuntimeException error(String type) {
    return new IllegalArgumentException("type " + type + " was not expected");
  }
  public BoolConsumer getBoolConsumer()     { throw error("BOOL");   }
  public ByteConsumer getByteConsumer()     { throw error("BYTE");   }
  public DoubleConsumer getDoubleConsumer() { throw error("DOUBLE"); }
  public I16Consumer getI16Consumer()       { throw error("I16");    }
  public I32Consumer getI32Consumer()       { throw error("I32");    }
  public ListConsumer getListConsumer()     { throw error("LIST");   }
  public I64Consumer getI64Consumer()       { throw error("I64");    }
  public MapConsumer getMapConsumer()       { throw error("MAP");    }
  public SetConsumer getSetConsumer()       { throw error("SET");    }
  public StringConsumer getStringConsumer() { throw error("STRING"); }
  public StructConsumer getStructConsumer() { throw error("STRUCT"); }
}