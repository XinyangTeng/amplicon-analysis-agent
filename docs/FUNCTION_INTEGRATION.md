# Analysis function integration

The repository contains 55 team-authorized R analysis functions under `r/functions/`.
They are ordinary executable scripts, not a separately named package layer.

## Runtime contract

Each function:

- reads normalized `otutab.txt`, `taxonomy.txt`, `metadata.tsv`, and `params.json`;
- runs in a batch-isolated workspace;
- writes tables, figures, PDFs, and logs into its own result directory;
- declares parameters and prerequisites through the Python function registry;
- is executed only after input inspection and one-time approval.

The shared adapter `r/functions/amp_common.R` handles input loading, parameter aliases,
plot export, workbook output, and optional dependency loading. Individual functions remain
responsible for their own statistical method.

## Compatibility states

- `verified`: completed a compatibility smoke test.
- `conditional`: available only when its required data, sample size, tree, annotation, or
  optional implementation is present.
- `registered_untested`: registered but not yet accepted for a production run.
- `blocked`: known to fail and excluded from approved plans.

Compatibility results are stored in `r/functions/compatibility.json` and exposed through
`list_amplicon_analysis_functions` and `inspect_amplicon_function`.

## Provenance

The project owner supplied and authorized the function snapshot. Author names, copyright
ownership, and the definitive release license must be confirmed before a tagged public
release. Integration changes must be recorded without claiming authorship of the underlying
statistical or plotting methods.
