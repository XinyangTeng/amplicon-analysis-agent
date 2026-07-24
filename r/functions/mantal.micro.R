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


mantal.micro = function (ps = ps, method = "spearman", dist_method = "bray", group = "Group", ncol = 5,
                         nrow = 2) 
{
  dist <- ggClusterNet::scale_micro(ps = ps, method = "rela") %>% 
    ggClusterNet::vegan_otu() %>% vegan::vegdist(method = dist_method) %>% 
    as.matrix()
  map = phyloseq::sample_data(ps)
  gru = map[, group][, 1] %>% unlist() %>% as.vector()
  id = combn(unique(gru), 2)
  R_mantel = c()
  p_mantel = c()
  name = c()
  R_pro <- c()
  p_pro <- c()
  plots = list()
  for (i in 1:dim(id)[2]) {
    id_dist <- row.names(map)[gru == id[1, i]]
    dist1 = dist[id_dist, id_dist]
    id_dist <- row.names(map)[gru == id[2, i]]
    id_dist = id_dist[1:nrow(dist1)]
    dist2 = dist[id_dist, id_dist]
    mt <- vegan::mantel(dist1, dist2, method = method)
    R_mantel[i] = mt$statistic
    p_mantel[i] = mt$signif
    name[i] = paste(id[1, i], "_VS_", id[2, i], sep = "")
    mds.s <- vegan::monoMDS(dist1)
    mds.r <- vegan::monoMDS(dist2)
    pro.s.r <- vegan::protest(mds.s, mds.r)
    R_pro[i] <- pro.s.r$ss
    p_pro[i] <- pro.s.r$signif
    Y <- cbind(data.frame(pro.s.r$Yrot), data.frame(pro.s.r$X))
    X <- data.frame(pro.s.r$rotation)
    Y$ID <- rownames(Y)
    p1 <- ggplot(Y) + geom_segment(aes(x = X1, y = X2, xend = (X1 + 
                                                                 MDS1)/2, yend = (X2 + MDS2)/2), arrow = arrow(length = unit(0, 
                                                                                                                             "cm")), color = "#B2182B", size = 1) + geom_segment(aes(x = (X1 + 
                                                                                                                                                                                            MDS1)/2, y = (X2 + MDS2)/2, xend = MDS1, yend = MDS2), 
                                                                                                                                                                                 arrow = arrow(length = unit(0, "cm")), color = "#56B4E9", 
                                                                                                                                                                                 size = 1) + geom_point(aes(X1, X2), fill = "#B2182B", 
                                                                                                                                                                                                        size = 4, shape = 21) + geom_point(aes(MDS1, MDS2), 
                                                                                                                                                                                                                                           fill = "#56B4E9", size = 4, shape = 21) + labs(title = paste(id[1, 
                                                                                                                                                                                                                                                                                                           i], "-", id[2, i], " ", "Procrustes analysis:\n    M2 = ", 
                                                                                                                                                                                                                                                                                                        round(pro.s.r$ss, 3), ", p-value = ", round(pro.s.r$signif, 
                                                                                                                                                                                                                                                                                                                                                    3), "\nMantel test:\n    r = ", round(R_mantel[i], 
                                                                                                                                                                                                                                                                                                                                                                                          3), ", p-value =, ", round(p_mantel[i], 3), sep = ""))
    p1 = p1 + theme_classic()
    plots[[i]] = p1
  }
  dat = data.frame(name, R_mantel, p_mantel, R_pro, p_pro)
  pp = ggpubr::ggarrange(plotlist = plots, common.legend = TRUE, 
                         legend = "right", ncol = ncol, nrow = nrow)
  return(list(dat, pp))
}


result_m <- mantal.micro(
  ps     = ps.16s,
  method = tolower(param_chr(params, "beta_mantel_method", "spearman")),
  dist_method = param_chr(params, "distance_method", "bray"),
  group  = "Group",
  ncol   = gnum,
  nrow   = 1
)

data_m <- result_m[[1]]
p3_7   <- result_m[[2]]

library(ggpubr)

# 闁烩晛鐡ㄧ敮瀵糕偓鐢靛帶閸ゎ參鏁嶇仦鑲╃憹闂傚洠鍋撻悷鏇氭祰濞村棝骞?
ggexport(p3_7, filename = file.path(amplicon_beta_path, "mantel_test.pdf"), 
         width = getOption("amp.plot_width", 10), height = getOption("amp.plot_height", 8))
write_sheet2(amplicon_beta_wb, "mantel_results", data_m)
openxlsx::saveWorkbook(amplicon_beta_wb ,beta_xlsx_path, overwrite = TRUE)




