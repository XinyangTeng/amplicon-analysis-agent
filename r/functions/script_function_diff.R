source(file.path(Sys.getenv("SCRIPT_DIR", "/project/yun/scripts"), "amp_common.R"), encoding = "UTF-8")
params <- read_amp_params()
ctx <- init_amp_context(params, "08_function_prediction", "function_prediction_results.xlsx")
ps.kegg <- ctx$ps %>% filter_OTU_ps(param_int(params, "filter_top_n", 1000))

tax <- ps.kegg %>% phyloseq::tax_table()
ko_col <- param_int(params, "ko_column", 3)
colnames(tax)[ko_col] <- "KOid"
tax_table(ps.kegg) <- tax

res <- EdgerSuper.metf(ps = ps.kegg, group = "Group", artGroup = NULL)
write_sheet2(ctx$workbook, "differential_analysis", res[[2]])
save_amp_workbook(ctx)

