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
beta_cluster_method <- param_chr(params, "hcluter_method", "complete")
beta_cutree_k <- param_int(params, "cuttree", 3)


res_clust <- cluster_micro(
  ps            = ps.16s,
  hcluter_method = beta_cluster_method,
  dist          = beta_distance_metric,
  cuttree       = beta_cutree_k,
  row_cluster   = TRUE,
  col_cluster   = TRUE
)

p4    <- res_clust[[1]]
p4_1  <- res_clust[[2]]
p4_2  <- res_clust[[3]]
dat_c <- res_clust[[4]]
dat_c <- as.data.frame(dat_c, check.names = FALSE)
if ("id" %in% names(dat_c)) {
  names(dat_c)[names(dat_c) == "id"] <- "Sample_ID"
}
if (nrow(dat_c) == ncol(dat_c) && !any(names(dat_c) %in% c("Sample_ID", "ID", "id"))) {
  sample_ids <- colnames(dat_c)
  if (!is.null(sample_ids) && length(sample_ids) == nrow(dat_c)) {
    dat_c <- data.frame(Sample_ID = sample_ids, dat_c, check.names = FALSE)
  }
}

save_plot2(p4,   amplicon_beta_path, "cluster_heatmap",     width = 12, height = 10)
save_plot2(p4_1, amplicon_beta_path, "cluster_dendrogram1", width = 10, height = 8)
save_plot2(p4_2, amplicon_beta_path, "cluster_dendrogram2", width = 10, height = 8)
write_sheet2(amplicon_beta_wb, "cluster_results", dat_c)
openxlsx::saveWorkbook(amplicon_beta_wb ,beta_xlsx_path, overwrite = TRUE)




