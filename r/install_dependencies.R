options(repos = c(CRAN = "https://cloud.r-project.org"))
cran <- c(
  "jsonlite", "ggplot2", "vegan", "tidyverse", "ggsci", "openxlsx", "ape",
  "picante", "minpack.lm", "Hmisc", "fs", "randomForest", "caret", "e1071",
  "glmnet", "rpart", "ipred", "ROCR", "ggpubr", "ggrepel", "patchwork",
  "reshape2", "igraph", "ggraph", "pulsar"
)
missing_cran <- cran[!vapply(cran, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing_cran)) install.packages(missing_cran, Ncpus = max(1, parallel::detectCores() - 1))
if (!requireNamespace("BiocManager", quietly = TRUE)) install.packages("BiocManager")
bioc <- c("phyloseq", "Biostrings", "DESeq2")
missing_bioc <- bioc[!vapply(bioc, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing_bioc)) BiocManager::install(missing_bioc, ask = FALSE, update = FALSE)
