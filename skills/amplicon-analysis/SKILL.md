---
name: amplicon-analysis
description: Parse microbiome projects, organize inputs, design and approve analyses, call auditable MCP tools, validate deterministic R/EMO outputs, and interpret structured amplicon reports. Use for three-table ASV/OTU projects, multi-experiment or ordered-stress designs, team EMO module selection, and post-run biological interpretation.
---

# Amplicon Analysis

Use this skill for downstream ASV/OTU analyses with an abundance table, taxonomy table, and metadata table.

## Required workflow

1. Parse the biological question, experimental unit, treatments, controls, batches, gradients, repeated measures, confounders, and intended claims.
2. Identify the three file paths, metadata grouping column, optional batch/gradient columns, optional tree and representative sequences. Never invent a missing design field.
3. Call `inspect_amplicon_inputs` before proposing analysis. Explain every blocker and warning. Do not continue while blockers exist.
4. Select methods according to the design and available evidence. When metadata contains multiple experiments, pass the batch column and require within-batch inference. Pass an ordered numeric gradient column for dose or stress-severity trends. Never pool batches into one inferential group test.
5. Call `prepare_amplicon_analysis` and show the user the Analysis Contract, methods, parameters, warnings, expected outputs, and plan ID.
6. Do not approve on the user's behalf. Ask the user to explicitly confirm the displayed plan.
7. Only after confirmation, call `approve_analysis` with the exact phrase `CONFIRM <plan_id>`.
8. Call `run_amplicon_analysis` with the returned one-time token. Let MCP orchestrate the fixed R executor and team EMO functions; do not reproduce statistical calculations in the language model.
9. Call `validate_amplicon_results`. Do not interpret failed or incomplete results.
10. Call `get_report_context` after validation passes. Use its structured facts and statistics for interpretation; use `get_analysis_report` only to give the user the finished HTML path.
11. Separate facts, statistical results, interpretations, and hypotheses. Never turn association into causality.
12. Interpret categorical PERMANOVA only together with the dispersion test. Treat ordered gradients as trends, not independent categories.

## Responsibility boundary

- Let the expert Skill parse the project, check the experimental design, select eligible modules, set decision rules, and explain validated results.
- Let MCP enforce schemas, workspace boundaries, input hashes, the immutable contract, one-time approval, execution order, status, and audit records.
- Let R and EMO functions perform numerical analysis and create primary tables and figures.
- Let the deterministic report builder recursively scan the completed run directory, group figures by batch and result section, index tables/logs, and write `report.html`, `report_data.json`, and `artifact_manifest.json`.
- Let the language model interpret only after deterministic validation. Never ask it to discover files, copy images into HTML, calculate p-values, or decide whether an execution technically succeeded.

## EMO modules

Call `list_amplicon_analysis_modules` and read [references/modules.md](references/modules.md) before selecting a team EMO module. Include only `verified` modules in a production plan. Test `registered_untested` modules on demo data first. Never select a `blocked` module.

## Safety

- Never access files outside `AMPLICON_WORKSPACE`.
- Never fabricate an approval token, missing metadata, results, or biological meaning.
- Never silently delete samples, change groups, transpose tables, or replace parameters.
- A changed input requires a new inspection, contract, and approval.
