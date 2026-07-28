# Analysis function catalog

Generated from the executable registry. `verified` means the function completed a smoke test; `conditional` means implementation is present but extra inputs or sample size are required.

| Function | Category | Status | Declared parameters | Requirements |
|---|---|---|---|---|
| `cir-barplot-micro` | composition | blocked | comp_top_n, cuttree, dist, hcluter_method | Compatibility smoke test failed: cir-barplot-micro/all_samples |
| `cir-plot-micro` | composition | blocked | comp_tax_level, comp_top_n | Compatibility smoke test failed: cir-plot-micro/all_samples |
| `clumicro-bar-micro` | other | blocked | comp_tax_level, comp_top_n, cuttree, dist, hcluter_method | Compatibility smoke test failed: clumicro-bar-micro/all_samples |
| `cluster-micro` | beta_diversity | blocked | cuttree, distance_method, hcluter_method | Compatibility smoke test failed: cluster-micro/all_samples |
| `distance-micro` | beta_diversity | blocked | — | Compatibility smoke test failed: distance-micro/all_samples |
| `ggflower-micro` | composition | verified | — | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `ggven-upset-micro` | composition | blocked | — | Compatibility smoke test failed: ggven-upset-micro/all_samples |
| `mantal-micro` | network | blocked | beta_mantel_method, distance_method, plot_dpi | Compatibility smoke test failed: mantal-micro/all_samples |
| `maptree-micro` | other | blocked | comp_top_n, seed | Compatibility smoke test failed: maptree-micro/all_samples |
| `ordinate-micro` | beta_diversity | blocked | beta_ordination_method, distance_method, microtest_method, p_cutoff | Compatibility smoke test failed: ordinate-micro/all_samples |
| `sankey-m-group-micro` | composition | blocked | comp_top_n | Compatibility smoke test failed: sankey-m-group-micro/all_samples |
| `sankey-micro` | composition | blocked | comp_top_n | Compatibility smoke test failed: sankey-micro/all_samples |
| `script-alpha` | alpha_diversity | verified | alpha_metrics, alpha_sig_label, color_theme, exclude_groups, group_col, index_types, ncol, plot_dpi, plot_height, plot_width, rarefy_depth, rarefy_method, seed, x_label | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `script-alpha-pd` | alpha_diversity | verified | alpha_metrics, alpha_sig_label, ncol | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `script-alpha-rarefaction` | alpha_diversity | blocked | — | Compatibility smoke test failed: script-alpha-rarefaction/all_samples |
| `script-bagging` | biomarker_ml | verified | — | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `script-barplot` | composition | verified | comp_tax_level, comp_top_n | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `script-bnti` | community_assembly | blocked | filter_top_n, min_taxa_sum, permutations, threads | Compatibility smoke test failed: script-bnti/all_samples |
| `script-bnti-rcbray` | community_assembly | blocked | filter_top_n, min_taxa_sum, permutations, threads | Compatibility smoke test failed: script-bnti-rcbray/all_samples |
| `script-decision-tree` | biomarker_ml | verified | — | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `script-deseq2` | differential_abundance | verified | filter_top_n, tax_level | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `script-edger` | differential_abundance | blocked | filter_top_n, tax_level | Compatibility smoke test failed: script-edger/all_samples |
| `script-feast` | community_assembly | verified | sink_group, source_groups | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `script-function-bubble` | functional_prediction | blocked | filter_top_n, ko_column | Compatibility smoke test failed: script-function-bubble/all_samples |
| `script-function-diff` | differential_abundance | blocked | filter_top_n, ko_column | Compatibility smoke test failed: script-function-diff/all_samples |
| `script-heatmap` | composition | verified | comp_tax_level, feature_top_n, heatnum | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `script-kegg-enrich` | functional_prediction | blocked | filter_top_n, ko_column | Compatibility smoke test failed: script-kegg-enrich/all_samples |
| `script-lasso` | biomarker_ml | verified | — | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `script-lda` | biomarker_ml | verified | — | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `script-loading-pca` | beta_diversity | verified | top_n | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `script-manhattan` | differential_abundance | blocked | filter_top_n, lfc_cutoff, p_cutoff | Compatibility smoke test failed: script-manhattan/all_samples |
| `script-microtest` | beta_diversity | blocked | distance_method, microtest_method | Compatibility smoke test failed: script-microtest/all_samples |
| `script-naive-bayes` | biomarker_ml | verified | — | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `script-network` | network | blocked | big_network, cluster_method, cor_cutoff, fill_rank, layout_net, maxnode, ncpus, p_cutoff, random_times, show_label, step, top_n | Compatibility smoke test failed: script-network/all_samples |
| `script-network-properties` | network | blocked | big_network, cluster_method, cor_cutoff, fill_rank, layout_net, maxnode, ncpus, p_cutoff, random_times, step, top_n | Compatibility smoke test failed: script-network-properties/all_samples |
| `script-network-robustness` | network | blocked | big_network, cluster_method, cor_cutoff, fill_rank, layout_net, maxnode, ncpus, p_cutoff, random_times, robustness_end, robustness_random_top, robustness_start, step, top_n | Compatibility smoke test failed: script-network-robustness/all_samples |
| `script-network-stability` | network | blocked | big_network, cluster_method, cor_cutoff, fill_rank, layout_net, maxnode, ncpus, p_cutoff, random_times, step, top_n | Compatibility smoke test failed: script-network-stability/all_samples |
| `script-neutral-model` | community_assembly | verified | — | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `script-nnet` | biomarker_ml | verified | — | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `script-nullmodel` | community_assembly | verified | distance_method, gamma_method, min_taxa_sum, null_model, transfer | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `script-pair-microtest` | beta_diversity | blocked | distance_method, pair_method | Compatibility smoke test failed: script-pair-microtest/all_samples |
| `script-pca` | beta_diversity | blocked | top_n | Compatibility smoke test failed: script-pca/all_samples |
| `script-random-forest` | biomarker_ml | verified | — | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `script-rarefaction` | alpha_diversity | verified | alpha_rarefaction_metric, alpha_rarefaction_start | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `script-rcbray` | community_assembly | blocked | filter_top_n, min_taxa_sum, permutations, threads | Compatibility smoke test failed: script-rcbray/all_samples |
| `script-rfcv` | biomarker_ml | verified | — | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `script-roc` | biomarker_ml | verified | — | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `script-stamp` | differential_abundance | blocked | tax_rank, top_n | Compatibility smoke test failed: script-stamp/all_samples |
| `script-svm` | biomarker_ml | verified | — | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `script-ternary` | composition | verified | tax_rank, ternary_groups, top_n | Completed compatibility smoke testing; input-specific prerequisites still apply. |
| `script-venn` | composition | blocked | — | Compatibility smoke test failed: script-venn/all_samples |
| `script-volcano` | differential_abundance | blocked | tax_level | Compatibility smoke test failed: script-volcano/all_samples |
| `script-volcano-specific` | differential_abundance | blocked | case_group, cluster_k, control_group, tax_level | Compatibility smoke test failed: script-volcano-specific/all_samples |
| `ven-network-micro` | composition | blocked | comp_tax_level, venn_network_n | Compatibility smoke test failed: ven-network-micro/all_samples |
| `vensuper-micro` | composition | verified | venn_detail_num | Completed compatibility smoke testing; input-specific prerequisites still apply. |
