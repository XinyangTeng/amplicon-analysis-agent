source(file.path(Sys.getenv("SCRIPT_DIR", "/project/yun/scripts"), "amp_common.R"), encoding = "UTF-8")
suppressPackageStartupMessages({ library(DOSE); library(GO.db); library(GSEABase); library(clusterProfiler) })

params <- read_amp_params()
ctx <- init_amp_context(params, "08_function_prediction", "function_prediction_results.xlsx")
ps.kegg <- ctx$ps %>% filter_OTU_ps(param_int(params, "filter_top_n", 1000))
tax <- ps.kegg %>% phyloseq::tax_table()
colnames(tax)[param_int(params, "ko_column", 3)] <- "KOid"
tax_table(ps.kegg) <- tax

diff_res <- EdgerSuper.metf(ps = ps.kegg, group = "Group", artGroup = NULL)
write_sheet2(ctx$workbook, "function_diff_input", diff_res[[2]])

enrich <- tryCatch(
  KEGG_enrich.micro(ps = ps.kegg, dif = diff_res[[2]]),
  error = function(e) {
    write_sheet2(
      ctx$workbook,
      "function_bubble_note",
      amp_note_table("function_bubble", conditionMessage(e), "该步骤需要可访问 KEGG 在线数据；网络失败时保留差异功能输入表。")
    )
    NULL
  }
)

if (is.null(enrich) || length(enrich) == 0) {
  p1 <- amp_note_plot("功能气泡图未生成", "KEGG 在线数据不可用，详情见 Excel。")
  save_plot2(p1, ctx$out_dir, "function_bubble_note", width = 10, height = 8)
  save_preview_plot(p1, width = 10, height = 8)
} else {
  first_name <- names(enrich)[1]
  write_sheet2(ctx$workbook, paste0("KEGG_enrich_", make.names(first_name)), enrich[[first_name]])
  result <- buplot.micro(dt = enrich[[first_name]], id = paste0(first_name, "_level"))
  p1 <- result[[1]]
  p2 <- result[[2]]

  save_plot2(p1, ctx$out_dir, "function_bubble_plot1", width = 10, height = 8)
  save_plot2(p2, ctx$out_dir, "function_bubble_plot2", width = 10, height = 8)
  save_preview_plot(p1, width = 10, height = 8)
}
save_amp_workbook(ctx)

