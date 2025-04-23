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
Well-Known Binary (WKB) serializations (ISO variant supporting XY, XYZ, XYM,
XYZM) are defined by [OpenGIS Implementation Specification for Geographic
information - Simple feature access - Part 1: Common architecture][sfa-part1],
from [OGC(Open Geospatial Consortium)][ogc].

The version of the OGC standard first used here is 1.2.1, but future versions
may also be used if the WKB representation remains wire-compatible.

[sfa-part1]: https://portal.ogc.org/files/?artifact_id=25355
[ogc]: https://www.ogc.org/standard/sfa/

## Coordinate Reference System

Coordinate Reference System (CRS) is a mapping of how coordinates refer to
locations on Earth.

The default CRS `OGC:CRS84` means that the geospatial features must be stored
in the order of longitude/latitude based on the WGS84 datum.

Custom CRS can be specified by a string value. It is recommended to use an
identifier-based approach like [Spatial reference identifier][srid].

For geographic CRS, longitudes are bound by [-180, 180] and latitudes are bound
by [-90, 90].

[srid]: https://en.wikipedia.org/wiki/Spatial_reference_system#Identifier

## Edge Interpolation Algorithm

An algorithm for interpolating edges, and is one of the following values:

* `spherical`: edges are interpolated as geodesics on a sphere.
* `vincenty`: [https://en.wikipedia.org/wiki/Vincenty%27s_formulae](https://en.wikipedia.org/wiki/Vincenty%27s_formulae)
* `thomas`: Thomas, Paul D. Spheroidal geodesics, reference systems, & local geometry. US Naval Oceanographic Office, 1970.
* `andoyer`: Thomas, Paul D. Mathematical models for navigation systems. US Naval Oceanographic Office, 1965.
* `karney`: [Karney, Charles FF. "Algorithms for geodesics." Journal of Geodesy 87 (2013): 43-55](https://link.springer.com/content/pdf/10.1007/s00190-012-0578-z.pdf), and [GeographicLib](https://geographiclib.sourceforge.io/)

# Logical Types

Two geospatial logical type annotations are supported:
* `GEOMETRY`: geospatial features in the WKB format with linear/planar edges interpolation. See [Geometry](LogicalTypes.md#geometry)
* `GEOGRAPHY`: geospatial features in the WKB format with an explicit (non-linear/non-planar) edges interpolation algorithm. See [Geography](LogicalTypes.md#geography)

# Statistics

`GeospatialStatistics` is a struct specific for `GEOMETRY` and `GEOGRAPHY`
logical types to store statistics of a column chunk. It is an optional field in
the `ColumnMetaData` and contains [Bounding Box](#bounding-box) and [Geospatial
Types](#geospatial-types) that are described below in detail.

## Bounding Box

A geospatial instance has at least two coordinate dimensions: X and Y for 2D
coordinates of each point. Please note that X is longitude/easting and Y is
latitude/northing. A geospatial instance can optionally have Z and/or M values
associated with each point.

The Z values introduce the third dimension coordinate. Usually they are used to
indicate the height, or elevation.

M values are an opportunity for a geospatial instance to express a fourth
dimension as a coordinate value. These values can be used as a linear reference
value (e.g., highway milepost value), a timestamp, or some other value as defined
by the CRS.

Bounding box is defined as the thrift struct below in the representation of
min/max value pair of coordinates from each axis. Note that X and Y Values are
always present. Z and M are omitted for 2D geospatial instances.

Writers should follow the guidelines below when calculating bounding boxes in
the presence of invalid values. An invalid geospatial value refers to any of 
the following: `NaN`, `null`, `does not exist` (e.g., LINESTRING EMPTY), or 
`out of bounds` (e.g., `x < -180` or `x > 180` for `GEOGRAPHY` types):

* X and Y: Skip any invalid X or Y value and continue processing the remaining X or Y 
  values. Do not produce a bounding box if all X or all Y values are invalid.

* Z: Skip any invalid Z value and continue processing the remaining Z values.
  Omit Z from the bounding box if all Z values are invalid.

* M: Skip any invalid M value and continue processing the remaining M values.
  Omit M from the bounding box if all M values are invalid.

Readers should follow the guidelines below when examining bounding boxes:

* No bounding box: No assumptions can be made about the presence or absence 
  of invalid values. Readers may need to load all individual coordinate 
  values for validation.

* A bounding box is present:
    * X and Y: X and Y of the bounding box must be present. Readers should 
      proceed using these values.
    * Z: If Z of the bounding box are missing, readers should make no 
      assumptions about invalid values and may need to load individual 
      coordinates for validation.
    * M: If M of the bounding box are missing, readers should make no 
      assumptions about invalid values and may need to load individual 
      coordinates for validation.

For the X values only, xmin may be greater than xmax. In this case, an object
in this bounding box may match if it contains an X such that `x >= xmin` OR
`x <= xmax`. This wraparound occurs only when the corresponding bounding box
crosses the antimeridian line. In geographic terminology, the concepts of `xmin`,
`xmax`, `ymin`, and `ymax` are also known as `westernmost`, `easternmost`,
`southernmost` and `northernmost`, respectively.

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

## Geospatial Types

A list of geospatial types from all instances in the `GEOMETRY` or `GEOGRAPHY`
column, or an empty list if they are not known.

This is borrowed from [geometry_types of GeoParquet][geometry-types] except that
values in the list are [WKB (ISO-variant) integer codes][wkb-integer-code].
Table below shows the most common geospatial types and their codes:

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
- A list of multiple values indicates that multiple geospatial types are present (e.g. `[0003, 0006]`).
- An empty array explicitly signals that the geospatial types are not known.
- The geospatial types in the list must be unique (e.g. `[0001, 0001]` is not valid).

[geometry-types]: https://github.com/opengeospatial/geoparquet/blob/v1.1.0/format-specs/geoparquet.md?plain=1#L159
[wkb-integer-code]: https://en.wikipedia.org/wiki/Well-known_text_representation_of_geometry#Well-known_binary

# CRS Customization

CRS is represented as a string value. Writer and reader implementations are
responsible for serializing and deserializing the CRS, respectively.

As a convention to maximize the interoperability, custom CRS values can be
specified by a string of the format `type:identifier`, where `type` is one of
the following values:

* `srid`: [Spatial reference identifier](https://en.wikipedia.org/wiki/Spatial_reference_system#Identifier), `identifier` is the SRID itself.
* `projjson`: [PROJJSON](https://proj.org/en/stable/specifications/projjson.html), `identifier` is the name of a table property or a file property where the projjson string is stored.

# Coordinate axis order

The axis order of the coordinates in WKB and bounding box stored in Parquet
follows the de facto standard for axis order in WKB and is therefore always
(x, y) where x is easting or longitude and y is northing or latitude. This
ordering explicitly overrides the axis order as specified in the CRS.
