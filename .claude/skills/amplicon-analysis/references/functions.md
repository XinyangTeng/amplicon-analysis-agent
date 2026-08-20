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
- `differential_abundance`: ANCOM-BC2, ALDEx2, LinDA, corncob, MaAsLin2/3,
  metagenomeSeq, DESeq2, edgeR, STAMP, and volcano/Manhattan views.
- `biomarker_ml`: LEfSe, sPLS-DA, SIAMCAT, random forest, SVM, LASSO, LDA,
  and classification diagnostics.
- `network`: descriptive correlation networks, compositional networks, modules/hubs,
  stability/robustness, and two-group network comparison.
- `community_assembly`: betaNTI, RCbray, neutral/null models, and source tracking.
- `functional_prediction`: KEGG enrichment and function summaries.

Run functions in batch-specific workspaces when `batch_column` is present. Do not use
machine-learning functions with very small groups without nested resampling. Do not use
network comparison functions unless each selected group has at least 10 independent samples;
prefer 20 or more per group for stable inference. Use `script-network-compositional` as the
default network method because it applies prevalence filtering, pseudocount replacement, CLR,
FDR sparsification, modules, centralities, and hub detection without requiring an additional
network package. Use
`script-network-compare` only for a confirmed two-group contrast; pass `network_group1`,
`network_group2`, and `network_permutations`. Treat network edges as conditional hypotheses,
not direct interactions. Describe both methods as independent reduced implementations inspired
by published network-analysis stages, not as output from an external network package or an exact
drop-in replacement. Do not
interpret predicted function as measured metagenomic function.

For a standard replicated two-group compositional comparison, prefer ANCOM-BC2 plus one
independent sensitivity method such as ALDEx2 or LinDA; do not run every differential method
merely because it is installed. Use MaAsLin2/3 when confirmed covariates, repeated measures,
or multivariable adjustment are central to the question. Use corncob when differential
variability is biologically relevant. Treat LEfSe as exploratory candidate screening.

Use `script-coda-pca` for zero replacement + CLR ordination. Use `script-gunifrac` only with
a matching phylogenetic tree and always interpret PERMANOVA together with PERMDISP. Use
`script-spieceasi` for sparse conditional-dependence networks and `script-wgcna` for taxon
modules; both require adequate replication and cannot prove direct interactions. Use sPLS-DA
or SIAMCAT only with at least 10 samples per selected group, repeated cross-validation, and an
explicit statement that independent validation is still missing.

Tax4Fun2 requires representative sequences plus its external reference database. ggpicrust2
is a downstream analyser for genuine PICRUSt2 functional-abundance outputs; do not apply it
to a taxonomy table or call predicted functions measured metagenomic functions. The installed
package named FEAST is a single-cell feature-selection package, not microbial source tracking.

Pass a phylogenetic tree through `tree` for PD/bNTI functions and representative sequences
through `representative_sequences` when required. Pass function-specific settings through
`function_parameters`; source tracking requires `sink_group` and `source_groups`. Treat every
supplementary file and parameter change as a new contract requiring approval.

The legacy function ID `script-feast` now routes to the repository's self-contained
nonnegative constrained source-contribution estimator. It is not the original FEAST
algorithm and must be described with that limitation in the report.
