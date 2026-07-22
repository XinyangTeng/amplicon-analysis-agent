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

sankey.m.Group.micro = function (ps = ps, rank = 6, Top = 50) 
{
  map <- data.frame(sample_data(ps), check.names = FALSE)
  if ("ID" %in% colnames(map)) map$ID <- NULL
  map <- map %>%
    tibble::rownames_to_column("ID")
  otu = ps %>% vegan_otu() %>% as.data.frame()
  otu$ID = row.names(otu)
  tax = ps %>% scale_micro() %>% vegan_tax() %>% as.data.frame()
  tax$taxid = row.names(tax)
  head(tax)
  map$ID %in% otu$ID
  data <- map %>% 
    inner_join(otu, by = "ID") %>%   # 闁告梻濮崇粭?by = "ID" 闁哄洨绻濈换姘舵⒔?
    gather(key = "taxa", value = "count", starts_with("ASV")) %>% 
    inner_join(tax, by = c("taxa" = "taxid"))
  data
  tax = ps %>% ggClusterNet::tax_glom_wt(ranks = rank) %>% 
    ggClusterNet::filter_OTU_ps(Top) %>% subset_taxa(!Genus %in% 
                                                       c("Unassigned", "Unknown")) %>% ggClusterNet::vegan_tax() %>% 
    as.data.frame()
  head(tax)
  dim(tax)
  id2 = c("k", "p", "c", "o", "f", "g")
  dat = NULL
  for (i in 1:5) {
    dat <- tax[, c(i, i + 1)] %>% distinct(.keep_all = TRUE)
    colnames(dat) = c("source", "target")
    dat$source = paste(id2[i], dat$source, sep = "_")
    dat$target = paste(id2[i + 1], dat$target, sep = "_")
    if (i == 1) {
      dat2 = dat
    }
    dat2 = rbind(dat2, dat)
  }
  dim(dat2)
  otu = ps %>% ggClusterNet::tax_glom_wt(ranks = 6) %>% ggClusterNet::scale_micro() %>% 
    ggClusterNet::filter_OTU_ps(Top) %>% subset_taxa(!Genus %in% 
                                                       c("Unassigned", "Unknown")) %>% ggClusterNet::vegan_otu() %>% 
    t() %>% as.data.frame()
  head(otu)
  otutax = cbind(otu, tax)
  id = rank.names(ps)[1:6]
  dat = NULL
  dat3 = NULL
  head(data)
  for (j in 1) {
    dat = data %>% group_by(Group, !!sym(rank_names(ps)[j])) %>% 
      summarise_if(is.numeric, sum, na.rm = TRUE)
    colnames(dat) = c("source", "target", "value")
    dat$target = paste(id2[j], dat$target, sep = "_")
    if (j == 1) {
      dat3 = dat
    }
  }
  dat3 %>% tail()
  tem = data.frame(target = dat3$target, value = dat3$value)
  dat3$value = NULL
  head(dat2)
  dat2 = rbind(dat2, dat3)
  head(otutax)
  for (i in 1:6) {
    dat <- otutax %>% dplyr::group_by(!!sym(id[i])) %>% summarise_if(is.numeric, 
                                                                     sum, na.rm = TRUE)
    dat = data.frame(Genus = dat[, 1], value = rowSums(dat[, 
                                                           -1]))
    colnames(dat) = c("target", "value")
    dat$target = paste(id2[i], dat$target, sep = "_")
    if (i == 1) {
      dat3 = dat
    }
    dat3 = rbind(dat3, dat)
  }
  dat4 <- dat2 %>% left_join(dat3)
  sankey = dat4
  head(sankey)
  nodes <- data.frame(name = unique(c(as.character(sankey$source), 
                                      as.character(sankey$target))), stringsAsFactors = FALSE)
  nodes$ID <- 0:(nrow(nodes) - 1)
  sankey <- merge(sankey, nodes, by.x = "source", by.y = "name")
  sankey <- merge(sankey, nodes, by.x = "target", by.y = "name")
  colnames(sankey) <- c("X", "Y", "value", "source", "target")
  sankey <- subset(sankey, select = c("source", "target", "value"))
  nodes <- subset(nodes, select = c("name"))
  ColourScal = "d3.scaleOrdinal() .range([\"#E41A1C\", \"#377EB8\", \"#4DAF4A\", \"#984EA3\", \"#FF7F00\", \"#FFFF33\", \"#A65628\", \"#F781BF\", \"#999999\"])"
  sankey$energy_type <- sub(" .*", "", nodes[sankey$source + 
                                               1, "name"])
  library(networkD3)
  p <- sankeyNetwork(Links = sankey, Nodes = nodes, Source = "source", 
                     Target = "target", Value = "value", NodeID = "name", 
                     sinksRight = FALSE, LinkGroup = "energy_type", colourScale = ColourScal, 
  )
  return(list(p, sankey))
}

comp_top_n <- param_int(params, "comp_top_n", 50)

res23 <- sankey.m.Group.micro(
  ps   = ps.16s %>% subset_taxa.wt("Species", "Unassigned", TRUE),
  rank = 6,
  Top  = comp_top_n
)

p23   <- res23[[1]]
dat23 <- res23[[2]]

# 濞ｅ洦绻傞悺銊︾閵堝嫮闉?HTML
saveNetwork(
  p23,
  file.path(amplicon_composition_path, "23_sankey_Group.html"),
  selfcontained = FALSE
)

# 闁轰胶澧楀畵浣烘偘閵娿儱鏅搁柛?Excel
write_sheet2(amplicon_composition_wb, "23_sankey_group_data", dat23)
## 濞ｅ洦绻傞悺銊︾▔閳ь剙鈻?Excel
# save_comp_wb(amplicon_composition_wb, comp_xlsx_path)
openxlsx::saveWorkbook(amplicon_composition_wb, comp_xlsx_path, overwrite = TRUE)





