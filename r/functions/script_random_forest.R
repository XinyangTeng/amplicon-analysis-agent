source(file.path(Sys.getenv("SCRIPT_DIR", "/project/yun/scripts"), "amp_common.R"), encoding = "UTF-8")
suppressPackageStartupMessages(library(randomForest))

params <- read_amp_params()
ctx <- init_amp_context(params, "05_biomarker", "biomarker_results.xlsx")
res <- randomforest.micro(ps = ctx$ps, group = "Group", optimal = param_int(params, "optimal", 50))
p1 <- res[[1]]
p4 <- res[[4]]
dat <- res[[3]]
if ("id" %in% names(dat)) {
  names(dat)[names(dat) == "id"] <- "ASV_ID"
  dat <- dat[, c("ASV_ID", setdiff(names(dat), "ASV_ID")), drop = FALSE]
}
save_plot2(p1, ctx$out_dir, "randomforest_plot1", width = 20, height = 16)
save_plot2(p4, ctx$out_dir, "randomforest_plot4", width = 20, height = 20)
save_preview_plot(p1, width = 12, height = 8)
write_sheet2(ctx$workbook, "randomforest_results", dat)
save_amp_workbook(ctx)

