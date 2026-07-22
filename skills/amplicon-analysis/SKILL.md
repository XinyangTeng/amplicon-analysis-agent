---
name: amplicon-analysis
description: Inspect, plan, approve, run, validate, and interpret three-table amplicon microbiome analyses through the Amplicon Analysis Agent MCP server.
---

# Amplicon Analysis

Use this skill for downstream ASV/OTU analyses with an abundance table, taxonomy table, and metadata table.

## Required workflow

1. Ask for the biological question, the three file paths, and the metadata grouping column.
2. Call `inspect_amplicon_inputs` before proposing analysis.
3. Explain every blocker and warning. Do not continue while blockers exist.
4. When metadata contains multiple experiments, pass the batch column and require within-batch inference. Pass an ordered numeric gradient column for dose or stress-severity trends. Never pool batches into one inferential group test.
5. Call `prepare_amplicon_analysis` and show the user the Analysis Contract, methods, parameters, warnings, expected outputs, and plan ID.
6. Do not approve on the user's behalf. Ask the user to explicitly confirm the displayed plan.
7. Only after confirmation, call `approve_analysis` with the exact phrase `CONFIRM <plan_id>`.
8. Call `run_amplicon_analysis` with the returned one-time token.
9. Call `validate_amplicon_results` before interpreting the report.
10. Separate facts, statistical results, interpretations, and hypotheses. Never turn association into causality.
11. Interpret categorical PERMANOVA only together with the dispersion test. Treat ordered gradients as trends, not independent categories.

## Safety

- Never access files outside `AMPLICON_WORKSPACE`.
- Never fabricate an approval token, missing metadata, results, or biological meaning.
- Never silently delete samples, change groups, transpose tables, or replace parameters.
- A changed input requires a new inspection, contract, and approval.
