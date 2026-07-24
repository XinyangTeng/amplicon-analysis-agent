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

inputMicro = function (otu = NULL, tax = NULL, map = NULL, tree = NULL, ps = NULL, 
                       group = "Group") 
{
  if (is.null(otu) & is.null(tax) & is.null(map)) {
    ps = ps
    map = as.data.frame(phyloseq::sample_data(ps))
    map = map[, "Group"]
    colnames(map) = "Group"
    map$Group = as.factor(map$Group)
    phyloseq::sample_data(ps) = map
    map = NULL
  }
  if (is.null(ps)) {
    if (!is.null(otu)) {
      otu = as.matrix(otu)
      ps <- phyloseq::phyloseq(phyloseq::otu_table(otu, 
                                                   taxa_are_rows = TRUE))
    }
    if (!is.null(tax)) {
      tax = as.matrix(tax)
      x = phyloseq::tax_table(tax)
      ps = phyloseq::merge_phyloseq(ps, x)
      ps
    }
    if (!is.null(map)) {
      map = map[group]
      map[, group] = as.factor(map[, group])
      map$Group
      z = phyloseq::sample_data(map)
      ps = phyloseq::merge_phyloseq(ps, z)
      ps
    }
    if (!is.null(tree)) {
      h = phyloseq::phy_tree(tree)
      ps = phyloseq::merge_phyloseq(ps, h)
      ps
    }
  }
  return(ps)
}

ggflower.micro = function (otu = NULL, tax = NULL, map = NULL, ps = NULL, group = "Group", 
                           rep = 6, m1 = 2, start = 1, a = 0.2, b = 1, lab.leaf = 1, 
                           col.cir = "yellow", a.cir = 0.5, b.cir = 0.5, m1.cir = 2, 
                           N = 0.5) 
{
  ps = inputMicro(otu, tax, map, tree, ps, group = group)
  mapping = as.data.frame(phyloseq::sample_data(ps))
  aa = ggClusterNet::vegan_otu(ps)
  otu_table = as.data.frame(t(aa))
  count = aa
  sub_design <- as.data.frame(phyloseq::sample_data(ps))
  sub_design$SampleType = sub_design$Group
  phyloseq::sample_data(ps) = sub_design
  count[count > 0] <- 1
  count2 = as.data.frame(count)
  iris.split <- split(count2, as.factor(sub_design$Group))
  iris.apply <- lapply(iris.split, function(x) colSums(x[]))
  iris.combine <- do.call(rbind, iris.apply)
  ven2 = t(iris.combine)
  for (i in 1:length(unique(phyloseq::sample_data(ps)$Group))) {
    aa <- as.data.frame(table(phyloseq::sample_data(ps)$Group))[i, 
                                                                1]
    bb = as.data.frame(table(phyloseq::sample_data(ps)$Group))[i, 
                                                               2]
    ven2[, aa] = ven2[, aa]/bb
  }
  ven2[ven2 < N] = 0
  ven2[ven2 >= N] = 1
  ven2 = as.data.frame(ven2)
  ven3 = as.list(ven2)
  ven2 = as.data.frame(ven2)
  all_num = dim(ven2[rowSums(ven2) == length(levels(sub_design$Group)), 
  ])[1]
  ven2[, 1] == 1
  A = rep("A", length(colnames(ven2)))
  B = rep(1, length(colnames(ven2)))
  i = 1
  for (i in 1:length(colnames(ven2))) {
    B[i] = length(ven2[rowSums(ven2) == 1, ][, i][ven2[rowSums(ven2) == 
                                                         1, ][, i] == 1])
    A[i] = colnames(ven2)[i]
  }
  n <- length(A)
  deg <- 360/n
  t = 1:n
  print(deg)
  p <- ggplot() + ggforce::geom_ellipse(aes(x0 = 5 + cos((start + 
                                                            deg * (t - 1)) * pi/180), y0 = 5 + sin((start + deg * 
                                                                                                      (t - 1)) * pi/180), a = a, b = b, angle = (n/2 + seq(0, 
                                                                                                                                                           1000, 2)[1:n])/n * pi, m1 = m1, fill = as.factor(1:n)), 
                                        show.legend = F) + ggforce::geom_ellipse(aes(x0 = 5, 
                                                                                     y0 = 5, a = a.cir, b = b.cir, angle = 0, m1 = m1.cir), 
                                                                                 fill = col.cir) + geom_text(aes(x = 5, y = 5, label = paste("OVER :", 
                                                                                                                                             all_num, sep = ""))) + geom_text(aes(x = 5 + cos((start + 
                                                                                                                                                                                                 deg * (t - 1)) * pi/180) * lab.leaf, y = 5 + sin((start + 
                                                                                                                                                                                                                                                     deg * (t - 1)) * pi/180) * lab.leaf, label = paste(A, 
                                                                                                                                                                                                                                                                                                        ":", B, sep = "")), angle = 360/n * ((1:n) - 1)) + coord_fixed() + 
    theme_void()
  p
  return(list(p, ven2))
}

res13 <- ggflower.micro(
  ps    = ps.16s,
  group = "ID",   # 閺夆晜鐟╅崳鐑芥偨閵娧勭暠闁?ID闁挎稑鐬奸垾妯荤┍?sample_data 闂佹彃鏈﹢浣规交濞嗗繐鐏?
  start = 1,
  m1    = 2,
  a     = 0.3,
  b     = 1,
  lab.leaf = 1,
  col.cir  = "yellow",
  N        = 0.5
)

p13   <- res13[[1]]
dat13 <- res13[[2]]

save_plot2(p13, amplicon_composition_path, "13_flower_plot", base_width = 10, base_height = 10)
write_sheet2(amplicon_composition_wb, "13_flower_data", dat13)
## 濞ｅ洦绻傞悺銊︾▔閳ь剙鈻?Excel
# save_comp_wb(amplicon_composition_wb, comp_xlsx_path)
openxlsx::saveWorkbook(amplicon_composition_wb, comp_xlsx_path, overwrite = TRUE)




