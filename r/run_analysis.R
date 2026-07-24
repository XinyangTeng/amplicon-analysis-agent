#!/usr/bin/env Rscript

# Refactored for the Amplicon Analysis Agent prototype.
# Source inspiration: EasyMultiOmics/pipeline/1.pipeline.amp.pro.R
# Original authors listed by EasyMultiOmics: WenTao, XiePenghao.
# Changes: removed interactive state and hard-coded paths; reduced the workflow to
# deterministic QC, alpha, beta, and composition modules with explicit artifacts.

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2) stop("Usage: run_analysis.R CONTRACT_JSON OUTPUT_DIR")
contract_path <- normalizePath(args[[1]], mustWork = TRUE)
output_dir <- normalizePath(args[[2]], mustWork = TRUE)

suppressPackageStartupMessages({
  library(jsonlite)
  library(vegan)
  library(ggplot2)
})

contract <- fromJSON(contract_path, simplifyVector = TRUE)
dir.create(file.path(output_dir, "tables"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(output_dir, "figures"), recursive = TRUE, showWarnings = FALSE)

read_table <- function(path) {
  header <- readLines(path, n = 1, warn = FALSE, encoding = "UTF-8")
  separator <- if (grepl("\t", header, fixed = TRUE)) "\t" else ","
  read.table(
    path, header = TRUE, sep = separator, check.names = FALSE,
    stringsAsFactors = FALSE, quote = "\"", comment.char = "",
    fileEncoding = "UTF-8-BOM"
  )
}
abundance_raw <- read_table(contract$files$abundance)
taxonomy <- read_table(contract$files$taxonomy)
metadata <- read_table(contract$files$metadata)

rownames(metadata) <- trimws(as.character(metadata[[1]]))
rownames(taxonomy) <- trimws(as.character(taxonomy[[1]]))
if (isTRUE(contract$transpose_abundance)) {
  rownames(abundance_raw) <- trimws(as.character(abundance_raw[[1]]))
  counts <- t(as.matrix(abundance_raw[, -1, drop = FALSE]))
} else {
  rownames(abundance_raw) <- trimws(as.character(abundance_raw[[1]]))
  counts <- as.matrix(abundance_raw[, -1, drop = FALSE])
}
storage.mode(counts) <- "numeric"
counts <- counts[, rownames(metadata), drop = FALSE]
taxonomy <- taxonomy[rownames(counts), , drop = FALSE]
group <- factor(metadata[[contract$group_column]])
names(group) <- rownames(metadata)
seed <- as.integer(contract$parameters$seed)
set.seed(seed)

sample_counts <- t(counts)
depth <- rowSums(sample_counts)
qc <- data.frame(
  sample_id = rownames(sample_counts), group = as.character(group),
  sequencing_depth = depth, observed_features = rowSums(sample_counts > 0),
  zero_fraction = rowMeans(sample_counts == 0), check.names = FALSE
)
write.csv(qc, file.path(output_dir, "tables", "qc_summary.csv"), row.names = FALSE)

alpha <- data.frame(
  sample_id = rownames(sample_counts), group = as.character(group),
  Observed = rowSums(sample_counts > 0),
  Shannon = diversity(sample_counts, index = "shannon"),
  Simpson = diversity(sample_counts, index = "simpson"), check.names = FALSE
)
write.csv(alpha, file.path(output_dir, "tables", "alpha_diversity.csv"), row.names = FALSE)
alpha_long <- reshape(alpha, varying = c("Observed", "Shannon", "Simpson"),
                      v.names = "value", timevar = "metric",
                      times = c("Observed", "Shannon", "Simpson"), direction = "long")
p_alpha <- ggplot(alpha_long, aes(group, value, fill = group)) +
  geom_boxplot(outlier.shape = NA, alpha = 0.65) + geom_jitter(width = 0.12, size = 2) +
  facet_wrap(~metric, scales = "free_y") + theme_bw() +
  theme(legend.position = "none") + labs(x = contract$group_column, y = NULL)
ggsave(file.path(output_dir, "figures", "alpha_diversity.png"), p_alpha, width = 10, height = 4.5, dpi = 160)

alpha_tests <- list(skipped = TRUE, reason = "Overall test disabled when a batch column is supplied")
has_replicated_groups <- nlevels(group) >= 2 && all(table(group) >= 2)
if (has_replicated_groups && is.null(contract$batch_column)) {
  alpha_tests <- list(skipped = FALSE, tests = list())
  for (metric in c("Observed", "Shannon", "Simpson")) {
    test <- kruskal.test(alpha[[metric]] ~ group)
    alpha_tests$tests[[metric]] <- list(statistic = unname(test$statistic), p_value = test$p.value)
  }
}
write_json(alpha_tests, file.path(output_dir, "tables", "alpha_tests.json"), pretty = TRUE, auto_unbox = TRUE)

dist_bray <- vegdist(sample_counts, method = "bray")
pcoa_fit <- cmdscale(dist_bray, k = 2, eig = TRUE, add = TRUE)
pcoa <- data.frame(sample_id = rownames(pcoa_fit$points), group = as.character(group),
                   PCoA1 = pcoa_fit$points[, 1], PCoA2 = pcoa_fit$points[, 2])
write.csv(pcoa, file.path(output_dir, "tables", "pcoa_coordinates.csv"), row.names = FALSE)
p_pcoa <- ggplot(pcoa, aes(PCoA1, PCoA2, color = group)) + geom_point(size = 3) + theme_bw() +
  labs(color = contract$group_column)
ggsave(file.path(output_dir, "figures", "pcoa.png"), p_pcoa, width = 7, height = 5.5, dpi = 160)

beta_tests <- list(skipped = TRUE, reason = "Overall test disabled when a batch column is supplied")
if (has_replicated_groups && is.null(contract$batch_column)) {
  metadata_beta <- data.frame(group = group)
  permutations <- as.integer(contract$parameters$permutations)
  permanova <- adonis2(dist_bray ~ group, data = metadata_beta, permutations = permutations)
  dispersion <- betadisper(dist_bray, group)
  dispersion_test <- anova(dispersion)
  beta_tests <- list(
    skipped = FALSE,
    permanova = list(F = permanova$F[1], R2 = permanova$R2[1], p_value = permanova$`Pr(>F)`[1]),
    dispersion = list(F = dispersion_test$`F value`[1], p_value = dispersion_test$`Pr(>F)`[1])
  )
}
write_json(beta_tests, file.path(output_dir, "tables", "beta_tests.json"), pretty = TRUE, auto_unbox = TRUE, na = "null")

# Stratified inference prevents experiment-batch effects from being interpreted
# as biological treatment effects. Numeric gradients are tested as trends.
stratified_tests <- list(skipped = TRUE, reason = "No batch column supplied")
if (!is.null(contract$batch_column)) {
  batch_values <- as.character(metadata[[contract$batch_column]])
  stratified_tests <- list(skipped = FALSE, batch_column = contract$batch_column, batches = list())
  for (batch_name in unique(batch_values)) {
    keep <- which(batch_values == batch_name)
    batch_samples <- rownames(metadata)[keep]
    batch_group <- droplevels(group[batch_samples])
    batch_counts <- sample_counts[batch_samples, , drop = FALSE]
    batch_alpha <- alpha[match(batch_samples, alpha$sample_id), , drop = FALSE]
    batch_result <- list(sample_count = length(keep), groups = as.list(table(batch_group)))

    gradient_used <- FALSE
    if (!is.null(contract$gradient_column)) {
      gradient <- suppressWarnings(as.numeric(metadata[batch_samples, contract$gradient_column]))
      if (all(is.finite(gradient)) && length(unique(gradient)) >= 3) {
        gradient_used <- TRUE
        alpha_trend <- list()
        for (metric in c("Observed", "Shannon", "Simpson")) {
          trend <- cor.test(batch_alpha[[metric]], gradient, method = "spearman", exact = FALSE)
          alpha_trend[[metric]] <- list(rho = unname(trend$estimate), p_value = trend$p.value)
        }
        batch_dist <- vegdist(batch_counts, method = "bray")
        gradient_data <- data.frame(gradient = gradient)
        gradient_permanova <- adonis2(batch_dist ~ gradient, data = gradient_data,
                                      permutations = as.integer(contract$parameters$permutations))
        batch_result$analysis_type <- "ordered_gradient"
        batch_result$gradient_levels <- sort(unique(gradient))
        batch_result$alpha_trend <- alpha_trend
        batch_result$beta_trend <- list(F = gradient_permanova$F[1], R2 = gradient_permanova$R2[1],
                                        p_value = gradient_permanova$`Pr(>F)`[1])
      }
    }

    if (!gradient_used && nlevels(batch_group) >= 2 && all(table(batch_group) >= 2)) {
      alpha_group <- list()
      for (metric in c("Observed", "Shannon", "Simpson")) {
        test <- kruskal.test(batch_alpha[[metric]] ~ batch_group)
        alpha_group[[metric]] <- list(statistic = unname(test$statistic), p_value = test$p.value)
      }
      batch_dist <- vegdist(batch_counts, method = "bray")
      group_data <- data.frame(batch_group = batch_group)
      perm <- adonis2(batch_dist ~ batch_group, data = group_data,
                      permutations = as.integer(contract$parameters$permutations))
      disp <- anova(betadisper(batch_dist, batch_group))
      batch_result$analysis_type <- "categorical_within_batch"
      batch_result$alpha_group <- alpha_group
      batch_result$permanova <- list(F = perm$F[1], R2 = perm$R2[1], p_value = perm$`Pr(>F)`[1])
      batch_result$dispersion <- list(F = disp$`F value`[1], p_value = disp$`Pr(>F)`[1])
    } else if (!gradient_used) {
      batch_result$analysis_type <- "descriptive_only"
      batch_result$reason <- "At least two replicated groups are required"
    }
    stratified_tests$batches[[batch_name]] <- batch_result
  }
}
write_json(stratified_tests, file.path(output_dir, "tables", "stratified_tests.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")

rank_name <- as.character(contract$parameters$taxonomy_rank)
taxa <- as.character(taxonomy[[rank_name]])
taxa[is.na(taxa) | trimws(taxa) == ""] <- "Unassigned"
agg <- rowsum(counts, group = taxa, reorder = FALSE)
relative <- sweep(agg, 2, colSums(agg), "/")
relative[!is.finite(relative)] <- 0
top_n <- as.integer(contract$parameters$top_n)
top_taxa <- names(sort(rowMeans(relative), decreasing = TRUE))[seq_len(min(top_n, nrow(relative)))]
composition <- relative[top_taxa, , drop = FALSE]
if (nrow(relative) > length(top_taxa)) composition <- rbind(composition, Other = colSums(relative[setdiff(rownames(relative), top_taxa), , drop = FALSE]))
comp_df <- data.frame(taxon = rownames(composition), composition, check.names = FALSE)
write.csv(comp_df, file.path(output_dir, "tables", "composition_relative_abundance.csv"), row.names = FALSE)
comp_long <- data.frame(
  taxon = rep(rownames(composition), times = ncol(composition)),
  sample_id = rep(colnames(composition), each = nrow(composition)),
  abundance = as.vector(composition)
)
comp_long$group <- metadata[comp_long$sample_id, contract$group_column]
p_comp <- ggplot(comp_long, aes(sample_id, abundance, fill = taxon)) + geom_col() +
  facet_grid(~group, scales = "free_x", space = "free_x") + theme_bw() +
  theme(axis.text.x = element_text(angle = 45, hjust = 1)) + labs(x = NULL, y = "Relative abundance", fill = rank_name)
ggsave(file.path(output_dir, "figures", "composition.png"), p_comp, width = 10, height = 6, dpi = 160)

checks <- list(
  positive_depth = all(depth > 0),
  finite_alpha = all(is.finite(as.matrix(alpha[, c("Observed", "Shannon", "Simpson")]))),
  finite_pcoa = all(is.finite(as.matrix(pcoa[, c("PCoA1", "PCoA2")]))),
  composition_sums_to_one = all(abs(colSums(relative) - 1) < 1e-8),
  permanova_has_dispersion_test = isTRUE(beta_tests$skipped) || !is.null(beta_tests$dispersion),
  stratified_tests_present = is.null(contract$batch_column) || !isTRUE(stratified_tests$skipped)
)
validation <- list(status = if (all(unlist(checks))) "pass" else "fail", checks = checks,
                   cautions = c("PERMANOVA must be interpreted together with dispersion testing.",
                                "Associations and group differences do not establish causality."))
write_json(validation, file.path(output_dir, "validation.json"), pretty = TRUE, auto_unbox = TRUE)

manifest <- list(
  plan_id = contract$plan_id, completed_at = format(Sys.time(), tz = "UTC", usetz = TRUE),
  R_version = R.version.string,
  packages = list(vegan = as.character(packageVersion("vegan")), ggplot2 = as.character(packageVersion("ggplot2")), jsonlite = as.character(packageVersion("jsonlite"))),
  parameters = contract$parameters,
  files = list.files(output_dir, recursive = TRUE)
)
write_json(manifest, file.path(output_dir, "run_manifest.json"), pretty = TRUE, auto_unbox = TRUE)
