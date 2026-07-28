source(file.path(Sys.getenv("SCRIPT_DIR", "/project/yun/scripts"), "amp_common.R"), encoding = "UTF-8")
params <- read_amp_params()
ps.16s <- load_amp_phyloseq(params)
saveRDS(ps.16s, "ps.rds")
init_amp_legacy_globals(ps.16s, params)

library(phyloseq)
library(tidyverse)
library(Biostrings)
load_amp_legacy_packages()
library(ggClusterNet)
library(ggsci)
library(openxlsx)
library(ape)
library(picante)
library(fs)

amplicon_path <- "."

amplicon_alpha_path <- file.path(amplicon_path, "01_alpha_diversity")
dir.create(amplicon_alpha_path, recursive = TRUE, showWarnings = FALSE)

alpha_xlsx_path <- file.path(amplicon_alpha_path, "alpha_diversity_results.xlsx")

amplicon_alpha_wb <- openxlsx::createWorkbook()


if (file.exists("ps.rds")) {
  message("Detected existing ps.rds, loading directly.")
  ps.16s <- readRDS("ps.rds")
  
} else if (file.exists("otutab.txt") & file.exists("metadata.tsv")) {
  
  message("Reading from text files...")
  
  # 閻犲洩顕цぐ?Metadata (鐎点倝缂氶鍛村礉閻樿京鐟?header=TRUE 闁?sep="\t" 濞寸姰鍎靛Σ濠氬冀閻撳海纭€閻犲洩顕цぐ鍥煥濞嗘帩鍤?
  metadata = read.delim("./metadata.tsv",row.names = 1)
  
  # 閻犲洩顕цぐ?OTU 閻?
  otutab = read.delim("./otutab.txt", row.names=1)
  
  # 闁哄瀚紓?phyloseq 閻庣數顢婇挅?
  ps <- phyloseq(
    sample_data(metadata),
    otu_table(as.matrix(otutab), taxa_are_rows=TRUE)
  )
  
  # 閻犲洩顕цぐ?Taxonomy (濠碘€冲€归悘澶愬嫉?
  if (file.exists("taxonomy.txt")) {
    taxonomy = read.table("./taxonomy.txt", row.names=1,header = T)
    tax_mat <- as.matrix(taxonomy)
    tax_table(ps) <- tax_table(tax_mat)
  }
  
  # 閻犲洩顕цぐ?閺夆晜绋戠€垫煡寮?(濠碘€冲€归悘澶愬嫉?
  if (file.exists("otus.tree")) {
    phy_tree(ps) <- read_tree("./otus.tree")
  }
  
  if (file.exists("otus.fa")) {
    message("Reading representative sequences (otus.fa)...")
    rep <- readDNAStringSet("./otus.fa")
    ps <- merge_phyloseq(ps, rep)
  }
  
  saveRDS(ps, "ps.rds")
  ps.16s <- ps
  
} else {
  stop("Input data not found. Provide ps.rds or otutab.txt plus metadata.tsv.")
}



gnum       <- phyloseq::sample_data(ps.16s)$Group %>% unique() %>% length()
axis_order <- phyloseq::sample_data(ps.16s)$Group %>% unique()

col.g = get_group_cols(axis_order)
# scales::show_col(col.g) # disabled for server runtime
# 濞戞挸顭烽。?& 濡増绮忔竟?
package.amp()
res      <- theme_my(ps.16s)
mytheme1 <- res[[1]]
mytheme2 <- res[[2]]
colset1  <- res[[3]]
colset2  <- res[[4]]
colset3  <- res[[5]]
colset4  <- res[[6]]
rare <- mean(phyloseq::sample_sums(ps.16s)) / 10
rarefaction_metric <- param_chr(params, "alpha_rarefaction_metric", "Richness")
rarefaction_start <- param_int(params, "alpha_rarefaction_start", 100)

