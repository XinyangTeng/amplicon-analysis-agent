# EMO R module provenance

These scripts are a team-authorized snapshot supplied by the project owner from
`E:/桌面/生信agent/R` on 2026-07-22. They were derived from the EasyMultiOmics
analysis workflow maintained by the user's team.

Repository integration changes:

- copied the 56 supplied R files as a versioned snapshot;
- made optional legacy packages load only when installed in `amp_common.R`;
- execute modules only through the Agent contract, workspace sandbox, dependency
  preflight, approval token, run log, and output validation;
- do not claim authorship of the original statistical or plotting functions.

Before a public tagged release, the repository owner must replace this snapshot
date with the originating commit identifier and confirm the complete author and
copyright list.
