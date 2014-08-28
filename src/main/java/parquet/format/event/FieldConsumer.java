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
  /**
   * called by the EventBasedThriftReader when reading a field from a Struct
   * The implementor has the choice of either reading the field themselves from the protocol or delegate to the reader
   * reader.readField(provider, id, type);
   * @param protocol the underlying protocol
   * @param reader the reader to delegate to
   * @param id the id of the field
   * @param type the type of the field
   * @throws TException
   */
  public void addField(TProtocol protocol, EventBasedThriftReader reader, short id, byte type) throws TException;
}