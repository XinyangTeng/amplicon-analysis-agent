# Project-specific interpretation

Use only validated structured results and the confirmed design contract. Write `interpretation.json` with `save_analysis_interpretation`.

Required fields: `project_summary`, `key_findings`, `section_interpretations`, `supported_conclusions`, `unsupported_conclusions`, `limitations`, and `next_steps`.

Every finding must cite a statistic, table, or figure and distinguish observation, statistical result, biological interpretation, and follow-up hypothesis. Do not call a non-significant result “no effect”; do not call classifier importance causal biomarkers; disclose significant dispersion alongside PERMANOVA.

For networks, report the transformation, filtering, association and sparsification rules,
sample count, retained taxa, edge stability or comparison permutations, and FDR threshold.
Separate network topology differences from individual differential associations. Never infer
cooperation, competition, causality, or physical interaction from positive/negative edges alone.
When Spearman correlations are used, disclose that association p-values and between-group
Fisher-z comparisons are approximation-based exploratory evidence.

For differential-abundance results, name the backend method and preprocessing, report effect
size and FDR, and distinguish consensus across methods from method-specific discoveries. Do not
count the same signal from several correlated methods as independent replication. For LEfSe,
sPLS-DA, SIAMCAT and WGCNA, use “candidate feature/module” language unless an independent cohort
or held-out validation confirms performance. For breakaway, report confidence intervals and flag
unstable estimates. For predicted functional profiles, state the reference database and that the
result is inferred rather than directly measured.
