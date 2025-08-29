# Proposals

This proposal process is intended for significantly impactfull additions to the Parquet spec. The goal is to facilitate those projects and help them being contributed to Parquet.
For example, changes that are not backward compatible like adding a new encoding or a new compression algorithm (older implementations can not read new files).
This gives better visibility to those projects which require coordination in several implementations.
Bug fixes, code only features or minor changes to the spec that can be ignored by older implementations can simply be filed as a github issue.

## Proposal lifecycle

Discuss -> Draft/POC -> Implementation -> Approval

### Discuss
Start a [DISCUSS] thread on the mailing list (dev@parquet.apache.org) with your idea. At this point, the community can discuss whether the impact of the proposal requires a document here or just be a github issue.
Once you have a better idea of the general consensus on the proposal, open a github issue using the proposal template.
Attaching a google doc to collect feedback and collaborate with the community works usually well early on.

*Transition:* Once you feel you received enough feedback or need to start the POC to have better answers to questions you get, you can move to the next step. Anybody is free to start POCs anytime. We just recommend getting feedback before you spend a significant amount of your time.

### Draft/POC
Once you feel the discussion has stabilized and you are ready to start a POC, open a PR to add a new Markdown file in the proposals folder and give more visibility to the work in progress.
The proposal document can evolve along the course of the POC. In particular to add more links to findings and performance evaluations. Collaboration is encouraged. More validation on the POC increases the chances of success.

Example: [https://github.com/apache/parquet-format/pull/221]

Make sure you consider the [requirements document](https://docs.google.com/document/d/1qGDnOyoNyPvcN4FCRhbZGAvp0SfewlWo-WVsai5IKUo/edit?tab=t.0#heading=h.v4emiipkghrx)  to ensure the success of the POC. (Note: this doc would become a markdown page in the repo)

*Transition:* There is enough clarity on the spec for the new feature and we have identified the reference implementations to be implemented to be able to release.

### Implementation
Once we have reached enough consensus on the formalized spec change and validated it through the POC, we should have a clear idea of whether we want to pursue the implementation accross the ecosystem. 
At this stage we should finalize a formal spec contribution to parquet-format and we need to meet the contribution guidelines to consider the implementation finished. 
See [CONTRIBUTING guidelines](https://github.com/apache/parquet-format/blob/master/CONTRIBUTING.md#additionschanges-to-the-format).

*Transition:* A PMC vote will formalize that we have concluded the implementation and are ready to release.

### Approval
Once the implementation phase is finished, we can include the contribution in the next release. Congrats!

## Active Proposals 

| ID  | Description  | Status  |
|-----|--------------|---------|
| [github issue] | adding this new encoding | POC |
| [github issue] | add Variant type | Implementation |

## Implemented
| ID  | Description  | Status  | release it was added  |
|-----|--------------|---------|-----------------------|
| [gihub issue] | encryption | Completed |  x.y.z | 

## Archived

| ID  | Description  | Status  | reason for archiving  |
|-----|--------------|---------|-----------------------|
| [github issue] | [adding base64 compression](1_BASE64_ENCODING.md) | Archived | POC showed that compression ratio was not practical | 

