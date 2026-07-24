source(file.path(Sys.getenv("SCRIPT_DIR", "/project/yun/scripts"), "amp_common.R"), encoding = "UTF-8")
params <- read_amp_params()
ctx <- init_amp_context(params, "06_community_assembly", "community_assembly_results.xlsx")
psphy <- filter_taxa(ctx$ps, function(x) sum(x) > param_num(params, "min_taxa_sum", 10), TRUE)
max_taxa <- param_int(params, "filter_top_n", 500)
if (ntaxa(psphy) > max_taxa) {
  keep_taxa <- names(sort(taxa_sums(psphy), decreasing = TRUE))[seq_len(max_taxa)]
  psphy <- prune_taxa(keep_taxa, psphy)
}

bnti_raw <- as.data.frame(
  bNTICul(ps = psphy, group = "Group", num = param_int(params, "permutations", 10), thread = param_int(params, "threads", 1))[[1]],
  check.names = FALSE
)
bnti_table <- bnti_raw
if ("bNTI" %in% names(bnti_table) && all(!is.finite(suppressWarnings(as.numeric(bnti_table$bNTI))))) {
  bnti_table$bNTI <- "not_estimable"
  bnti_table$bNTI_status <- "\u7f6e\u6362\u6807\u51c6\u5dee\u4e3a 0 \u6216\u7ed3\u679c\u4e0d\u53ef\u4f30\u8ba1\uff1b\u8bf7\u589e\u52a0\u7f6e\u6362\u6b21\u6570\u6216\u4f7f\u7528\u66f4\u5b8c\u6574\u6570\u636e\u3002"
}

rcb <- RCbary(ps = psphy, group = "Group", num = param_int(params, "permutations", 10), thread = param_int(params, "threads", 1))[[1]]
rcb_plot <- rcb %>% dplyr::mutate(Sample_1 = Site2, Sample_2 = Site1)
write_sheet2(ctx$workbook, "bNTI_results", bnti_table)
write_sheet2(ctx$workbook, "RCbray_results", rcb)

result <- tryCatch(
  bNTIRCPlot(ps = psphy, RCb = rcb_plot, bNTI = bnti_raw, group = "Group"),
  error = function(e) {
    write_sheet2(
      ctx$workbook,
      "bNTI_RCbray_plot_note",
      amp_note_table("bnti_rcbray", conditionMessage(e), "\u4f4e\u91cd\u590d\u6b21\u6570\u6216\u793a\u4f8b\u6570\u636e\u5bfc\u81f4\u53ef\u7ed8\u56fe\u70b9\u4e0d\u8db3\u65f6\uff0c\u4ec5\u8f93\u51fa bNTI \u4e0e RCbray \u8868\u683c\u3002")
    )
    NULL
  }
)

if (is.null(result)) {
  p <- amp_note_plot("bNTI / RCbray \u5df2\u5b8c\u6210", "\u5f53\u524d\u53c2\u6570\u4e0b\u53ef\u7ed8\u56fe\u70b9\u4e0d\u8db3\uff0c\u7ed3\u679c\u8868\u5df2\u5199\u5165 Excel\u3002")
  save_plot2(p, ctx$out_dir, "bNTI_RCbray_note", width = 10, height = 8)
  save_preview_plot(p, width = 10, height = 8)
} else {
  save_plot2(result[[1]], ctx$out_dir, "bNTI_plot", width = 10, height = 8)
  save_plot2(result[[2]], ctx$out_dir, "RCbray_plot", width = 10, height = 8)
  save_plot2(result[[3]], ctx$out_dir, "bNTI_RCbray_combined", width = 20, height = 10)
  save_preview_plot(result[[3]], width = 12, height = 8)
  write_sheet2(ctx$workbook, "bNTI_RCbray_plotdata", result[[4]])
  write_sheet2(ctx$workbook, "bNTI_RCbray_summary", result[[5]])
}
save_amp_workbook(ctx)
