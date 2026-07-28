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
      "KEGG_enrich_note",
      amp_note_table("kegg_enrich", conditionMessage(e), "该步骤需要可访问 KEGG 在线数据；网络失败时保留差异功能输入表。")
    )
    NULL
  }
)

if (!is.null(enrich)) {
  for (nm in names(enrich)) {
    write_sheet2(ctx$workbook, paste0("KEGG_enrich_", make.names(nm)), enrich[[nm]])
  }
}
save_amp_workbook(ctx)

