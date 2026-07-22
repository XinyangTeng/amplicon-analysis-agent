source(file.path(Sys.getenv("SCRIPT_DIR", "/project/yun/scripts"), "amp_common.R"), encoding = "UTF-8")
params <- read_amp_params()
ctx <- init_amp_context(params, "04_differential", "differential_results.xlsx")
ps.16s <- ctx$ps

top_n <- param_int(params, "filter_top_n", 500)
tax_level <- param_chr(params, "tax_level", "OTU")

res <- DESep2Super.micro(
  ps = ps.16s %>% ggClusterNet::filter_OTU_ps(top_n),
  group = "Group",
  artGroup = NULL,
  j = tax_level
)

p <- res[[1]]
if (is.list(p)) p <- p[[1]]
dat <- res[[2]]

save_plot2(p, ctx$out_dir, "26_DESeq2_plot1", width = 10, height = 8)
save_preview_plot(p, width = 10, height = 8)
write_sheet2(ctx$workbook, "26_DESeq2_results", dat)
save_amp_workbook(ctx)

