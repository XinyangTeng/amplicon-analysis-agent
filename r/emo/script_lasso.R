source(file.path(Sys.getenv("SCRIPT_DIR", "/project/yun/scripts"), "amp_common.R"), encoding = "UTF-8")
suppressPackageStartupMessages(library(glmnet))

params <- read_amp_params()
ctx <- init_amp_context(params, "05_biomarker", "biomarker_results.xlsx")
ps_lasso <- ctx$ps
groups <- unique(as.character(sample_data(ps_lasso)$Group))
case_group <- param_chr(params, "case_group", "")
control_group <- param_chr(params, "control_group", "")
selected_groups <- c(case_group, control_group)
selected_groups <- selected_groups[nzchar(selected_groups)]
if (length(selected_groups) < 2) {
  selected_groups <- groups[seq_len(min(2, length(groups)))]
}
if (length(selected_groups) != 2) {
  stop("LASSO requires exactly two groups. Set case_group and control_group.")
}
ps_lasso <- subset_samples(ps_lasso, Group %in% selected_groups)
ps_lasso <- prune_taxa(taxa_sums(ps_lasso) > 0, ps_lasso)
k <- min(param_int(params, "folds", 5), min(table(sample_data(ps_lasso)$Group)))
if (k < 2) stop("LASSO requires at least two samples per selected group.")
res <- tryCatch(
  lasso.micro(ps = ps_lasso, top = param_int(params, "top_n", 20), seed = param_int(params, "seed", 1010), k = k),
  error = function(e) {
    message("LASSO skipped: ", conditionMessage(e))
    list(
      data.frame(status = "skipped", reason = conditionMessage(e), stringsAsFactors = FALSE),
      data.frame(status = "skipped", reason = conditionMessage(e), stringsAsFactors = FALSE)
    )
  }
)
write_sheet2(ctx$workbook, "lasso_accuracy", res[[1]])
write_sheet2(ctx$workbook, "lasso_importance", res[[2]])
save_amp_workbook(ctx)

