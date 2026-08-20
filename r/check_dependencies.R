args <- commandArgs(trailingOnly = TRUE)
out <- if (length(args)) args[[1]] else "dependency_status.csv"
packages <- c(
  "jsonlite", "ggplot2", "vegan", "phyloseq", "tidyverse", "Biostrings",
  "agricolae", "ggClusterNet", "ggvenn", "microbiome", "mia",
  "ggsci", "openxlsx", "ape", "picante", "minpack.lm", "Hmisc", "fs",
  "randomForest", "caret", "e1071", "glmnet", "rpart", "ipred", "ROCR",
  "DESeq2", "ggpubr", "ggrepel", "patchwork", "reshape2", "igraph",
  "ggraph", "pulsar", "MASS", "nnet", "edgeR", "ggalluvial",
  "ANCOMBC", "ALDEx2", "Maaslin2", "maaslin3", "corncob",
  "MicrobiomeStat", "metagenomeSeq", "microbiomeMarker", "breakaway",
  "GUniFrac", "mixOmics", "SIAMCAT", "SpiecEasi", "WGCNA",
  "zCompositions", "compositions", "robCompositions", "MicrobiotaProcess",
  "microeco", "ggpicrust2", "Tax4Fun2", "lefser"
)
status <- data.frame(
  package = packages,
  installed = vapply(packages, requireNamespace, logical(1), quietly = TRUE),
  version = vapply(packages, function(x) {
    if (!requireNamespace(x, quietly = TRUE)) return(NA_character_)
    as.character(utils::packageVersion(x))
  }, character(1)),
  stringsAsFactors = FALSE
)
utils::write.csv(status, out, row.names = FALSE)
print(status, row.names = FALSE)
if (any(!status$installed)) quit(status = 2)
