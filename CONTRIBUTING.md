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

Recommendations and requirements for how to best contribute to Parquet. We strive to obey these as best as possible. As always, thanks for contributing--we hope these guidelines make it easier and shed some light on our approach and processes.

### Key branches
- `master` has the latest stable changes

### Pull requests
- Submit pull requests against the `master` branch
- Try not to pollute your pull request with unintended changes--keep them simple and small

### License
By contributing your code, you agree to license your contribution under the terms of the APLv2:
https://github.com/apache/parquet-format/blob/master/LICENSE

### Additions/Changes to the Format

The general steps for adding features to the format are as follows:

1. Discuss changes on on the developer mailing list (dev@parquet.apache.org).  Often times it is helpful to link to a draft pull request to make the discussion concrete. This step is complete when there lazy consensus.

2. Once a change has lazy consensus two implementations of the feature
demonstrating interopability must also be provided.  One implementation MUST be [parquet-java](http://github.com/apache/parquet-java).  It is preferred that the second implementation be [parquet-cpp](https://github.com/apache/arrow) or [parquet-rs](https://github.com/apache/arrow-rs), however at the discretion of the PMC any
open source Parquet implementation may be acceptable. Implementations
whose contributors actively
participate in the community (e.g. keep their feature matrix
up-to-date on parquet-site) are more likely to be considered.

Unless otherwise discussed, it is expected the implementations will
develop from the main branch (i.e. packporting is not expected).

In some cases in addition to library level implementations it is 
expected the changes to be justified with integration into a
processing engine to show there viability.

3. After the first two steps are complete a formal vote is held on the Parquet mailing list to officially
ratify the feature.  After the vote passes the format change is merged into the parquet-format repository
and it is expected the change in step 2 will also be merged soon after. Before merging into Parquet-java a parquet-format release
must be performed.

#### General guidelines/preferences on additions.

1. To the greatest extent possible changes should have an option for forwards compatibility (old readers can still read files).
2. New encodings should be fully specified in this repository and ideally not rely on an external dependencies for implementation (i.e. Parquet is the source of truth for the encoding).
3. New compression mechanisms must have a pure Java implementation that can be used as dependency in parquet-java.

### Releases

The Parquet community aims to do releases of the format package only as needed when new features are introduced.
If multiple new features are being proposed simultaneously some features might be consolidated into the same release.  Guidance is provided below on when implementations should enable features added to the specification.
Due to confusion in the past over parquet versioning it is not expected that there will be a 3.0 release of the specification in the foreseeable future.

### Compatibility and Feature Enablement

For the purposes of this discussion we classify features into the following buckets:

1. Backwards compatible.  A file written by an older version of a library can be read by a newer version of the
library.

2. Forwards compatible.  A file written by a new version of the library can be read by an older version
of the library. 

3. Forward compatible with suboptimal performance. A file written by a new version of the library can
be read an older version of the library but performance might be suboptimal (e.g. statistics might be missing
from the older reader's perspective).

4. Forward incompatible. A file written with a new version of the library cannot be read by an older version
of the library.

The Parquet community hopes that new features are widely beneficial
to users of Parquet, and therefore third-party implementations will
adopt them quickly after they are introduced. It is assumed that most new features will be implemented behind a feature flag that defaults to "off".To avoid, compatibility issues across the ecosystem some amount of lead time is desirable to ensure a critical mass of Parquet implementations support a feature.  Therefore, the Parquet PMC gives the following guidance for changing a feature to be "on" by default:

1. Backwards compatibility is the concern of implementations but given the ubiquity of Parquet and the length
of time it has been used, libraries SHOULD support reading older
file variants.

2. Forward compatible changes MAY be used by default in implementations once the parquet-format containing
those changes has been formally released. These features SHOULD be turned on 1 year after the parquet-java
implementation containing feature is released (e.g. it is expected
the Java implementation itself will turn them on for the first
release 1 year after a features initial introduction).

3. Forward compatible with suboptimal performance features MAY be made default after 
the parquet-java implementation containing the feature is released. Features in this category
SHOULD be turned on 1 year after the parquet-java
implementation containing the feature is released.  Implementations MAY choose
to do a major version bump when turning on a feature in this category.

4. Forwards incompatible changes MAY be made default 2 years after the parquet-java
implementation containing the feature is released. Features in this category SHOULD be turned on by 
default 3 years after the parquet-java implementation containing feature is released. Implementations MUST do 
a major version bump when enabling a forward incompatible feature by default.

For features released prior to October 2024, target dates for each of these categories will be updated
as part of the parquet-java 2.0 process based on a collected feature compatibility matrix.

For each release of parquet-java or parquet-format that influences this guidance it is expected
exact dates will be added to parquet-format to provide clarity to implementors (e.g. When parquet-java 2.X.X is released, any 
new format features it uses will be updated with concrete dates).

End users of software are generally encouraged to follow the same guidance unless they have mechanisms for ensuring the version of all possible readers of the Parquet files support the feature. One way
of doing this is to cross-reference feature matrix.