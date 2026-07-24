source(file.path(Sys.getenv("SCRIPT_DIR", "/project/yun/scripts"), "amp_common.R"), encoding = "UTF-8")
suppressPackageStartupMessages(library(ggrepel))

params <- read_amp_params()
ctx <- init_amp_context(params, "04_differential", "differential_results.xlsx")
ps.16s <- ctx$ps

case_group <- param_chr(params, "case_group", "")
control_group <- param_chr(params, "control_group", "")
groups <- unique(sample_data(ps.16s)$Group)

if (!nzchar(case_group) || !nzchar(control_group)) {
  pair <- combn(groups, 2)[, 1]
} else {
  pair <- c(case_group, control_group)
}

res_input <- tryCatch(
  EdgerSuper2.metm(
    ps = ps.16s,
    group = "Group",
    artGroup = data.frame(group2 = pair),
    j = param_chr(params, "tax_level", "OTU")
  ),
  error = function(e) {
    write_sheet2(
      ctx$workbook,
      "volcano_specific_note",
      amp_note_table("volcano_specific", conditionMessage(e), "指定比较组合不适配旧函数时，自动回退到全部组比较。")
    )
    EdgerSuper2.metm(
      ps = ps.16s,
      group = "Group",
      artGroup = NULL,
      j = param_chr(params, "tax_level", "OTU")
    )
  }
)

res <- Mui.cluster.volcano.micro(res = res_input, rs.k = param_int(params, "cluster_k", 6))
p <- res[[1]] + ggtitle(paste(pair, collapse = "-"))
dat <- res[[3]]

save_plot2(p, ctx$out_dir, "30_volcano_specific1", width = 12, height = 8)
save_preview_plot(p, width = 12, height = 8)
write_sheet2(ctx$workbook, "30_volcano_specific_data", dat)
save_amp_workbook(ctx)

