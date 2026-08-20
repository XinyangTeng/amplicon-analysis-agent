# Intake and design confirmation

Ask the user to upload or locate the required abundance, taxonomy and metadata tables; optional phylogenetic tree, representative sequences and KO annotation; research question; sample type and experimental unit; exact controls and treatments; pairing or repeated measures; batches; ordered gradient and biological direction; covariates; requested full or targeted scope; and report audience/language.

After inspection, show a concise design contract and explicitly ask for correction or confirmation. Group labels alone do not identify a control. “All groups are treatments” is valid only when the user confirms the intended reference or gradient question.

Selection rules:

- Always: QC, alpha, beta and composition.
- Differential abundance: replicated contrasts with a confirmed reference. Prefer a small,
  justified method panel rather than every installed method; add MaAsLin only for confirmed
  covariates/random effects and corncob when differential variability is part of the question.
- Biomarker/ML: at least 10 samples per group; prefer held-out/nested validation and label exploratory results.
- Network: use compositional construction for at least 10 independent samples in a stratum;
  two-group comparison requires at least 10 per selected group and a confirmed contrast, with
  20+ per group preferred. Skip inference when filtering leaves fewer than four taxa. Never
  describe an association edge as a demonstrated microbial interaction.
- Assembly: phylogenetic methods require a tree; source tracking requires confirmed roles.
- Functional prediction: requires KO annotation and must be labelled predicted.
- Tax4Fun2: additionally requires representative sequences and an available reference database.
- PICRUSt2 downstream analysis: requires genuine PICRUSt2 output tables, not ASV taxonomy alone.
- Gradients: use trend models, not unrelated pairwise tests.
