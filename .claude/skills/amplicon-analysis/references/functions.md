# Analysis function routing

Call `list_amplicon_analysis_functions` before selecting an analysis function. Treat status as follows:

- `verified`: allow in an approved production run when design requirements are met.
- `registered_untested`: explain the risk and test on example data first.
- `conditional`: execute only when its stated input and sample-size prerequisites are met.
- `blocked`: do not include in a plan; use the stated fallback.

Use these categories:

- `alpha_diversity`: diversity indices, phylogenetic diversity, and rarefaction.
- `beta_diversity`: ordination, distance, clustering, and group tests.
- `composition`: abundance plots, heatmaps, Venn/UpSet, Sankey, and ternary views.
- `differential_abundance`: DESeq2, edgeR, STAMP, and volcano/Manhattan views.
- `biomarker_ml`: random forest, SVM, LASSO, LDA, and classification diagnostics.
- `network`: construction, properties, stability, and robustness.
- `community_assembly`: betaNTI, RCbray, neutral/null models, and source tracking.
- `functional_prediction`: KEGG enrichment and function summaries.

Run functions in batch-specific workspaces when `batch_column` is present. Do not use
machine-learning functions with very small groups without nested resampling. Do not use
network comparison functions unless each batch/group has enough independent samples. Do not
interpret predicted function as measured metagenomic function.

Pass a phylogenetic tree through `tree` for PD/bNTI functions and representative sequences
through `representative_sequences` when required. Pass function-specific settings through
`function_parameters`; source tracking requires `sink_group` and `source_groups`. Treat every
supplementary file and parameter change as a new contract requiring approval.
