source(file.path(Sys.getenv("SCRIPT_DIR", "/project/yun/scripts"), "amp_common.R"), encoding = "UTF-8")
params <- read_amp_params()
ctx <- init_amp_context(params, "06_community_assembly", "community_assembly_results.xlsx")
ps.16s <- ctx$ps

n <- length(unique(sample_data(ps.16s)$Group))
result <- tryCatch(
  neutralModel(ps = ps.16s, group = "Group", ncol = n),
  error = function(e) {
    message("Neutral model fitting failed; writing fallback result. Reason: ", conditionMessage(e))
    NULL
  }
)

if (is.null(result)) {
  note <- amp_note_table(
    "neutral_model",
    "Neutral model fitting failed for the current data and parameters.",
    "Use a larger dataset or adjust feature filtering before rerunning."
  )
  p <- amp_note_plot("Neutral model skipped", "The model could not be fitted; see Excel note.")
  save_plot2(p, ctx$out_dir, "neutral_model_note", width = 10, height = 8)
  save_preview_plot(p, width = 10, height = 8)
  write_sheet2(ctx$workbook, "neutral_model_note", note)
} else {
  p <- result[[1]]
  dat <- result[[3]][[1]]
  dat2 <- result[[4]][[1]]

  save_plot2(p, ctx$out_dir, "neutral_model", width = 30, height = 16)
  save_preview_plot(p, width = 12, height = 8)
  write_sheet2(ctx$workbook, "neutral_model_data1", dat)
  write_sheet2(ctx$workbook, "neutral_model_data2", dat2)
}
save_amp_workbook(ctx)

