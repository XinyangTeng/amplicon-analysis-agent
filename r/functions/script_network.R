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
  label = param_bool(params, "show_label", FALSE),
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

plot <- tab.r[[1]][[1]]
cortab <- tab.r[[2]]$net.cor.matrix$cortab
cor_matrix <- as.data.frame(cortab, check.names = FALSE)
cor_matrix <- tibble::rownames_to_column(cor_matrix, "ASV_ID")

save_plot2(plot, ctx$out_dir, "network_main", width = 45, height = 30)
save_preview_plot(plot, width = 12, height = 8)
write_sheet2(ctx$workbook, "network_cor_matrix", cor_matrix)
save_amp_workbook(ctx)
