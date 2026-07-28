# Intake and design confirmation

Ask the user to upload or locate the required abundance, taxonomy and metadata tables; optional phylogenetic tree, representative sequences and KO annotation; research question; sample type and experimental unit; exact controls and treatments; pairing or repeated measures; batches; ordered gradient and biological direction; covariates; requested full or targeted scope; and report audience/language.

After inspection, show a concise design contract and explicitly ask for correction or confirmation. Group labels alone do not identify a control. “All groups are treatments” is valid only when the user confirms the intended reference or gradient question.

Selection rules:

- Always: QC, alpha, beta and composition.
- Differential abundance: replicated contrasts with a confirmed reference.
- Biomarker/ML: at least 10 samples per group; prefer held-out/nested validation and label exploratory results.
- Network: at least 10 samples per stratum; group comparison needs adequate samples per group.
- Assembly: phylogenetic methods require a tree; source tracking requires confirmed roles.
- Functional prediction: requires KO annotation and must be labelled predicted.
- Gradients: use trend models, not unrelated pairwise tests.
