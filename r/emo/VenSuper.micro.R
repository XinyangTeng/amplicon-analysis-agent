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


venn_detail_num <- param_int(params, "venn_detail_num", 4)

res12 <- tryCatch(
  VenSuper.metm(
    ps    = ps.16s,
    group = "Group",
    num   = venn_detail_num
  ),
  error = function(e) {
    message("Venn detail plot failed; writing fallback result. Reason: ", conditionMessage(e))
    NULL
  }
)

if (is.null(res12)) {
  note <- amp_note_table(
    "venn_detail",
    "The detailed Venn decomposition could not be drawn for the current data and parameters.",
    "Try fewer groups, a different feature threshold, or run with a larger dataset."
  )
  p_note <- amp_note_plot("Venn detail skipped", "Current data are insufficient for the detailed Venn plot; see Excel note.")
  save_plot2(p_note, amplicon_composition_path, "12_venn_detail_note", base_width = 10, base_height = 8)
  save_preview_plot(p_note, width = 10, height = 8)
  write_sheet2(amplicon_composition_wb, "12_venn_detail_note", note)
} else {
  p12_1 <- res12[[1]]
  p12_2 <- res12[[3]]
  p12_3 <- res12[[2]]
  dat12 <- res12[[4]]
  dat120 <- dplyr::bind_rows(dat12, .id = "Part")

  save_plot2(p12_1, amplicon_composition_path, "12_venn_detail_bar",        base_width = 12, base_height = 8)
  save_plot2(p12_2, amplicon_composition_path, "12_venn_detail_alluvial",   base_width = 12, base_height = 8)
  save_plot2(p12_3, amplicon_composition_path, "12_venn_detail_proportion", base_width = 10, base_height = 8)
  write_sheet2(amplicon_composition_wb, "12_venn_detail_data", dat120)
}
openxlsx::saveWorkbook(amplicon_composition_wb, comp_xlsx_path, overwrite = TRUE)




