source(file.path(Sys.getenv("SCRIPT_DIR", "/project/yun/scripts"), "amp_common.R"), encoding = "UTF-8")
params <- read_amp_params()
ctx <- init_amp_context(params, "05_biomarker", "biomarker_results.xlsx")
res <- naivebayes.micro(ps = ctx$ps, top = param_int(params, "top_n", 20), seed = param_int(params, "seed", 1010), k = param_int(params, "folds", 5))
write_sheet2(ctx$workbook, "naivebayes_accuracy", res[[1]])
write_sheet2(ctx$workbook, "naivebayes_importance", res[[2]])
save_amp_workbook(ctx)

