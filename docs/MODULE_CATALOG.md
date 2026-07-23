# EMO analysis module catalog

Generated from the executable registry. `verified` means the module completed a smoke test; `conditional` means implementation is present but extra inputs or sample size are required.

| Module | Category | Status | Declared parameters | Requirements |
|---|---|---|---|---|
| `cir-barplot-micro` | composition | verified | comp_top_n, cuttree, dist, hcluter_method | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `cir-plot-micro` | composition | verified | comp_tax_level, comp_top_n | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `clumicro-bar-micro` | other | verified | comp_tax_level, comp_top_n, cuttree, dist, hcluter_method | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `cluster-micro` | beta_diversity | verified | cuttree, distance_method, hcluter_method | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `distance-micro` | beta_diversity | verified | — | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `ggflower-micro` | composition | verified | — | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `ggven-upset-micro` | composition | verified | — | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `mantal-micro` | network | conditional | beta_mantel_method, distance_method | network analysis requires at least ten samples in the batch |
| `maptree-micro` | other | verified | comp_top_n, seed | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `ordinate-micro` | beta_diversity | verified | beta_ordination_method, distance_method, microtest_method, p_cutoff | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `sankey-m-group-micro` | composition | verified | comp_top_n | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `sankey-micro` | composition | verified | comp_top_n | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `script-alpha` | alpha_diversity | verified | alpha_metrics, alpha_sig_label, color_theme, exclude_groups, group_col, index_types, ncol, plot_dpi, plot_height, plot_width, rarefy_depth, rarefy_method, seed, x_label | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `script-alpha-pd` | alpha_diversity | conditional | alpha_metrics, alpha_sig_label, ncol | phylogenetic tree is required |
| `script-alpha-rarefaction` | alpha_diversity | verified | — | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `script-bagging` | biomarker_ml | conditional | folds, seed, top_n | machine learning requires at least ten samples per group |
| `script-barplot` | composition | verified | comp_tax_level, comp_top_n | Native phyloseq composition fallback passed after the legacy wrapper failed with current dplyr semantics. |
| `script-bnti` | community_assembly | conditional | filter_top_n, min_taxa_sum, permutations, threads | phylogenetic tree is required |
| `script-bnti-rcbray` | community_assembly | conditional | filter_top_n, min_taxa_sum, permutations, threads | phylogenetic tree is required |
| `script-decision-tree` | biomarker_ml | conditional | folds, seed, top_n | machine learning requires at least ten samples per group |
| `script-deseq2` | differential_abundance | verified | filter_top_n, tax_level | Native DESeq2 dispersion fallback passed after the legacy wrapper failed on low-dispersion demo data. |
| `script-edger` | differential_abundance | verified | filter_top_n, tax_level | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `script-feast` | community_assembly | conditional | sink_group, source_groups | source and sink groups must be configured |
| `script-function-bubble` | functional_prediction | conditional | filter_top_n, ko_column | KO annotation is required |
| `script-function-diff` | differential_abundance | conditional | filter_top_n, ko_column | KO annotation is required |
| `script-heatmap` | composition | verified | comp_tax_level, feature_top_n, heatnum | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `script-kegg-enrich` | functional_prediction | conditional | filter_top_n, ko_column | KO annotation is required |
| `script-lasso` | biomarker_ml | conditional | case_group, control_group, folds, seed, top_n | machine learning requires at least ten samples per group |
| `script-lda` | biomarker_ml | conditional | adjust_p, lda_cutoff, p_cutoff, seed, top_n | machine learning requires at least ten samples per group |
| `script-loading-pca` | beta_diversity | verified | top_n | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `script-manhattan` | differential_abundance | verified | filter_top_n, lfc_cutoff, p_cutoff | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `script-microtest` | beta_diversity | verified | distance_method, microtest_method | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `script-naive-bayes` | biomarker_ml | conditional | folds, seed, top_n | machine learning requires at least ten samples per group |
| `script-network` | network | conditional | big_network, cluster_method, cor_cutoff, fill_rank, layout_net, maxnode, ncpus, p_cutoff, random_times, show_label, step, top_n | network analysis requires at least ten samples in the batch |
| `script-network-properties` | network | conditional | big_network, cluster_method, cor_cutoff, fill_rank, layout_net, maxnode, ncpus, p_cutoff, random_times, step, top_n | network analysis requires at least ten samples in the batch |
| `script-network-robustness` | network | conditional | big_network, cluster_method, cor_cutoff, fill_rank, layout_net, maxnode, ncpus, p_cutoff, random_times, robustness_end, robustness_random_top, robustness_start, step, top_n | network analysis requires at least ten samples in the batch |
| `script-network-stability` | network | conditional | big_network, cluster_method, cor_cutoff, fill_rank, layout_net, maxnode, ncpus, p_cutoff, random_times, step, top_n | network analysis requires at least ten samples in the batch |
| `script-neutral-model` | community_assembly | verified | — | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `script-nnet` | biomarker_ml | conditional | folds, seed, top_n | machine learning requires at least ten samples per group |
| `script-nullmodel` | community_assembly | verified | distance_method, gamma_method, min_taxa_sum, null_model, transfer | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `script-pair-microtest` | beta_diversity | verified | distance_method, pair_method | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `script-pca` | beta_diversity | verified | top_n | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `script-random-forest` | biomarker_ml | conditional | optimal | machine learning requires at least ten samples per group |
| `script-rarefaction` | alpha_diversity | verified | alpha_rarefaction_metric, alpha_rarefaction_start | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `script-rcbray` | community_assembly | verified | filter_top_n, min_taxa_sum, permutations, threads | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `script-rfcv` | biomarker_ml | conditional | filter_top_n, folds, optimal | machine learning requires at least ten samples per group |
| `script-roc` | biomarker_ml | conditional | case_group, control_group, filter_top_n, min_taxa_sum, repnum | machine learning requires at least ten samples per group |
| `script-stamp` | differential_abundance | verified | tax_rank, top_n | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `script-svm` | biomarker_ml | conditional | filter_top_n, folds | machine learning requires at least ten samples per group |
| `script-ternary` | composition | conditional | tax_rank, ternary_groups, top_n | ternary analysis requires at least three groups |
| `script-venn` | composition | verified | — | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `script-volcano` | differential_abundance | verified | tax_level | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `script-volcano-specific` | differential_abundance | verified | case_group, cluster_k, control_group, tax_level | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `ven-network-micro` | composition | verified | comp_tax_level, venn_network_n | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `vensuper-micro` | composition | verified | venn_detail_num | Completed compatibility smoke testing; input-specific prerequisites still apply. |