result_rare <- tryCatch(
  alpha.rare.line.micro(
    ps     = ps.16s,
    group  = "Group",
    method = rarefaction_metric,
    start  = rarefaction_start,
    step   = rare
  ),
  error = function(e) {
    message("alpha.rare.line.micro failed; using fallback rarefaction curve. Reason: ", conditionMessage(e))
    otu <- as(phyloseq::otu_table(ps.16s), "matrix")
    if (phyloseq::taxa_are_rows(ps.16s)) otu <- t(otu)
    min_depth <- min(rowSums(otu))
    depths <- unique(round(seq(1, min_depth, length.out = 20)))
    meta <- data.frame(phyloseq::sample_data(ps.16s), check.names = FALSE)
    raretab <- do.call(rbind, lapply(seq_len(nrow(otu)), function(i) {
      data.frame(
        Sample = rownames(otu)[i],
        Group = as.character(meta[rownames(otu)[i], "Group"]),
        Depth = depths,
        Richness = as.numeric(vegan::rarefy(otu[i, ], sample = depths)),
        stringsAsFactors = FALSE
      )
    }))
    p_sample <- ggplot2::ggplot(raretab, ggplot2::aes(Depth, Richness, color = Group, group = Sample)) +
      ggplot2::geom_line(alpha = 0.65) +
      ggplot2::theme_minimal()
    group_tab <- raretab %>%
      dplyr::group_by(Group, Depth) %>%
      dplyr::summarise(Richness = mean(Richness, na.rm = TRUE), sd = stats::sd(Richness, na.rm = TRUE), .groups = "drop")
    p_group <- ggplot2::ggplot(group_tab, ggplot2::aes(Depth, Richness, color = Group)) +
      ggplot2::geom_line(linewidth = 0.8) +
      ggplot2::theme_minimal()
    p_group_sd <- ggplot2::ggplot(group_tab, ggplot2::aes(Depth, Richness, color = Group, fill = Group)) +
      ggplot2::geom_ribbon(ggplot2::aes(ymin = Richness - sd, ymax = Richness + sd), alpha = 0.18, color = NA) +
      ggplot2::geom_line(linewidth = 0.8) +
      ggplot2::theme_minimal()
    list(p_sample, raretab, p_group, p_group_sd)
  }
)

# 闁告娲橀悧閬嶅嫉椤掑倵鏋呴梺鎻掞攻濞插摜鐥?
p2_1 <- result_rare[[1]] +
  theme_nature() +
  theme(axis.title.y = element_text(angle = 90)) +
  scale_color_manual(values = col.g)

## 缂佸鍋撻梺鎻掞龚閵嗗啴寮?
raretab <- result_rare[[2]]

# 闁告帒妫涚划宥囩矙閳ь剟鏌屾繝鍐╅敜缂?
p2_2 <- result_rare[[3]] +
  theme_nature() +
  theme(axis.title.y = element_text(angle = 90)) +
  scale_color_manual(values = col.g) +
  scale_fill_manual(values = col.g)

# 闁告帒妫涚划宥囩矙閳ь剟鏌屾繝鍐╅敜缂佹儳灏呯槐娆戞暜閿旂晫鍨奸柛鎴濇濡﹪鏁?
p2_3 <- result_rare[[4]] +
  theme_nature() +
  theme(axis.title.y = element_text(angle = 90)) +
  scale_color_manual(values = col.g) +
  scale_fill_manual(values = col.g)

## ---- 濞ｅ洦绻傞悺銊х矙閳ь剟鏌屾繝鍐╅敜缂佹儳鐏濆ù?----
save_plot2(p2_1, amplicon_alpha_path, "rarefaction_individual", width = 10, height = 8)
save_plot2(p2_2, amplicon_alpha_path, "rarefaction_group",      width = 10, height = 8)
save_plot2(p2_3, amplicon_alpha_path, "rarefaction_group_sd",   width = 10, height = 8)

## ---- 濞ｅ洦绻傞悺銊х矙閳ь剟鏌屾繝鍐╅敜缂佺偓瀵ч弳鐔煎箲?----
write_sheet2(amplicon_alpha_wb, "rarefaction_data", raretab)
openxlsx::saveWorkbook(amplicon_alpha_wb, alpha_xlsx_path, overwrite = TRUE)




