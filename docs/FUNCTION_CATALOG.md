# Analysis function catalog

Generated from the executable registry. `verified` means the function completed a smoke test; `conditional` means implementation is present but extra inputs or sample size are required.

| Function | Category | Status | Declared parameters | Requirements |
|---|---|---|---|---|
| `cir-barplot-micro` | composition | verified | tax_rank, top_n | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `cir-plot-micro` | composition | verified | tax_rank, top_n | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `clumicro-bar-micro` | composition | verified | tax_rank, top_n | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `cluster-micro` | beta_diversity | verified | distance_method, microtest_method, permutations | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `distance-micro` | beta_diversity | verified | distance_method, microtest_method, permutations | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `ggflower-micro` | composition | verified | tax_rank, top_n | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `ggven-upset-micro` | composition | verified | tax_rank, top_n | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `mantal-micro` | beta_diversity | verified | distance_method, microtest_method, permutations | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `maptree-micro` | composition | verified | tax_rank, top_n | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `ordinate-micro` | beta_diversity | verified | distance_method, microtest_method, permutations | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `sankey-m-group-micro` | composition | verified | tax_rank, top_n | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `sankey-micro` | composition | verified | tax_rank, top_n | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `script-alpha` | alpha_diversity | verified | alpha_metrics, alpha_sig_label, color_theme, exclude_groups, group_col, index_types, ncol, plot_dpi, plot_height, plot_width, rarefy_depth, rarefy_method, seed, x_label | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `script-alpha-pd` | alpha_diversity | verified | alpha_metrics, alpha_sig_label, ncol, rarefy_depth, rarefy_method | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `script-alpha-rarefaction` | alpha_diversity | verified | alpha_metrics, rarefy_depth, rarefy_method | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `script-bagging` | biomarker_ml | verified | folds, optimal, seed | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `script-barplot` | composition | verified | comp_tax_level, comp_top_n, tax_rank, top_n | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `script-bnti` | community_assembly | verified | min_taxa_sum, permutations, threads | Verified abundance-weighted betaNTI with phylogenetic tip-label randomization. |
| `script-bnti-rcbray` | community_assembly | verified | min_taxa_sum, permutations, threads | Verified betaNTI plus modified Raup-Crick Bray-Curtis workflow. |
| `script-decision-tree` | biomarker_ml | verified | folds, optimal, seed | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `script-deseq2` | differential_abundance | verified | adjust_p, filter_top_n, lfc_cutoff, p_cutoff, tax_level | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `script-edger` | differential_abundance | verified | adjust_p, lfc_cutoff, p_cutoff, tax_level | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `script-feast` | community_assembly | verified | min_taxa_sum, permutations, threads | Verified constrained nonnegative source-contribution estimator. This is a transparent local approximation and not the original FEAST algorithm. |
| `script-function-bubble` | functional_prediction | verified | filter_top_n, ko_column | Verified predicted-KO rank-based differential bubble plot. |
| `script-function-diff` | functional_prediction | verified | filter_top_n, ko_column | Verified predicted-KO rank-based differential analysis. |
| `script-heatmap` | composition | verified | comp_tax_level, feature_top_n, heatnum, tax_rank, top_n | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `script-kegg-enrich` | functional_prediction | verified | filter_top_n, ko_column | Verified offline KO-to-Pathway Fisher over-representation analysis. |
| `script-lasso` | biomarker_ml | verified | folds, optimal, seed | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `script-lda` | biomarker_ml | verified | folds, optimal, seed | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `script-loading-pca` | beta_diversity | verified | distance_method, microtest_method, permutations, top_n | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `script-manhattan` | differential_abundance | verified | adjust_p, lfc_cutoff, p_cutoff, tax_level | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `script-microtest` | beta_diversity | verified | distance_method, microtest_method, permutations | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `script-naive-bayes` | biomarker_ml | verified | folds, optimal, seed | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `script-network` | network | verified | cor_cutoff, p_cutoff, random_times, top_n | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `script-network-properties` | network | verified | cor_cutoff, p_cutoff, random_times, top_n | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `script-network-robustness` | network | verified | cor_cutoff, p_cutoff, random_times, top_n | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `script-network-stability` | network | verified | cor_cutoff, p_cutoff, random_times, top_n | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `script-neutral-model` | community_assembly | verified | min_taxa_sum, permutations, threads | Verified self-contained Sloan neutral-community model. |
| `script-nnet` | biomarker_ml | verified | folds, optimal, seed | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `script-nullmodel` | community_assembly | verified | min_taxa_sum, permutations, threads | Verified group-label permutation null model for between-minus-within Bray distance. |
| `script-pair-microtest` | beta_diversity | verified | distance_method, microtest_method, permutations | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `script-pca` | beta_diversity | verified | distance_method, microtest_method, permutations | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `script-random-forest` | biomarker_ml | verified | folds, optimal, seed | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `script-rarefaction` | alpha_diversity | verified | alpha_metrics, alpha_rarefaction_metric, alpha_rarefaction_start, rarefy_depth, rarefy_method | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `script-rcbray` | community_assembly | verified | min_taxa_sum, permutations, threads | Verified modified Raup-Crick Bray-Curtis null model. |
| `script-rfcv` | biomarker_ml | verified | folds, optimal, seed | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `script-roc` | biomarker_ml | verified | folds, optimal, seed | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `script-stamp` | differential_abundance | verified | adjust_p, lfc_cutoff, p_cutoff, tax_level | Verified rank-based abundance-difference view with Wilcoxon tests and BH correction. |
| `script-svm` | biomarker_ml | verified | folds, optimal, seed | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `script-ternary` | composition | verified | tax_rank, ternary_groups, top_n | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `script-venn` | composition | verified | tax_rank, top_n | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `script-volcano` | differential_abundance | verified | adjust_p, lfc_cutoff, p_cutoff, tax_level | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `script-volcano-specific` | differential_abundance | verified | adjust_p, lfc_cutoff, p_cutoff, tax_level | Verified rank-based volcano analysis with Wilcoxon tests and BH correction. |
| `ven-network-micro` | composition | verified | tax_rank, top_n | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `vensuper-micro` | composition | verified | tax_rank, top_n | Completed compatibility smoke testing; input-specific prerequisites still apply. |
