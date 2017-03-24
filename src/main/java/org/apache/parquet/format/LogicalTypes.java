package org.apache.parquet.format;

/**
 * Convenience instances of logical type classes.
 */
public class LogicalTypes {
  public static class TimeUnits {
    public static final TimeUnit MILLIS = TimeUnit.MILLIS(new MilliSeconds());
    public static final TimeUnit MICROS = TimeUnit.MICROS(new MicroSeconds());
  }

  private static class EmbeddedFormats {
    public static final EmbeddedFormat JSON = EmbeddedFormat.JSON(new JSON());
    public static final EmbeddedFormat BSON = EmbeddedFormat.BSON(new BSON());
  }

  public static LogicalType DECIMAL(int scale, int precision) {
    return LogicalType.DECIMAL(new DecimalType(scale, precision));
  }

  public static final LogicalType UTF8 = LogicalType.STRING(new StringType());
  public static final LogicalType MAP  = LogicalType.MAP(new MapType());
  public static final LogicalType LIST = LogicalType.LIST(new ListType());
  public static final LogicalType ENUM = LogicalType.ENUM(new EnumType());
  public static final LogicalType DATE = LogicalType.DATE(new DateType());
  public static final LogicalType TIME_MILLIS = LogicalType.TIME(new TimeType(true, TimeUnits.MILLIS));
  public static final LogicalType TIME_MICROS = LogicalType.TIME(new TimeType(true, TimeUnits.MICROS));
  public static final LogicalType TIMESTAMP_MILLIS = LogicalType.TIMESTAMP(new TimestampType(true, TimeUnits.MILLIS));
  public static final LogicalType TIMESTAMP_MICROS = LogicalType.TIMESTAMP(new TimestampType(true, TimeUnits.MICROS));
  public static final LogicalType INT_8 = LogicalType.INTEGER(new IntType(8, true));
  public static final LogicalType INT_16 = LogicalType.INTEGER(new IntType(16, true));
  public static final LogicalType INT_32 = LogicalType.INTEGER(new IntType(32, true));
  public static final LogicalType INT_64 = LogicalType.INTEGER(new IntType(64, true));
  public static final LogicalType UINT_8 = LogicalType.INTEGER(new IntType(8, false));
  public static final LogicalType UINT_16 = LogicalType.INTEGER(new IntType(16, false));
  public static final LogicalType UINT_32 = LogicalType.INTEGER(new IntType(32, false));
  public static final LogicalType UINT_64 = LogicalType.INTEGER(new IntType(64, false));
  public static final LogicalType JSON = LogicalType.EMBEDDED(new EmbeddedType(EmbeddedFormats.JSON));
  public static final LogicalType BSON = LogicalType.EMBEDDED(new EmbeddedType(EmbeddedFormats.BSON));
  public static final LogicalType NULL = LogicalType.NULL(new NullType());
}
