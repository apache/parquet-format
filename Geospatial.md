<!--
  - Licensed to the Apache Software Foundation (ASF) under one
  - or more contributor license agreements.  See the NOTICE file
  - distributed with this work for additional information
  - regarding copyright ownership.  The ASF licenses this file
  - to you under the Apache License, Version 2.0 (the
  - "License"); you may not use this file except in compliance
  - with the License.  You may obtain a copy of the License at
  -
  -   http://www.apache.org/licenses/LICENSE-2.0
  -
  - Unless required by applicable law or agreed to in writing,
  - software distributed under the License is distributed on an
  - "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
  - KIND, either express or implied.  See the License for the
  - specific language governing permissions and limitations
  - under the License.
  -->

Geospatial Definitions
====

This document contains the specification of geospatial types and statistics.

# Background

The Geometry and Geography class hierarchy and its Well-Known Text (WKT) and
Well-Known Binary (WKB) serializations (ISO supporting XY, XYZ, XYM, XYZM) are
defined by [OpenGIS Implementation Specification for Geographic information –
Simple feature access – Part 1: Common architecture][sfa-part1], from [OGC
(Open Geospatial Consortium)][ogc].

The version of the OGC standard first used here is 1.2.1, but future versions
may also used if the WKB representation remains wire-compatible.

[sfa-part1]: https://portal.ogc.org/files/?artifact_id=25355
[ogc]: https://www.ogc.org/standard/sfa/

## Well-Known Binary

Well-Known Binary (WKB) representations of geometries.

Apache Parquet follows the same definitions of GeoParquet for [WKB][geoparquet-wkb]
and [coordinate axis order][coordinate-axis-order]:
- Geometries should be encoded as ISO WKB supporting XY, XYZ, XYM, XYZM. Supported
standard geometry types: Point, LineString, Polygon, MultiPoint, MultiLineString,
MultiPolygon, and GeometryCollection.
- Coordinate axis order is always (x, y) where x is easting or longitude, and
y is northing or latitude. This ordering explicitly overrides the axis order
as specified in the CRS following the [GeoPackage specification][geopackage-spec].

[geoparquet-wkb]: https://github.com/opengeospatial/geoparquet/blob/v1.1.0/format-specs/geoparquet.md?plain=1#L92
[coordinate-axis-order]: https://github.com/opengeospatial/geoparquet/blob/v1.1.0/format-specs/geoparquet.md?plain=1#L155
[geopackage-spec]: https://www.geopackage.org/spec130/#gpb_spec

## Coordinate Reference System

Coordinate Reference System (CRS) is a mapping of how coordinates refer to
locations on Earth.

Apache Parquet supports CRS Customization by providing following attributes:
* `crs`: a CRS text representation. If unset, the CRS defaults to "OGC:CRS84".
* `crs_encoding`: a standard encoding used to represent the CRS text. If unset,
  `crs` can be arbitrary string.

For maximum interoperability of a custom CRS, it is recommended to provide
the CRS text with a standard encoding. Supported CRS encodings are:
* `SRID`: [Spatial reference identifier][srid], CRS text is the identifier itself.
* `PROJJSON`: [PROJJSON][projjson], CRS text is the projjson string.

For example, if a Geometry or Geography column uses the CRS "OGC:CRS84", a writer
may write a PROJJSON representation of [OGC:CRS84][ogc-crs84] to the `crs` field
and set the `crs_encoding` field to `PROJJSON`.

[srid]: https://en.wikipedia.org/wiki/Spatial_reference_system#Identifier
[projjson]: https://proj.org/en/stable/specifications/projjson.html
[ogc-crs84]: https://github.com/opengeospatial/geoparquet/blob/main/format-specs/geoparquet.md#ogccrs84-details

## Edge Interpolation Algorithm

