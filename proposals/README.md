# Proposals

## Requirements

See the [requirements document](https://docs.google.com/document/d/1qGDnOyoNyPvcN4FCRhbZGAvp0SfewlWo-WVsai5IKUo/edit?tab=t.0#heading=h.v4emiipkghrx) (Note: this doc would become a markdown page in the repo)

## Proposal lifecycle

Discuss -> Draft -> POC -> Approved -> Implementation -> Release

### Discuss
Start a [DISCUSS] thread on the mailing list (dev@parquet.apache.org) with your idea.
Once you have a better idea of the direction, open a github issue using the proposal template.
You can attach a google doc to collaborate on the general idea with the community.

### Draft
Once the discussion has stabilized and you are ready to start a POC, open a PR to add a new Markdown file in the proposals folder and give more visibility to the work in progress.

### POC
The proposal document can evolve along the course of the POC. In particular to add more links to findings and performance evaluations. Collaboration is encouraged. More validation on the POC increases the chances of success.

Make sure you consider the [#Requirements] to ensure the success of the POC.

### Approved for Implementation
Once the POC has concluded, we should have a clear idea of whether we want to pursue the implementation accross the ecosystem. A PMC vote will formalize that stage

### Implementation
At this stage we need to meet the contribution guidelines to confsider the implementation finished (ex: two independent implementations with cross compatibility tests, spec updated, ...)

### Release
Once the implementation phase is finished, we can include the contribution in the next release. 

## Active Proposals 

| ID | Description | Status |
| [github issue] | adding this new encoding | POC |
| [github issue] | add Variant typea | Implementation |

## Implemented
 | ID | Description | Status | release it was added |
| [gihub issue] | encryption | Completed |  x.y.z | 

## Archived

| ID | Description | Status | reason for archiving |
| [github issue] | [adding base64 compression](1_BASE64_ENCODING.md) | Archived | POC showed that compression ratio was not practical | 

