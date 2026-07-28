# Function validation status

Validation date: 2026-07-28  
R runtime: 4.5.1  
Example: `examples/comprehensive` (36 samples, 3 groups, 60 features, taxonomy with KO, tree and representative sequences)

## Results

- Registered functions exercised: 55/55
- Verified after the comprehensive run and targeted ML rerun: 23
- Blocked by real compatibility failures: 32
- Machine-learning functions verified: 11/11
- Python regression tests: 11 passed
- Successful ML report: 25 embedded figures, all `.png`; zero PDF files without a PNG sibling

Verified:

`script-alpha`, `script-rarefaction`, `script-barplot`, `ggflower-micro`,
`script-alpha-pd`, `script-bagging`, `script-decision-tree`, `script-deseq2`,
`script-feast`, `script-heatmap`, `script-lasso`, `script-lda`,
`script-loading-pca`, `script-naive-bayes`, `script-neutral-model`,
`script-nnet`, `script-nullmodel`, `script-random-forest`, `script-rfcv`,
`script-roc`, `script-svm`, `script-ternary`, `vensuper-micro`.

Blocked:

`ordinate-micro`, `script-microtest`, `cir-barplot-micro`, `cir-plot-micro`,
`clumicro-bar-micro`, `cluster-micro`, `distance-micro`,
`ggven-upset-micro`, `mantal-micro`, `maptree-micro`,
`sankey-m-group-micro`, `sankey-micro`, `script-alpha-rarefaction`,
`script-bnti`, `script-bnti-rcbray`, `script-edger`,
`script-function-bubble`, `script-function-diff`, `script-kegg-enrich`,
`script-manhattan`, `script-network`, `script-network-properties`,
`script-network-robustness`, `script-network-stability`,
`script-pair-microtest`, `script-pca`, `script-rcbray`, `script-stamp`,
`script-venn`, `script-volcano`, `script-volcano-specific`,
`ven-network-micro`.

Blocked does not mean the scientific method is unavailable. It means the
current file still depends on a missing wrapper, incompatible package API, or
an unresolved runtime error. The MCP planner refuses to select blocked
functions. Exact machine-readable status is stored in
`r/functions/compatibility.json`.

## Reproduce

```powershell
$env:PYTHONPATH = "src"
python scripts/generate_comprehensive_example.py
Rscript r/check_dependencies.R dependency_status.csv
python scripts/smoke_test_all_functions.py --output function_smoke_summary.json
python scripts/update_compatibility_from_manifest.py function_smoke_summary.json
python -m pytest -q
```

The smoke run intentionally continues through every function and records
failures instead of stopping at the first error.
