# EMO module routing

Use `list_amplicon_analysis_modules` before selecting an EMO module. Treat status as follows:

- `verified`: eligible for an approved production run.
- `registered_untested`: visible for development, but explain the risk and test on demo data first.
- `conditional`: implementation is registered, but execute only when its stated input and sample-size prerequisites are met.
- `blocked`: do not include in a plan; use the stated fallback.

Categories:

- `alpha_diversity`: diversity indices, phylogenetic diversity and rarefaction.
- `beta_diversity`: ordination, distance, clustering and group tests.
- `composition`: abundance plots, heatmaps, Venn/UpSet, Sankey and ternary views.
- `differential_abundance`: DESeq2, edgeR, STAMP and volcano/Manhattan views.
- `biomarker_ml`: random forest, SVM, LASSO, LDA and classification diagnostics.
- `network`: construction, properties, stability and robustness.
- `community_assembly`: betaNTI, RCbray, neutral/null models and source tracking.
- `functional_prediction`: KEGG enrichment and function summaries.

Run EMO modules inside batch-specific workspaces whenever `batch_column` is present. Do not
use machine-learning modules with very small groups without nested resampling. Do not use
network comparison modules unless each batch/group has enough independent samples. Do not
interpret function prediction as measured metagenomic function.

Pass a phylogenetic tree through `tree` for PD/bNTI modules and representative sequences through
`representative_sequences` when required. Pass module-specific settings through
`module_parameters`; source tracking requires `sink_group` and `source_groups`. Treat every
supplementary file and parameter change as a new contract requiring approval.
