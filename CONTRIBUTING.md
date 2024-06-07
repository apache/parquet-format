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

Note: This section applies to actual functional changes to the specification.
Fixing typos, grammar, and clarifying concepts that would not change the
semantics of the specification can be done as long a comitter feels comfortable
to merge them. When in doubt starting a discussion on the dev mailing list is
encouraged.

The general steps for adding features to the format are as follows:

1. Discuss changes on on the developer mailing list (dev@parquet.apache.org).
   Often times it is helpful to link to a draft pull request to make the
   discussion concrete. This step is complete when there lazy consensus. Part
   of the consensus is whether it sufficient to provide 2 working
   implementations as outlined in step 2 or if demonstration of the feature
   with a down-stream query engine is necessary to justify the feature (e.g.
   demonstrate performance improvements in Arrow's DataSet library or
   Apache Data Fusion).

2. Once a change has lazy consensus two implementations of the feature
   demonstrating interopability must also be provided.  One implementation MUST
   be [parquet-java](http://github.com/apache/parquet-java).  It is preferred
   that the second implementation be
   [parquet-cpp](https://github.com/apache/arrow) or
   [parquet-rs](https://github.com/apache/arrow-rs), however at the discretion
   of the PMC any open source Parquet implementation may be acceptable.
   Implementations whose contributors actively participate in the community
   (e.g. keep their feature matrix up-to-date on parquet-site) are more likely
   to be considered. If discussed as a requirement in step one demonstration
   of integration with a query engine is also required for this step.

Unless otherwise discussed, it is expected the implementations will develop from
the main branch (i.e. backporting is not expected).

3. After the first two steps are complete a formal vote is held on the Parquet
   mailing list to officially ratify the feature.  After the vote passes the
   format change is merged into the parquet-format repository and it is expected
   the changes from step 2 will also be merged soon after. Before merging into
   Parquet-java a parquet-format release must be performed.

#### General guidelines/preferences on additions.

1. To the greatest extent possible changes should have an option for forwards
   compatibility (old readers can still read files).
2. New encodings should be fully specified in this repository and ideally not
   rely on an external dependencies for implementation (i.e. Parquet is the
   source of truth for the encoding).
3. New compression mechanisms must have a pure Java implementation that can be
   used as dependency in parquet-java.

### Releases

The Parquet community aims to do releases of the format package only as needed
when new features are introduced. If multiple new features are being proposed
simultaneously some features might be consolidated into the same release.
Guidance is provided below on when implementations should enable features added
to the specification.  Due to confusion in the past over parquet versioning it
is not expected that there will be a 3.0 release of the specification in the
foreseeable future.

### Compatibility and Feature Enablement

For the purposes of this discussion we classify features into the following buckets:

1. Backwards compatible. A file written under an older version of the format
   should be readable under a newer version of the format.
2. Forwards compatible. A file written under a newer version of the format with
   the enabled feature can be read under an older version of the format, but
   some information might be missing or performance might be suboptimal.
3. Forward incompatible. A file written under a new version of the format with
   the feature enabled cannot be read under and older version of the format
   (e.g. Adding a new compression algorithm.

The Parquet community hopes that new features are widely beneficial to users of
Parquet, and therefore third-party implementations will adopt them quickly after
they are introduced. It is assumed that most new features will be implemented
behind a feature flag that defaults to "off" and at some future point the
features are turned on by default. To avoid, compatibility issues across the
ecosystem some amount of lead time is desirable to ensure a critical mass of
Parquet implementations support a feature.  Therefore, the Parquet PMC gives the
following guidance for changing a feature to be "on" by default:

1. Backwards compatibility is the concern of implementations but given the
   ubiquity of Parquet and the length of time it has been used, libraries SHOULD
   support reading older version of the formats to the greatest extent possible.

2. Forward compatible features/changes MAY be used by default in implementations
   once the parquet-format containing those changes has been formally released.
   For features that may pose a significant performance regression to prior
   format readers, libaries SHOULD consider delaying until 1 year after the
   release of the parquet-java implementation that contains the feature
   implementation.  Implementations MAY choose to do a major version bump when
   turning on a feature in this category.

3. Forwards incompatible features/changes MAY be made default 2 years after the
   parquet-java implementation containing the feature is released.
   Implementations MUST do a major version bump when enabling a forward
   incompatible feature by default.

For forward compatible changes which have a high chance or performance
regression for older readers and forward incompatible changes implementations
SHOULD clearly document the compatibility issues and SHOULD consider also
logging a warning when such a feature is used. Additionally, while it is up to
maintainers of individual implementations to make the best decision to serve
their ecosystem they are encouraged to start enabling features by default along
the same timelines as parquet-java.  Parquet-java will aim to enable features
based on the most conservative timelines outlined above.

For features released prior to October 2024, target dates for each of these
categories will be updated as part of the parquet-java 2.0 process based on a
collected feature compatibility matrix.

For each release of parquet-java or parquet-format that influences this guidance
it is expected exact dates will be added to parquet-format to provide clarity to
implementors (e.g. When parquet-java 2.X.X is released, any new format features
it uses will be updated with concrete dates).

End users of software are generally encouraged to follow the same guidance
unless they have mechanisms for ensuring the version of all possible readers of
the Parquet files support the feature they want to enable. One way of doing this
is to cross-reference feature matrix and any relevant vendor documentation.
