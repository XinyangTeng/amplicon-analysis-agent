source(file.path(Sys.getenv("SCRIPT_DIR", "/project/yun/scripts"), "amp_common.R"), encoding = "UTF-8")
suppressPackageStartupMessages(library(e1071))

params <- read_amp_params()
ctx <- init_amp_context(params, "05_biomarker", "biomarker_results.xlsx")
res <- svm_micro(ps = ctx$ps %>% filter_OTU_ps(param_int(params, "filter_top_n", 20)), k = max(5L, param_int(params, "folds", 5)))
write_sheet2(ctx$workbook, "svm_AUC", res[[1]])
write_sheet2(ctx$workbook, "svm_importance", res[[2]])
save_amp_workbook(ctx)

