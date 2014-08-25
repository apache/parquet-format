package parquet.format.event;

import org.apache.thrift.TException;
import org.apache.thrift.protocol.TProtocol;

/**
 * To receive Thrift field events
 *
 * @author Julien Le Dem
 *
 */
public interface FieldConsumer {
  public void addField(TProtocol protocol, EventBasedThriftReader reader, short id, byte type) throws TException;
}