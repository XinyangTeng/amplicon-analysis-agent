---
name: amplicon-analysis
description: Plan, approve, run, validate, and interpret auditable ASV/OTU microbiome projects. Use for three-table amplicon analysis, experimental-design confirmation, function selection, and project-specific result interpretation.
---

# Amplicon Analysis

## Mandatory Plan mode

The first response must be an intake question, even when files are already attached. Confirm what is present and ask for every missing item in [references/planning.md](references/planning.md). Do not call an execution tool in the first response.

After the user answers:

1. Call `inspect_amplicon_inputs`; never infer table orientation, columns, groups, or sample counts from filenames.
2. Show the detected files, sample/feature counts, group sizes, batch/gradient fields, warnings, and blockers.
3. Propose an explicit experimental design: research question, sample type, experimental unit, controls, treatments, contrasts, pairing/repeated measures, batches, gradients and gradient direction, covariates, and intended claims.
4. Ask the user to confirm or correct that design. Do not prepare a plan before this confirmation.
5. Decide between `targeted` and `full` analysis. Full means every scientifically eligible category, not blindly every function. Explain every omitted or conditional category.
6. Query the compact function catalog by category. Inspect full details only for selected functions.
7. Call `prepare_amplicon_analysis` with the confirmed `project_design` and `analysis_scope`. Show the immutable contract, parameters, warnings, expected outputs, and plan ID.
8. Never approve for the user. Continue only after the exact phrase `CONFIRM <plan_id>`.
9. Approve, run, then validate. Never interpret failed or incomplete output.
10. Call compact `get_report_context`. Interpret the results using the confirmed design and [references/interpretation.md](references/interpretation.md), then call `save_analysis_interpretation`.
11. Return the rebuilt HTML report path.

## Responsibility boundary

- Skill: intake, design reasoning, method selection, and biological interpretation.
- MCP: schemas, safe paths, hashes, contract, approval, execution state, and audit trail.
- R: numerical calculations, tables, and PNG figures.
- Fixed report builder: scans outputs, embeds PNG only, indexes all files, and merges validated `interpretation.json`.
- LLM: writes interpretation only after validation; it never calculates p-values or decides technical success.

## Scientific rules

- Never pool experimental batches for inferential tests.
- Interpret PERMANOVA only with dispersion.
- Treat ordered gradients as trends and record their direction.
- Machine learning is exploratory unless held-out or nested validation is available.
- Predicted KO function is not measured metagenomic function.
- Association, ordination separation, and significance do not prove causality.

## Token discipline

- List functions by category; do not request the full detailed 55-function catalog.
- Inspect only shortlisted functions.
- Use compact report context; open individual tables only when a claim needs verification.
- Refer to the confirmed design contract instead of repeating the conversation.
- Keep interpretation evidence-linked and omit decorative restatement.

## Safety

- Never access files outside `AMPLICON_WORKSPACE`.
- Never invent design fields, approvals, tokens, missing metadata, results, or biological meaning.
- Never silently transpose, delete samples, change groups, or alter parameters.
- Any changed input or parameter requires a new inspection, contract, and approval.
