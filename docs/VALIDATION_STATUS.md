# Function validation status

Validation date: 2026-08-15
R runtime: 4.5.1
Example: `examples/comprehensive` (36 samples, 3 groups, 60 features, KO and Pathway annotation, resolved tree, representative sequences)
Docker image: `amplicon-analysis-agent:0.6.0`

## Final result

- Registered functions exercised in one approved Docker contract: 72/72 succeeded
- Original registered functions: 55/55
- Independently implemented network extensions: 2/2
- Package-backed extensions: 15/15
- Compatibility registry: 66 `verified`, 6 `conditional`, 0 `blocked`
- R packages loaded inside the image: 59/59
- Python regression tests: 40 passed
- Expert Skill validation: passed
- Domain validation: passed
- Embedded report figures: 100, all `.png`
- Result CSV/TSV tables indexed for on-demand interpretation: 179
- Result workbooks: 26 `.xlsx`
- PDF files without a same-name PNG: 0
- Report status: generated and readable
- Validation status: `pass`
- Web stack: healthy on host port 8001 with Redis and Celery worker/cleanup services

The full smoke run used one immutable contract and one run directory, so this
result also tests shared workbooks, artifact naming, recursive report assembly,
and cross-function interaction. The report was rebuilt after writing a
structured project-specific interpretation.

Evidence from the full Docker run:

- Plan/run ID: `e684d35e-4e44-4ebd-8d4c-f37c88fd340b`
- Summary: `tmp/container_smoke_summary_v060_round3.json`
- Full manifest: `runs/<run-id>/functions/function_manifest.json`

After the full run, betaNTI plotting was tightened so non-estimable pairs remain
in the result table but are excluded from the histogram. The rebuilt formal
image then passed both betaNTI entry points without warnings. Its audit table
reported 630 total pairs, 603 estimable pairs, and 27 explicitly marked
non-estimable pairs. Final targeted run ID:
`0bdbd14f-4b9d-4a78-bde1-8952bec74b4b`.

## Scientific implementation notes

- Machine learning uses stratified out-of-fold predictions. Random-forest
  recursive feature CV and one-vs-rest ROC are exported as tables and PNG.
- PERMANOVA is always paired with a dispersion test.
- Differential modules state whether they use edgeR, DESeq2, or rank-based
  Wilcoxon tests with BH correction.
- `script-feast` is retained as a stable legacy function ID, but now executes a
  transparent nonnegative constrained source-contribution estimator; it is not
  the original FEAST algorithm.
- KO enrichment is offline Fisher over-representation and requires both `KO`
  and `Pathway` annotation.
- betaNTI requires a resolved tree with non-uniform branch lengths.
- betaNTI exports `Estimable` for every pair and a separate summary table; a
  non-estimable pair is retained for audit rather than silently dropped.
- Network results are association networks and do not imply direct interaction.
- Newly verified package backends include ANCOM-BC2, ALDEx2, MaAsLin2/3, LinDA,
  corncob, metagenomeSeq, LEfSe, breakaway, Generalized UniFrac, CoDA PCA,
  SPIEC-EASI, sPLS-DA, SIAMCAT and WGCNA.
- `FEAST 1.18.0` in this environment is a single-cell feature-selection package,
  not the microbial source-tracking FEAST algorithm.

Exact method notes and dates are stored in
`r/functions/compatibility.json`.

## Reproduce

```powershell
$env:PYTHONPATH = "src"
python scripts/generate_comprehensive_example.py
Rscript r/check_dependencies.R dependency_status.csv
python scripts/smoke_test_all_functions.py --output function_smoke_summary.json
python scripts/update_compatibility_from_manifest.py function_smoke_summary.json
python scripts/export_function_catalog.py
python -m pytest -q
```

The final Docker image was built from the repository Dockerfile, checked for all
59 declared R packages, verified for the `Noto Sans CJK SC` font, and used to
start the healthy web/worker stack. Chinese plot titles are rendered through
Cairo devices; the previous character-conversion warnings are no longer present.
