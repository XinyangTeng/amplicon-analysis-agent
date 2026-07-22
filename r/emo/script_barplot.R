source(file.path(Sys.getenv("SCRIPT_DIR", "/project/yun/scripts"), "amp_common.R"), encoding = "UTF-8")
params <- read_amp_params()
ps.16s <- load_amp_phyloseq(params)
saveRDS(ps.16s, "ps.rds")
init_amp_legacy_globals(ps.16s, params)

library(ggalluvial)
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
# library(mia) # disabled: can mask phyloseq/EasyMultiOmics methods in server runtime


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

message("Composition output directory: ", amplicon_composition_path)



pst <- ps.16s %>% subset_taxa.wt("Species", "Unassigned", TRUE)
pst <- pst %>% subset_taxa.wt("Genus",   "Unassigned", TRUE)
comp_tax_level <- param_chr(params, "comp_tax_level", "Genus")
comp_top_n <- param_int(params, "comp_top_n", 10)

res16 <- barMainplot.micro(
  ps   = pst,
  j    = comp_tax_level,
  label = FALSE,
  sd    = FALSE,
  Top   = comp_top_n
)

p16_1 <- res16[[1]] +
  scale_fill_manual(values = colset2) +
  scale_x_discrete(limits = axis_order) +
  theme_nature() +
  theme(axis.title.y = element_text(angle = 90))

p16_2 <- res16[[3]] +
  scale_fill_manual(values = colset2) +
  scale_x_discrete(limits = axis_order) +
  theme_nature() +
  theme(axis.title.y = element_text(angle = 90))

dat16 <- res16[[2]] %>%
  dplyr::group_by(Group, aa) %>%
  dplyr::summarise(Abundance = sum(Abundance), .groups = "drop") %>%
  as.data.frame()
colnames(dat16) <- c("Group", "Genus", "Abundance(%)")

save_plot2(p16_1, amplicon_composition_path, "16_barplot_main",      base_width = 12, base_height = 8)
save_plot2(p16_2, amplicon_composition_path, "16_barplot_secondary", base_width = 12, base_height = 8)
write_sheet2(amplicon_composition_wb, "16_barplot_data", dat16)
## 濞ｅ洦绻傞悺銊︾▔閳ь剙鈻?Excel
# save_comp_wb(amplicon_composition_wb, comp_xlsx_path)
openxlsx::saveWorkbook(amplicon_composition_wb, comp_xlsx_path, overwrite = TRUE)



