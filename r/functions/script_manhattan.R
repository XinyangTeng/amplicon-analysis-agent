source(file.path(Sys.getenv("SCRIPT_DIR", "/project/yun/scripts"), "amp_common.R"), encoding = "UTF-8")
params <- read_amp_params()
ctx <- init_amp_context(params, "04_differential", "differential_results.xlsx")
ps.16s <- ctx$ps

p_cutoff <- param_num(params, "p_cutoff", 0.05)
lfc <- param_num(params, "lfc_cutoff", 0)
top_n <- param_int(params, "filter_top_n", 500)

res <- edge_Manhattan.metm(
  ps = ps.16s %>% ggClusterNet::filter_OTU_ps(top_n),
  pvalue = p_cutoff,
  lfc = lfc
)
p <- if (is.list(res)) res[[1]] else res

save_plot2(p, ctx$out_dir, "27_Manhattan_plot1", width = 12, height = 8)
save_preview_plot(p, width = 12, height = 8)

