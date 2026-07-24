source(file.path(Sys.getenv("SCRIPT_DIR", "/project/yun/scripts"), "amp_common.R"), encoding = "UTF-8")
params <- read_amp_params()
ps.16s <- load_amp_phyloseq(params)
saveRDS(ps.16s, "ps.rds")
init_amp_legacy_globals(ps.16s, params)

library(ggpubr)
library(agricolae)
library(reshape2)
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
library(ggvenn)


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
amplicon_path <- "."

amplicon_composition_path <- file.path(amplicon_path, "03_composition")
dir.create(amplicon_composition_path, recursive = TRUE, showWarnings = FALSE)

comp_xlsx_path <- file.path(amplicon_composition_path, "composition_results.xlsx")

amplicon_composition_wb <- openxlsx::createWorkbook()

gnum       <- phyloseq::sample_data(ps.16s)$Group %>% unique() %>% length()
axis_order <- phyloseq::sample_data(ps.16s)$Group %>% unique()

col.g = get_group_cols(axis_order)
# scales::show_col(col.g) # disabled for server runtime
package.amp()
res      <- theme_my(ps.16s)
mytheme1 <- res[[1]]
mytheme2 <- res[[2]]
colset1  <- res[[3]]
colset2  <- res[[4]]
colset3  <- res[[5]]
colset4  <- res[[6]]
venn_network_n <- param_num(params, "venn_network_n", 0.5)
venn_network_fill <- param_chr(params, "comp_tax_level", "Phylum")

res14 <- ven.network.metm(
  ps   = ps.16s,
  N    = venn_network_n,
  fill = venn_network_fill
)

p14   <- res14[[1]]
dat14 <- res14[[2]]
if ("X1" %in% names(dat14)) names(dat14)[names(dat14) == "X1"] <- "layout_x"
if ("X2" %in% names(dat14)) names(dat14)[names(dat14) == "X2"] <- "layout_y"

save_plot2(p14, amplicon_composition_path, "14_venn_network", base_width = 10, base_height = 8)
write_sheet2(amplicon_composition_wb, "14_venn_network_data", dat14)
## 濞ｅ洦绻傞悺銊︾▔閳ь剙鈻?Excel
# save_comp_wb(amplicon_composition_wb, comp_xlsx_path)
openxlsx::saveWorkbook(amplicon_composition_wb, comp_xlsx_path, overwrite = TRUE)





