source(file.path(Sys.getenv("SCRIPT_DIR", "/project/yun/scripts"), "amp_common.R"), encoding = "UTF-8")
params <- read_amp_params()
ctx <- init_amp_context(params, "05_biomarker", "biomarker_results.xlsx")
ps.16s <- ctx$ps

tablda <- LDA.micro(
  ps = ps.16s,
  Top = param_int(params, "top_n", 20),
  p.lvl = param_num(params, "p_cutoff", 0.05),
  lda.lvl = param_num(params, "lda_cutoff", 2),
  seed = param_int(params, "seed", 11),
  adjust.p = param_bool(params, "adjust_p", FALSE)
)
lefse_tab <- tablda[[2]]
p <- lefse_bar(taxtree = lefse_tab) + theme_classic()
save_plot2(p, ctx$out_dir, "35_LDA", width = 12, height = 8)
save_preview_plot(p, width = 12, height = 8)
write_sheet2(ctx$workbook, "35_LDA_results", lefse_tab)
save_amp_workbook(ctx)

