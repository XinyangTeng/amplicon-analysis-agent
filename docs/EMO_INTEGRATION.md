# EMO function integration

The team-authorized source functions are currently stored in:

- `E:/桌面/生信agent/R`
- original exploratory pipeline: `F:/GitHub/EasyMultiOmics/pipeline/1.pipeline.amp.pro.R`

The prototype deliberately does not vendor the whole function directory. Its baseline QC,
alpha, beta, and composition implementation is a small deterministic runner using `vegan`
and `ggplot2`. This keeps the first release runnable and testable while the EMO functions
are reviewed one module at a time.

Candidate adapters for the next iteration:

| Agent module | EMO source candidate | Integration rule |
|---|---|---|
| Alpha diversity | `R/script_alpha.R` | Extract pure plotting/statistics functions; remove interactive state |
| Beta ordination | `R/ordinate.micro.R` | Preserve method defaults and expose them in the contract |
| Composition | `R/script_barplot.R` | Extract rank aggregation and plotting functions |
| Shared preprocessing | `R/amp_common.R` | Reuse only helpers without hidden global variables |

Every copied function must record the source file, author/copyright owner, source commit or
snapshot date, and a concise modification log in its file header. Authorization to use and
publish these team functions was provided by the project owner; final public release still
requires the repository owner to confirm the definitive license and author list.
