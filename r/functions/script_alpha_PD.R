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


## ===================== 2. Alpha 濠㈣埖纰嶉悧閬嶅箑瑜嶉崹搴ㄥ几?=====================

# 2.1 闁告帗绋戠紓?Alpha 濠㈣埖纰嶉悧閬嶅箑瑜忓ú鎷屻亹?& 鐎规悶鍎扮紞鏃傝姳閸栵紕绀勫ù鐘烘硶閸?composition/diff 闁汇劌瀚崯鎾斥枖閺囶亞绀?
amplicon_alpha_path <- file.path(amplicon_path, "01_alpha_diversity")
dir.create(amplicon_alpha_path, recursive = TRUE, showWarnings = FALSE)

alpha_xlsx_path <- file.path(amplicon_alpha_path, "alpha_diversity_results.xlsx")

amplicon_alpha_wb <- open_amp_workbook(alpha_xlsx_path)

requested_alpha <- param_vec(params, "alpha_metrics", c("Shannon", "Chao1", "Simpson", "Richness", "ACE", "Pielou"))
alpha_name_map <- c(Simpson = "Inv_Simpson", Pielou = "Pielou_evenness", Evenness = "Pielou_evenness")
requested_alpha <- unname(ifelse(requested_alpha %in% names(alpha_name_map), alpha_name_map[requested_alpha], requested_alpha))
alpha_sig_label <- param_chr(params, "alpha_sig_label", "abc")
alpha_ncol <- param_int(params, "ncol", 4)

# 閻犱緤绱曢悾?alpha 闁圭娲﹂悥?
tab <- alpha.micro(ps = ps.16s, group = "Group")
head(tab)
all.alpha <- intersect(requested_alpha, colnames(tab))
if (length(all.alpha) == 0) {
  stop("No selected alpha metrics were found in alpha.micro result.")
}

sample_id <- rownames(tab)
if (is.null(sample_id) || length(sample_id) != nrow(tab) || identical(sample_id, as.character(seq_len(nrow(tab))))) {
  sample_id <- phyloseq::sample_names(ps.16s)
}

data <- cbind(
  data.frame(ID = sample_id, group = tab$Group),
  tab[all.alpha]
)
data$ID <- as.character(data$ID)
head(data)
alpha_num <- seq.int(3, ncol(data))

# Kruskal-Wallis omnibus tests plus BH-adjusted pairwise Wilcoxon tests.
result <- amp_alpha_tests(data, all.alpha, group_col = "group")
plot_data <- tidyr::pivot_longer(
  data, cols = dplyr::all_of(all.alpha), names_to = "name", values_to = "dd"
) %>% dplyr::filter(is.finite(dd))
plot_data$group <- factor(plot_data$group, levels = axis_order)
test_labels <- amp_alpha_test_labels(result, facet_col = "name")
p1_1 <- ggplot2::ggplot(plot_data, ggplot2::aes(x = group, y = dd, fill = group, color = group)) +
  ggplot2::geom_boxplot(alpha = 0.65, outlier.shape = NA) +
  ggplot2::geom_jitter(width = 0.15, size = 2, alpha = 0.7) +
  ggplot2::geom_text(
    data = test_labels, ggplot2::aes(x = 1, y = Inf, label = label),
    inherit.aes = FALSE, hjust = 0, vjust = 1.2, size = 3
  ) +
  ggplot2::facet_wrap(. ~ name, scales = "free_y", ncol = alpha_ncol) +
  ggplot2::scale_x_discrete(limits = axis_order) +
  theme_nature() +
  ggplot2::guides(fill = guide_legend(title = NULL)) +
  ggplot2::scale_color_manual(values = col.g) +
  ggplot2::scale_fill_manual(values = col.g)

save_plot2(p1_1, amplicon_alpha_path, "alpha_pd_alpha_boxplot", width = 10, height = 8)
save_preview_plot(p1_1, width = 10, height = 8)
write_sheet2(amplicon_alpha_wb, "alpha_pd_alpha_data", data)
write_sheet2(amplicon_alpha_wb, "alpha_pd_alpha_stat", result)

## ---- PD 濠㈣埖纰嶉悧閬嶅箑瑜嶉崹搴ㄥ几閹板墎绀勫ù鐘叉噹濠€顏嗏偓娑櫭﹢顏呮交濞戞ê顕ч柡宥嗗灦濡炲倹娼婚幇顖ｆ斀闁?----
alpha.pd.micro = function (ps = ps.16s, group = "Group") 
{
  com_2020 <- ps %>% vegan_otu() %>% as.data.frame()
  rooted <- phy_tree(ps)
  cover2020.pd <- pd(com_2020, rooted, include.root = F)
  map <- data.frame(sample_data(ps))
  if (!"ID" %in% colnames(map)) {
    map$ID <- rownames(map)
  }
  head(map)
  data = cbind(map[, c("ID", "Group")], pd = cover2020.pd[, 
                                                          1])
  head(data)
  colnames(data)[2] = "group"
  data$group = as.factor(data$group)
  return(data)
}


if (!is.null(phyloseq::phy_tree(ps.16s, errorIfNULL = FALSE))) {
  tab2    <- alpha.pd.micro(ps.16s)
  head(tab2)
  
  result_pd <- amp_alpha_tests(tab2, "pd", group_col = "group")
  pd_labels <- amp_alpha_test_labels(result_pd, facet_col = "metric")
  p_pd <- ggplot2::ggplot(tab2, ggplot2::aes(x = group, y = pd, fill = group, color = group)) +
    ggplot2::geom_boxplot(alpha = 0.65, outlier.shape = NA) +
    ggplot2::geom_jitter(width = 0.15, size = 2, alpha = 0.7) +
    ggplot2::annotate(
      "text", x = 1, y = Inf,
      label = if (nrow(pd_labels)) pd_labels$label[[1]] else "Kruskal-Wallis not applicable",
      hjust = 0, vjust = 1.2, size = 3
    ) +
    theme_nature() +
    ggplot2::guides(fill = guide_legend(title = NULL)) +
    ggplot2::scale_fill_manual(values = colset1) +
    ggplot2::scale_color_manual(values = colset1)
  
  ## ---- 濞ｅ洦绻傞悺?PD 闁?----
  save_plot2(p_pd, amplicon_alpha_path, "pd_diversity", width = 8, height = 6)
  
  ## ---- 濞ｅ洦绻傞悺?PD 閻?----
  write_sheet2(amplicon_alpha_wb, "pd_diversity_data", tab2)
  write_sheet2(amplicon_alpha_wb, "pd_diversity_stat", result_pd)
  openxlsx::saveWorkbook(amplicon_alpha_wb, alpha_xlsx_path, overwrite = TRUE)
  
} else {
  message("No phylogenetic tree detected; skipped PD diversity analysis.")
}

