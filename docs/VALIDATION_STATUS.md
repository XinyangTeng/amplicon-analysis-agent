# Function validation status

Validation date: 2026-07-28  
R runtime: 4.5.1  
Example: `examples/comprehensive` (36 samples, 3 groups, 60 features, KO and Pathway annotation, resolved tree, representative sequences)

## Final result

- Registered functions exercised in one approved contract: 55/55
- Function runs succeeded: 55/55
- Compatibility registry: 55 `verified`, 0 `blocked`
- Python regression tests: 12 passed
- Expert Skill validation: passed
- Domain validation: passed
- Embedded report figures: 78, all `.png`
- Result CSV/TSV tables indexed for on-demand interpretation: 111
- PDF files without a same-name PNG: 0
- Full result context: 160,105 characters
- Default compact interpretation context: 32,339 characters
- Context reduction: 79.8%

The full smoke run used one immutable contract and one run directory, so this
result also tests shared workbooks, artifact naming, recursive report assembly,
and cross-function interaction. The report was rebuilt after writing a
structured project-specific interpretation.

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
- Network results are association networks and do not imply direct interaction.

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

Docker dependencies and the build recipe were updated, but a Docker image build
was not executed during this validation because the local Docker Desktop daemon
was not running.