The edge interpolation algorithm is used for interpreting edges of elements of
a Geography column. It is applies to all non-point geometry objects and is
independent of the [Coordinate Reference System](#coordinate-reference-system).

Supported values are:
* `spherical`: edges are interpolated as geodesics on a sphere. The radius of the underlying sphere is the mean radius of the spheroid defined by the CRS, defined as (2 * major_axis_length + minor_axis_length / 3).
* `vincenty`: [https://en.wikipedia.org/wiki/Vincenty%27s_formulae](https://en.wikipedia.org/wiki/Vincenty%27s_formulae)
* `thomas`: Thomas, Paul D. Spheroidal geodesics, reference systems, & local geometry. US Naval Oceanographic Office, 1970.
* `andoyer`: Thomas, Paul D. Mathematical models for navigation systems. US Naval Oceanographic Office, 1965.
* `karney`: [Karney, Charles FF. "Algorithms for geodesics." Journal of Geodesy 87 (2013): 43-55](https://link.springer.com/content/pdf/10.1007/s00190-012-0578-z.pdf), and [GeographicLib](https://geographiclib.sourceforge.io/)

# Logical Types

Apache Parquet supports the following geospatial logical type annotations:
* `GEOMETRY`: Geometry features in the WKB format with linear/planar edges interpolation. See [Geometry logical type](LogicalTypes.md#geometry)
* `GEOGRAPHY`: Geometry features in the WKB format with non-linear/non-planar edges interpolation. See [Geography logical type](LogicalTypes.md#geography)

# Statistics

`GeometryStatistics` is a struct specific for `GEOMETRY` and `GEOGRAPHY` logical
types to store statistics of a column chunk. It is an optional field in the
`ColumnMetaData` and contains [Bounding Box](#bounding-box) and [Geometry
Types](#geometry-types).

## Bounding Box

A geometry has at least two coordinate dimensions: X and Y for 2D coordinates
of each point. A geometry can optionally have Z and / or M values associated
with each point in the geometry.

The Z values introduce the third dimension coordinate. Usually they are used to
indicate the height, or elevation.

M values are an opportunity for a geometry to express a fourth dimension as a
coordinate value. These values can be used as a linear reference value (e.g.,
highway milepost value), a timestamp, or some other value as defined by the CRS.

Bounding box is defined as the thrift struct below in the representation of
min/max value pair of coordinates from each axis. Note that X and Y Values are
always present. Z and M are omitted for 2D geometries. The concepts of westmost
and eastmost values are explicitly introduced for Geography logical type to
address cases involving antimeridian crossing, where xmin may be greater than
xmax.

```thrift
struct BoundingBox {
  /** Min X value for Geometry logical type, westmost value for Geography logical type */
  1: required double xmin;
  /** Max X value for Geometry logical type, eastmost value for Geography logical type */
  2: required double xmax;
  /** Min Y value for Geometry logical type, southmost value for Geography logical type */
  3: required double ymin;
  /** Max Y value for Geometry logical type, northmost value for Geography logical type */
  4: required double ymax;
  /** Min Z value if the axis exists */
  5: optional double zmin;
  /** Max Z value if the axis exists */
  6: optional double zmax;
  /** Min M value if the axis exists */
  7: optional double mmin;
  /** Max M value if the axis exists */
  8: optional double mmax;
}
```

## Geometry Types

A list of geometry types from all geometries in the `GEOMETRY` or `GEOGRAPHY`
column, or an empty list if they are not known.

This is borrowed from [geometry_types of GeoParquet][geometry-types] except that
values in the list are [WKB (ISO-variant) integer codes][wkb-integer-code].
Table below shows the most common geometry types and their codes:

| Type               | XY   | XYZ  | XYM  | XYZM |
| :----------------- | :--- | :--- | :--- | :--: |
| Point              | 0001 | 1001 | 2001 | 3001 |
| LineString         | 0002 | 1002 | 2002 | 3002 |
| Polygon            | 0003 | 1003 | 2003 | 3003 |
| MultiPoint         | 0004 | 1004 | 2004 | 3004 |
| MultiLineString    | 0005 | 1005 | 2005 | 3005 |
| MultiPolygon       | 0006 | 1006 | 2006 | 3006 |
| GeometryCollection | 0007 | 1007 | 2007 | 3007 |

In addition, the following rules are applied:
- A list of multiple values indicates that multiple geometry types are present (e.g. `[0003, 0006]`).
- An empty array explicitly signals that the geometry types are not known.
- The geometry types in the list must be unique (e.g. `[0001, 0001]` is not valid).

[geometry-types]: https://github.com/opengeospatial/geoparquet/blob/v1.1.0/format-specs/geoparquet.md?plain=1#L159
[wkb-integer-code]: https://en.wikipedia.org/wiki/Well-known_text_representation_of_geometry#Well-known_binary
