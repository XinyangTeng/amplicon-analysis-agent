source(file.path(Sys.getenv("SCRIPT_DIR", "/project/yun/scripts"), "amp_common.R"), encoding = "UTF-8")
params <- read_amp_params()
ctx <- init_amp_context(params, "07_other_analysis", "other_analysis_results.xlsx")

sink_group <- param_chr(params, "sink_group", "OE")
source_groups <- param_vec(params, "source_groups", c("WT", "KO"))
result <- tryCatch(
  FEAST.micro(ps = ctx$ps, group = "Group", sinkG = sink_group, sourceG = source_groups),
  error = function(e) {
    amp_note_table("feast", conditionMessage(e), "请确认目标组和来源组名称存在于分组列中；默认示例数据没有 OE/WT/KO 时会跳过绘图。")
  }
)

write_sheet2(ctx$workbook, "FEAST_results", result)

if (is.data.frame(result) && "status" %in% colnames(result)) {
  p <- amp_note_plot("FEAST 未执行", "目标组或来源组与当前数据不匹配，详情见 Excel。")
  save_plot2(p, ctx$out_dir, "FEAST_note", width = 10, height = 8)
  save_preview_plot(p, width = 10, height = 8)
} else {
  p1 <- Plot_FEAST(data = result)
  p2 <- MuiPlot_FEAST(data = result)
  save_plot2(p1, ctx$out_dir, "FEAST_group", width = 10, height = 8)
  save_plot2(p2, ctx$out_dir, "FEAST_sample", width = 10, height = 8)
  save_preview_plot(p1, width = 10, height = 8)
}
save_amp_workbook(ctx)

