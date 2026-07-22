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

alpha_tests <- list()
has_replicated_groups <- nlevels(group) >= 2 && all(table(group) >= 2)
if (has_replicated_groups) {
  for (metric in c("Observed", "Shannon", "Simpson")) {
    test <- kruskal.test(alpha[[metric]] ~ group)
    alpha_tests[[metric]] <- list(statistic = unname(test$statistic), p_value = test$p.value)
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

beta_tests <- list(skipped = TRUE, reason = "At least two groups with two or more samples each are required")
if (has_replicated_groups) {
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
  permanova_has_dispersion_test = isTRUE(beta_tests$skipped) || !is.null(beta_tests$dispersion)
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

esc <- function(x) gsub("&", "&amp;", gsub("<", "&lt;", gsub(">", "&gt;", as.character(x))))
warning_html <- if (length(contract$warnings)) paste0("<li>", esc(contract$warnings), "</li>", collapse = "") else "<li>None</li>"
beta_summary <- if (isTRUE(beta_tests$skipped)) esc(beta_tests$reason) else sprintf("PERMANOVA R²=%.3f, p=%.4g; dispersion p=%.4g", beta_tests$permanova$R2, beta_tests$permanova$p_value, beta_tests$dispersion$p_value)
html <- paste0(
  "<!doctype html><html><head><meta charset='utf-8'><title>Amplicon analysis report</title>",
  "<style>body{font-family:Arial,'Microsoft YaHei',sans-serif;max-width:1000px;margin:40px auto;line-height:1.6;color:#18352a}h1,h2{color:#075f35}img{max-width:100%;border:1px solid #ddd}code{background:#eef5f0;padding:2px 5px}table{border-collapse:collapse}td,th{border:1px solid #ccc;padding:6px}</style></head><body>",
  "<h1>扩增子微生物组分析报告</h1><p><b>Plan ID:</b> <code>", esc(contract$plan_id), "</code></p>",
  "<h2>数据概况</h2><p>", nrow(sample_counts), " 个样本，", ncol(sample_counts), " 个特征；分组列：", esc(contract$group_column), "。</p>",
  "<h2>输入警告</h2><ul>", warning_html, "</ul>",
  "<h2>方法与参数</h2><p>Alpha: Observed/Shannon/Simpson；Beta: Bray-Curtis + PCoA + PERMANOVA + dispersion；组成层级：", esc(rank_name), "。</p>",
  "<h2>QC 与 Alpha 多样性</h2><img src='figures/alpha_diversity.png'><p>详细数值见 <code>tables/alpha_diversity.csv</code>。</p>",
  "<h2>Beta 多样性</h2><img src='figures/pcoa.png'><p>", beta_summary, "</p>",
  "<h2>群落组成</h2><img src='figures/composition.png'><p>显示平均丰度最高的 ", top_n, " 个分类单元，其余合并为 Other。</p>",
  "<h2>合理性检查</h2><p>状态：<b>", validation$status, "</b>。结果必须结合实验设计、样本量和离散度检验解释。</p>",
  "<h2>结论边界</h2><ul><li>可以报告描述统计、组间差异及其不确定性。</li><li>不能由本分析直接推断因果关系或机制。</li><li>显著性结果不能替代效应量和数据质量判断。</li></ul>",
  "<h2>文件索引</h2><p>机器可读清单见 <code>run_manifest.json</code>，校验结果见 <code>validation.json</code>。</p></body></html>"
)
writeLines(html, file.path(output_dir, "report.html"), useBytes = TRUE)

# Keep report rendering isolated from the analysis code so it can later be
# replaced by a Quarto/R Markdown template without changing statistics.
script_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)[1]
script_dir <- dirname(normalizePath(sub("^--file=", "", script_arg), mustWork = TRUE))
source(file.path(script_dir, "write_report.R"))
