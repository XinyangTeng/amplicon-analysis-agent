# R package method map

This map separates user-facing analyses from shared preprocessing backends and methods that
need external reference data. Package versions are also written into each run's method table.
The 2026-08-15 Docker build loaded all 59 packages declared by
`r/check_dependencies.R`; the entries below highlight the analysis-specific backends rather
than repeating every plotting, data-structure, and runtime dependency.

| Installed package | Project entry point | Role | Status / prerequisite |
|---|---|---|---|
| ANCOMBC | `script-ancombc2` | Bias-corrected differential abundance | Verified; confirmed contrast |
| ALDEx2 | `script-aldex2` | Monte Carlo CLR differential abundance | Verified; confirmed contrast |
| Maaslin2 | `script-maaslin2` | Multivariable association | Verified; model must follow design |
| maaslin3 | `script-maaslin3` | Abundance/prevalence multivariable association | Verified; model must follow design |
| MicrobiomeStat | `script-linda` | LinDA differential abundance | Verified; confirmed contrast |
| corncob | `script-corncob` | Beta-binomial abundance/variability test | Verified; confirmed contrast |
| metagenomeSeq | `script-metagenomeseq` | CSS + zero-inflated Gaussian test | Verified; confirmed contrast |
| lefser | `script-lefse` | LEfSe candidate markers | Verified; exploratory |
| breakaway | `script-breakaway` | Unseen-richness estimation | Verified; inspect confidence intervals |
| GUniFrac | `script-gunifrac` | Generalized UniFrac + PERMANOVA/PERMDISP | Conditional; matching tree |
| mixOmics | `script-splsda` | Repeated-CV sPLS-DA | Conditional; >=10 samples/group |
| SIAMCAT | `script-siamcat` | Repeated-CV microbiome classifier | Conditional; >=10 samples/group |
| SpiecEasi | `script-spieceasi` | Sparse conditional-dependence network | Conditional; >=10 samples/group |
| WGCNA | `script-wgcna` | Taxon modules and module-trait association | Conditional; >=10 samples/group |
| zCompositions + compositions + robCompositions | `script-coda-pca` | Zero replacement, CLR and CoDA PCA | Verified |
| microbiomeMarker | Shared alternative backend | DA/marker toolkit | Installed; not duplicated as multiple buttons |
| MicrobiotaProcess | Shared alternative backend | Data structures, ordination and marker utilities | Installed; overlaps existing methods |
| microeco | Shared alternative backend | Ecology workflow utilities | Installed; overlaps existing methods |
| ggpicrust2 | Planned conditional downstream adapter | PICRUSt2-output analysis | Needs genuine PICRUSt2 output tables |
| Tax4Fun2 | Planned conditional prediction adapter | 16S functional prediction | Needs representative sequences and reference data |
| FEAST 1.18.0 | Not used for source tracking | Single-cell feature selection | Different package despite identical name |

The project calls documented package interfaces; it does not copy package source code into the
repository. Do not select every available differential method by default. The expert Skill should
choose a small complementary set based on design, assumptions and the intended claim.
