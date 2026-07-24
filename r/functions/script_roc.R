source(file.path(Sys.getenv("SCRIPT_DIR", "/project/yun/scripts"), "amp_common.R"), encoding = "UTF-8")
suppressPackageStartupMessages({ library(ROCR); library(e1071) })

params <- read_amp_params()
ctx <- init_amp_context(params, "05_biomarker", "biomarker_results.xlsx")
ps.16s <- ctx$ps

groups <- unique(sample_data(ps.16s)$Group)
case_group <- param_chr(params, "case_group", "")
control_group <- param_chr(params, "control_group", "")
pair <- if (nzchar(case_group) && nzchar(control_group)) c(case_group, control_group) else combn(groups, 2)[, 1]

pst <- ps.16s %>%
  subset_taxa.wt("Family", "Unassigned", TRUE) %>%
  subset_taxa.wt("Order", "Unassigned", TRUE) %>%
  subset_taxa.wt("Genus", "Unassigned", TRUE) %>%
  subset_taxa.wt("Phylum", "Unassigned", TRUE) %>%
  subset_samples.wt("Group", pair) %>%
  filter_taxa(function(x) sum(x) > param_num(params, "min_taxa_sum", 10), prune = TRUE)

res <- Roc.micro(ps = pst %>% filter_OTU_ps(param_int(params, "filter_top_n", 1000)), group = "Group", repnum = param_int(params, "repnum", 5))
p <- res[[1]] + theme_classic()
dat <- res[[3]]
if (ncol(dat) == 6) {
  colnames(dat) <- c(
    "RF_true_group", "RF_probability",
    "SVM_true_group", "SVM_probability",
    "GLM_true_group", "GLM_probability"
  )
}
save_plot2(p, ctx$out_dir, "33_ROC_plot1", width = 10, height = 8)
save_preview_plot(p, width = 10, height = 8)
write_sheet2(ctx$workbook, "33_ROC_results", dat)
save_amp_workbook(ctx)

