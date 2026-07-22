source(file.path(Sys.getenv("SCRIPT_DIR", "/project/yun/scripts"), "amp_common.R"), encoding = "UTF-8")
suppressPackageStartupMessages({ library(igraph); library(ggClusterNet) })

params <- read_amp_params()
ctx <- init_amp_context(params, "06_network", "network_analysis.xlsx")
ps.16s <- ctx$ps

tab.r <- network.pip(
  ps = ps.16s,
  N = param_int(params, "top_n", 500),
  big = param_bool(params, "big_network", TRUE),
  select_layout = FALSE,
  layout_net = param_chr(params, "layout_net", "model_maptree2"),
  r.threshold = param_num(params, "cor_cutoff", 0.6),
  p.threshold = param_num(params, "p_cutoff", 0.05),
  maxnode = param_int(params, "maxnode", 2),
  label = FALSE,
  lab = "elements",
  group = "Group",
  fill = param_chr(params, "fill_rank", "Phylum"),
  size = "igraph.degree",
  zipi = TRUE,
  ram.net = TRUE,
  clu_method = param_chr(params, "cluster_method", "cluster_fast_greedy"),
  step = param_int(params, "step", 100),
  R = param_int(params, "random_times", 10),
  ncpus = param_int(params, "ncpus", 1)
)

cor <- tab.r[[2]]$net.cor.matrix$cortab
meta <- as.data.frame(sample_data(ps.16s), check.names = FALSE)
if (!"treat" %in% colnames(meta)) {
  meta$treat <- meta$Group
  sample_data(ps.16s) <- sample_data(meta)
}
treat_df <- data.frame(
  Group = as.character(meta$Group),
  stringsAsFactors = FALSE,
  row.names = rownames(meta)
)
treat_df$pair <- paste0("rep_", ave(seq_len(nrow(treat_df)), treat_df$Group, FUN = seq_along))
assign("treat", treat_df[, c("pair", "Group"), drop = FALSE], envir = .GlobalEnv)
res <- community.stability(ps = ps.16s, corg = cor, time = FALSE)
p <- res[[1]]
dat <- res[[2]]

save_plot2(p, ctx$out_dir, "community_stability", width = 10, height = 8)
save_preview_plot(p, width = 10, height = 8)
write_sheet2(ctx$workbook, "community_stability", dat)
save_amp_workbook(ctx)
