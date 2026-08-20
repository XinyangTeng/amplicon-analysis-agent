# Analysis function integration

The repository contains 55 team-authorized R analysis functions plus independently implemented
extension functions under `r/functions/`.
They are ordinary executable scripts, not a separately named package layer.

## Runtime contract

Each function:

- reads normalized `otutab.txt`, `taxonomy.txt`, `metadata.tsv`, and `params.json`;
- runs in a batch-isolated workspace;
- writes tables, figures, PDFs, and logs into its own result directory;
- declares parameters and prerequisites through the Python function registry;
- is executed only after input inspection and one-time approval.

The shared runtime `r/functions/amp_common.R` contains reusable, self-contained method
implementations for diversity, composition, differential analysis, machine learning,
network analysis, assembly models, source contribution, and predicted-function analysis.
The thin function scripts select one method and result directory. This avoids hidden
package wrappers while keeping every function independently callable and auditable.

The lightweight compositional-network extension follows published microbial-network workflow stages
(filtering, zero handling, transformation, association, sparsification, property analysis and
group comparison) but does not copy or import external package source code. It uses installed base
dependencies (`igraph` and R statistics), which avoids optional dependency conflicts.
Method provenance and limitations remain visible in output tables.

## Compatibility states

- `verified`: completed a compatibility smoke test.
- `conditional`: available only when its required data, sample size, tree, annotation, or
  optional implementation is present.
- `registered_untested`: registered but not yet accepted for a production run.
- `blocked`: known to fail and excluded from approved plans.

Compatibility results are stored in `r/functions/compatibility.json` and exposed through
`list_amplicon_analysis_functions` and `inspect_amplicon_function`.

Installed package backends and the distinction between user-facing methods, shared utilities,
and external-database methods are documented in `docs/R_PACKAGE_METHOD_MAP.md`.

## Provenance

The project owner supplied and authorized the function snapshot. Author names, copyright
ownership, and the definitive release license must be confirmed before a tagged public
release. Integration changes must be recorded without claiming authorship of the underlying
statistical or plotting methods.
