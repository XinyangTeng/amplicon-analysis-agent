source(file.path(Sys.getenv("SCRIPT_DIR", "/project/yun/scripts"), "amp_common.R"), encoding = "UTF-8")
params <- read_amp_params()
ctx <- init_amp_context(params, "04_differential", "differential_results.xlsx")
ps.16s <- ctx$ps

top_n <- param_int(params, "filter_top_n", 500)
tax_level <- param_chr(params, "tax_level", "OTU")

res <- EdgerSuper.metm(
  ps = ps.16s %>% ggClusterNet::filter_OTU_ps(top_n),
  group = "Group",
  artGroup = NULL,
  j = tax_level
)

plots <- res[[1]]
dat <- res[[2]]

if (is.list(plots)) {
  for (i in seq_along(plots)) {
    save_plot2(plots[[i]], ctx$out_dir, paste0("25_EdgeR_plot_", i), width = 10, height = 8)
  }
  save_preview_plot(plots[[1]], width = 10, height = 8)
} else {
  save_plot2(plots, ctx$out_dir, "25_EdgeR_plot1", width = 10, height = 8)
  save_preview_plot(plots, width = 10, height = 8)
}

write_sheet2(ctx$workbook, "25_EdgeR_results", dat)
save_amp_workbook(ctx)

