source(file.path(Sys.getenv("SCRIPT_DIR", "/project/yun/scripts"), "amp_common.R"), encoding = "UTF-8")
params <- read_amp_params()
ctx <- init_amp_context(params, "05_biomarker", "biomarker_results.xlsx")
ps.16s <- ctx$ps

res <- loadingPCA.micro(ps = ps.16s, Top = param_int(params, "top_n", 20))
p <- res[[1]] + theme_classic()
dat <- res[[2]]
if ("id" %in% names(dat)) {
  names(dat)[names(dat) == "id"] <- "ASV_ID"
  dat <- dat[, c("ASV_ID", setdiff(names(dat), "ASV_ID")), drop = FALSE]
}
save_plot2(p, ctx$out_dir, "34_loadingPCA", width = 10, height = 8)
save_preview_plot(p, width = 10, height = 8)
write_sheet2(ctx$workbook, "34_loadingPCA_results", dat)
save_amp_workbook(ctx)

