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


amplicon_beta_path <- file.path(amplicon_path, "02_beta_diversity")
dir.create(amplicon_beta_path, recursive = TRUE, showWarnings = FALSE)

beta_xlsx_path <- file.path(amplicon_beta_path, "beta_diversity.xlsx")

if (file.exists(beta_xlsx_path)) {
  amplicon_beta_wb <- openxlsx::loadWorkbook(beta_xlsx_path)
} else {
  amplicon_beta_wb <- openxlsx::createWorkbook()
}
beta_distance_metric <- param_chr(params, "distance_method", "bray")
beta_ordination_method <- param_chr(params, "beta_ordination_method", "PCoA")
beta_stat_method <- normalize_microtest_method(param_chr(params, "microtest_method", "PERMANOVA"), "adonis")
beta_p_cutoff <- param_num(params, "p_cutoff", 0.05)
beta_pairwise <- isTRUE(params[["beta_pairwise"]]) || identical(params[["beta_pairwise"]], "TRUE")

result_ord <- tryCatch(
  ordinate.micro(
    ps           = ps.16s,
    group        = "Group",
    dist         = beta_distance_metric,
    method       = beta_ordination_method,
    Micromet     = beta_stat_method,
    pvalue.cutoff = beta_p_cutoff,
    pair         = beta_pairwise
  ),
  error = function(e) {
    message("Ordination with pairwise statistics failed; retrying without pairwise statistics. Reason: ", conditionMessage(e))
    ordinate.micro(
      ps           = ps.16s,
      group        = "Group",
      dist         = beta_distance_metric,
      method       = beta_ordination_method,
      Micromet     = beta_stat_method,
      pvalue.cutoff = beta_p_cutoff,
      pair         = FALSE
    )
  }
)

# 闁糕晞娅ｉ、鍛村箳閹烘垹纰嶉柛?
p3_1 <- result_ord[[1]] +
  scale_fill_manual(values = col.g) +
  scale_color_manual(values = col.g, guide = "none") +
  theme_nature() +
  theme(axis.title.y = element_text(angle = 90))

# 闁圭儤甯掔花顓㈡倷閻熺増缍忛柡宥呮处閺嗙喖骞?
plotdata <- result_ord[[2]]

# 閻㈩垽闄勯悥锝囩驳閸撗勭暠闁圭儤甯掔花顓㈠炊?
p3_2 <- result_ord[[3]] +
  scale_fill_manual(values = col.g) +
  scale_color_manual(values = col.g, guide = "none") +
  theme_nature() +
  theme(axis.title.y = element_text(angle = 90))

# 缂侇喖褰為幈銊╁炊閹惧懐绐楅柛鏃傚Х閸忋垼绠涢崘銊﹀闁炽儲绮忓﹢妤呮憘濞戞艾娈犻柍?
cent <- aggregate(cbind(x, y) ~ Group, data = plotdata, FUN = mean)
segs <- merge(
  plotdata,
  setNames(cent, c("Group", "oNMDS1", "oNMDS2")),
  by = "Group",
  sort = FALSE
)

p3_3 <- result_ord[[1]] +
  geom_segment(
    data    = segs,
    mapping = aes(x = x, y = y, xend = oNMDS1, yend = oNMDS2, color = Group),
    show.legend = FALSE
  ) +
  geom_point(
    data = cent,
    mapping = aes(x = x, y = y),
    size = 5, pch = 24, color = "black", fill = "yellow"
  ) +
  scale_fill_manual(values = col.g) +
  scale_color_manual(values = col.g, guide = "none") +
  theme_nature() +
  theme(axis.title.y = element_text(angle = 90))

## ---- 濞ｅ洦绻傞悺銊╁箳閹烘垹纰嶉柛?----
save_plot2(p3_1, amplicon_beta_path, "ordination_basic",   width = 10, height = 8)
save_plot2(p3_2, amplicon_beta_path, "ordination_labeled", width = 10, height = 8)
save_plot2(p3_3, amplicon_beta_path, "ordination_refined", width = 10, height = 8)

## ---- 濞ｅ洦绻傞悺銊╁箳閹烘垹纰嶉柛褎鍔栭悥锝夊极閻楀牆绁?----
write_sheet2(amplicon_beta_wb, "ordination_data", plotdata)
openxlsx::saveWorkbook(amplicon_beta_wb ,beta_xlsx_path, overwrite = TRUE)




