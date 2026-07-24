source(file.path(Sys.getenv("SCRIPT_DIR", "/project/yun/scripts"), "amp_common.R"), encoding = "UTF-8")
suppressPackageStartupMessages({ library(FSA); library(eulerr); library(minpack.lm); library(Hmisc) })

params <- read_amp_params()
ctx <- init_amp_context(params, "06_community_assembly", "community_assembly_results.xlsx")
psphy <- filter_taxa(ctx$ps, function(x) sum(x) > param_num(params, "min_taxa_sum", 10), TRUE)

if (!exists("nullModel", mode = "function")) {
  note <- amp_note_table(
    "null_model",
    "The optional null-model implementation is not installed in this runtime.",
    "Provide a compatible nullModel function or use the neutral-model and RCbray functions."
  )
  write_sheet2(ctx$workbook, "null_model_status", note)
  save_amp_workbook(ctx)
  quit(save = "no", status = 0)
}

result <- nullModel(
  ps = psphy,
  group = "Group",
  dist.method = param_chr(params, "distance_method", "bray"),
  gamma.method = param_chr(params, "gamma_method", "total"),
  transfer = param_chr(params, "transfer", "none"),
  null.model = param_chr(params, "null_model", "ecosphere")
)

write_sheet2(ctx$workbook, "null_model_results", result[[1]])
write_sheet2(ctx$workbook, "null_model_ratio", result[[2]])
aov_table <- tryCatch({
  dat <- as.data.frame(stats::anova(result[[3]]), check.names = FALSE)
  tibble::rownames_to_column(dat, "Term")
}, error = function(e) {
  data.frame(Output = capture.output(print(result[[3]])), stringsAsFactors = FALSE)
})
write_sheet2(ctx$workbook, "null_model_aov", aov_table)
save_amp_workbook(ctx)

