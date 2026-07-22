source(file.path(Sys.getenv("SCRIPT_DIR", "/project/yun/scripts"), "amp_common.R"), encoding = "UTF-8")
suppressPackageStartupMessages({ library(randomForest); library(caret) })

params <- read_amp_params()
ctx <- init_amp_context(params, "05_biomarker", "biomarker_results.xlsx")
ps.16s <- ctx$ps

res <- rfcv.Micro(
  ps = ps.16s %>% filter_OTU_ps(param_int(params, "filter_top_n", 100)),
  group = "Group",
  optimal = param_int(params, "optimal", 20),
  nrfcvnum = max(6L, param_int(params, "folds", 6))
)
p <- res[[1]] + theme_classic()
dat <- res[[3]]
if ("RowName" %in% names(dat) && all(grepl("^[0-9]+$", as.character(dat$RowName)))) {
  names(dat)[names(dat) == "RowName"] <- "feature_count"
}
if ("num" %in% names(dat)) {
  names(dat)[names(dat) == "num"] <- "feature_count"
}
rownames(dat) <- NULL
save_plot2(p, ctx$out_dir, "32_rfcv", width = 10, height = 8)
save_preview_plot(p, width = 10, height = 8)
write_sheet2(ctx$workbook, "32_rfcv_results", dat)
save_amp_workbook(ctx)

