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

Recommendations and requirements for how to best contribute to Parquet. We strive to obey these as best as possible. As always, thanks for contributing--we hope these guidelines make it easier and shed some light on our approach and processes. If you believe there should be a change or exception to these rules please bring it up for discussion on the developer mailing list (dev@parquet.apache.org).

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
semantics of the specification can be done as long as a committer feels comfortable
to merge them. When in doubt starting a discussion on the dev mailing list is
encouraged.

The general steps for adding features to the format are as follows:

1. Design/scoping: The goal of this phase is to identify design goals of a
   feature and provide some demonstration that the feature meets those goals.
   This phase starts with a discussion of changes on the developer mailing list
   (dev@parquet.apache.org). Depending on the scope and goals of the feature the
   it can be useful to provide additional artifacts as part of a discussion. The
   artifacts can include a design docuemnt, a draft pull request to make the
   discussion concrete and/or an prototype implementation to demostrate the
   viability of implementation. This step is complete when there is lazy
   consensus. Part of the consensus is whether it is sufficient to provide two
   working implementations as outlined in step 2, or if demonstration of the
   feature with a downstream query engine is necessary to justify the feature
   (e.g.  demonstrate performance improvements in the Apache Arrow C++ Dataset
   library, the Apache DataFusion query engine, or any other open source
   engine).

2. Completeness: The goal of this phase is to ensure the feature is viable,
   there is no ambiguity in its specification by demonstrating compatibility
   between implementations. Once a change has lazy consensus, two
   implementations of the feature demonstrating interopability must also be
   provided.  One implementation MUST be
   [`parquet-java`](http://github.com/apache/parquet-java).  It is preferred
   that the second implementation be
   [`parquet-cpp`](https://github.com/apache/arrow) or
   [`parquet-rs`](https://github.com/apache/arrow-rs), however at the discretion
   of the PMC any open source Parquet implementation may be acceptable.
   Implementations whose contributors actively participate in the community
   (e.g. keep their feature matrix up-to-date on the Parquet website) are more
   likely to be considered. If discussed as a requirement in step 1 above,
   demonstration of integration with a query engine is also required for this
   step. The implementations must be made available publicly, and they should be
   fit for inclusion (for example, they were submitted as a pull request against
   the target repository and committers gave positive reviews). Reports on the
   benefits from closed source implementations are welcome and can help lend
   weight to features desirability but are not sufficient for acceptance of a
   new feature.

Unless otherwise discussed, it is expected the implementations will be developed
from their respective main branch (i.e. backporting is not required), to
demonstrate that the feature is mergeable to its implementation.

3. Ratification: After the first two steps are complete a formal vote is held on
   dev@parquet.apache.org to officially ratify the feature.  After the vote
   passes the format change is merged into the `parquet-format` repository and
   it is expected the changes from step 2 will also be merged soon after
   (implementations should not be merged until the addition has been merged to
   `parquet-format`).

#### General guidelines/preferences on additions.

1. To the greatest extent possible changes should have an option for forward
   compatibility (old readers can still read files). The [compatibility and
   feature enablement](#compatibility-and-feature-enablement) section below 
   provides more details on expectations for changes that break compatibility.

2. New encodings should be fully specified in this repository and not
   rely on an external dependencies for implementation (i.e. `parquet-format` is
   the source of truth for the encoding). If it does require an
   external dependency, then the external dependency must have its
   own specification separate from implementation.

3. New compression mechanisms should have a pure Java implementation that can be
   used as a dependency in `parquet-java`, exceptions may be
   discussed on the mailing list to see if a non-native Java
   implementation is acceptable.

### Releases

The Parquet PMC aims to do releases of the format package only as needed when
new features are introduced. If multiple new features are being proposed
simultaneously some features might be consolidated into the same release.
Guidance is provided below on when implementations should enable features added
to the specification.  Due to confusion in the past over Parquet versioning it
is not expected that there will be a 3.x release of the specification in the
foreseeable future.

### Compatibility and Feature Enablement

For the purposes of this discussion we classify features into the following buckets:

1. Backward compatible. A file written under an older version of the format
   should be readable under a newer version of the format.

2. Forward compatible. A file written under a newer version of the format with
   the feature enabled can be read under an older version of the format, but
   some metadata might be missing or performance might be suboptimal. Simply
   phrased, forward compatible means all data can be read back in an older
   version of the format. New logical types are considered forward
   compatible despite the loss of semantic meaning.

3. Forward incompatible. A file written under a newer version of the format with
   the feature enabled cannot be read under an older version of the format (e.g.
   adding and using a new compression algorithm). It is expected any feature in
   this category will provide a signal to older readers, so they can
   unambiguously determine that they cannot properly read the file (e.g. via
   adding a new value to an existing enum).

New features are intended to be widely beneficial to users of Parquet, and
therefore it is hoped third-party implementations will adopt them quickly after
they are introduced. It is assumed that writing new parts of the format, and
especially forward incompatible features, will be configured with a feature flag
defaulted to "off", and at some future point the feature is turned on by default
(reading of the new feature will typically be enabled without configuration or
defaulted to on). Some amount of lead time is desirable to ensure a critical
mass of Parquet implementations support a feature to avoid compatibility issues
across the ecosystem.  Therefore, the Parquet PMC gives the following
recommendations for managing features:

1. Backward compatibility is the concern of implementations but given the
   ubiquity of Parquet and the length of time it has been used, libraries should
   support reading older versions of the format to the greatest extent possible.

2. Forward compatible features/changes may be enabled and used by default in
   implementations once the parquet-format containing those changes has been
   formally released.  For features that may pose a significant performance
   regression to older format readers, libaries should consider delaying default
   enablement until 1 year after the release of the parquet-java implementation
   that contains the feature implementation.

3. Forward incompatible features/changes should not be turned on by default
   until 2 years after the parquet-java implementation containing the feature is
   released. It is recommended that changing the default value for a forward
   incompatible feature flag should be clearly advertised to consumers (e.g. via
   a major version release if using Semantic Versioning, or highlighed in
   release notes).

For forward compatible changes which have a high chance of performance
regression for older readers and forward incompatible changes, implementations
should clearly document the compatibility issues. Additionally, while it is up
to maintainers of individual open-source implementations to make the best decision to serve
their ecosystem, they are encouraged to start enabling features by default along
the same timelines as `parquet-java`. Parquet-java will wait to enable features
by default until the most conservative timelines outlined above have been
exceeded. This timeline is an attempt to balance ensuring
new features make their way into the ecosystem and avoiding
breaking compatiblity for readers that are slower to adopt new standards. We
encourage earlier adoption of new features when an organization using Parquet
can guarantee that all readers of the parquet files they produce can read a new
feature.

After turning a feature on by default implementations
are encouraged to keep a configuration to turn off the feature.
A recommendation for full deprecation will be made in a future
iteration of this document.

For features released prior to October 2024, target dates for each of these
categories will be updated as part of the `parquet-java 2.0` release process
based on a collected feature compatibility matrix.

For each release of `parquet-java` or `parquet-format` that influences this
guidance it is expected exact dates will be added to parquet-format to provide
clarity to implementors (e.g. When `parquet-java` 2.X.X is released, any new
format features it uses will be updated with concrete dates). As part of
`parquet-format` releases the compatibility matrix will be updated to contain
the release date in the format. Implementations are also encouraged to provide
implementation date/release version information when updating the feature
matrix.

End users of software are generally encouraged to consult the feature matrix
and vendor documentation before enabling features that are not yet widely
adopted.
