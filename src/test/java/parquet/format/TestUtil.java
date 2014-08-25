package parquet.format;

import static java.util.Arrays.asList;
import static junit.framework.Assert.assertEquals;
import static junit.framework.Assert.assertNull;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.util.List;

import org.junit.Test;

public class TestUtil {

  private final class Observer extends Util.FileMetaDataObserver {
    private final FileMetaData md;

    private Observer(FileMetaData md3) {
      this.md = md3;
    }

    @Override
    public void setVersion(int version) {
      md.setVersion(version);
    }

    @Override
    public void setSchema(List<SchemaElement> schema) {
      md.setSchema(schema);
    }

    @Override
    public void setNumRows(long numRows) {
      md.setNum_rows(numRows);
    }

    @Override
    public void setCreatedBy(String createdBy) {
      md.setCreated_by(createdBy);
    }

    @Override
    public void addRowGroup(RowGroup rowGroup) {
      md.addToRow_groups(rowGroup);
    }

    @Override
    public void addKeyValueMetaData(KeyValue kv) {
      md.addToKey_value_metadata(kv);
    }
  }

  @Test
  public void testReadFileMetadata() throws Exception {
    ByteArrayOutputStream baos = new ByteArrayOutputStream();
    FileMetaData md = new FileMetaData(
        1,
        asList(new SchemaElement("foo")),
        10,
        asList(
            new RowGroup(
                asList(
                    new ColumnChunk(0),
                    new ColumnChunk(1)
                    ),
                10,
                5),
            new RowGroup(
                asList(
                    new ColumnChunk(2),
                    new ColumnChunk(3)
                    ),
                11,
                5)
        )
    );
    Util.writeFileMetaData(md , baos);
    ByteArrayInputStream bais = new ByteArrayInputStream(baos.toByteArray());
    FileMetaData md2 = Util.readFileMetaData(bais);
    bais.reset();
    FileMetaData md3 = new FileMetaData();
    Util.readFileMetaData(bais, new Observer(md3));
    bais.reset();
    FileMetaData md4 = new FileMetaData();
    Util.readFileMetaData(bais, new Observer(md4), true);
    assertEquals(md, md2);
    assertEquals(md, md3);
    assertNull(md4.getRow_groups());
    md4.setRow_groups(md.getRow_groups());
    assertEquals(md, md4);
  }
}
