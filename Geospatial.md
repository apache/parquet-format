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
may also be used if the WKB representation remains wire-compatible.

[sfa-part1]: https://portal.ogc.org/files/?artifact_id=25355
[ogc]: https://www.ogc.org/standard/sfa/

## Coordinate Reference System

Coordinate Reference System (CRS) is a mapping of how coordinates refer to
locations on Earth.

The default CRS `OGC:CRS84` means that the objects must be stored in longitude,
latitude based on the WGS84 datum.

Custom CRS can be specified by following attributes:
* `crs`: a CRS text representation. If unset, the CRS defaults to `"OGC:CRS84"`.
* `crs_encoding`: a standard encoding used to represent the CRS text. If unset,
  `crs` can be arbitrary string.

For maximum interoperability of a custom CRS, it is recommended to provide
the CRS text with a standard encoding. Supported CRS encodings are:
* `SRID`: [Spatial reference identifier][srid], CRS text is the identifier itself.
* `PROJJSON`: [PROJJSON][projjson], CRS text is the PROJJSON string.

For example, a writer may write a PROJJSON representation of [OGC:CRS84][ogc-crs84]
to the `crs` field and set the `crs_encoding` field to `"PROJJSON"`.

[srid]: https://en.wikipedia.org/wiki/Spatial_reference_system#Identifier
[projjson]: https://proj.org/en/stable/specifications/projjson.html
[ogc-crs84]: https://github.com/opengeospatial/geoparquet/blob/main/format-specs/geoparquet.md#ogccrs84-details

## Edge Interpolation Algorithm

An algorithm for interpolating edges, and is one of the following values:

* `spherical`: edges are interpolated as geodesics on a sphere.
* `vincenty`: [https://en.wikipedia.org/wiki/Vincenty%27s_formulae](https://en.wikipedia.org/wiki/Vincenty%27s_formulae)
* `thomas`: Thomas, Paul D. Spheroidal geodesics, reference systems, & local geometry. US Naval Oceanographic Office, 1970.
* `andoyer`: Thomas, Paul D. Mathematical models for navigation systems. US Naval Oceanographic Office, 1965.
* `karney`: [Karney, Charles FF. "Algorithms for geodesics." Journal of Geodesy 87 (2013): 43-55](https://link.springer.com/content/pdf/10.1007/s00190-012-0578-z.pdf), and [GeographicLib](https://geographiclib.sourceforge.io/)

# Logical Types

Two geospatial logical type annotations are supported:
* `GEOMETRY`: Geometry features in the WKB format with linear/planar edges interpolation. See [Geometry](LogicalTypes.md#geometry)
* `GEOGRAPHY`: Geography features in the WKB format with an explicit (non-linear/non-planar) edges interpolation algorithm. See [Geography](LogicalTypes.md#geography)

# Statistics

`GeometryStatistics` is a struct specific for `GEOMETRY` and `GEOGRAPHY` logical
types to store statistics of a column chunk. It is an optional field in the
`ColumnMetaData` and contains [Bounding Box](#bounding-box) and [Geometry
Types](#geometry-types) that are described below in detail.

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
always present. Z and M are omitted for 2D geometries.

For the X and Y values only, (xmin/ymin) may be greater than (xmax/ymax). In this
X case, an object in this bounding box may match if it contains an X such that
`x >= xmin` OR `x <= xmax`, and in this Y case if `y >= ymin` OR `y <= ymax`.
In geographic terminology, the concepts of `xmin`, `xmax`, `ymin`, and `ymax`
are also known as `westernmost`, `easternmost`, `southernmost` and `northernmost`,
respectively.

For `GEOGRAPHY` types, X and Y values are restricted to the canonical ranges of
[-180, 180] for X and [-90, 90] for Y.

```thrift
struct BoundingBox {
  1: required double xmin;
  2: required double xmax;
  3: required double ymin;
  4: required double ymax;
  5: optional double zmin;
  6: optional double zmax;
  7: optional double mmin;
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
