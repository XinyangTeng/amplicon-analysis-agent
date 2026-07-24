source(file.path(Sys.getenv("SCRIPT_DIR", "/project/yun/scripts"), "amp_common.R"), encoding = "UTF-8")
suppressPackageStartupMessages(library(parallel))

params <- read_amp_params()
ctx <- init_amp_context(params, "06_community_assembly", "community_assembly_results.xlsx")
psphy <- filter_taxa(ctx$ps, function(x) sum(x) > param_num(params, "min_taxa_sum", 10), TRUE)
max_taxa <- param_int(params, "filter_top_n", 500)
if (ntaxa(psphy) > max_taxa) {
  keep_taxa <- names(sort(taxa_sums(psphy), decreasing = TRUE))[seq_len(max_taxa)]
  psphy <- prune_taxa(keep_taxa, psphy)
}

result <- bNTICul(ps = psphy, group = "Group", num = param_int(params, "permutations", 10), thread = param_int(params, "threads", 1))
bnti <- as.data.frame(result[[1]], check.names = FALSE)
if ("bNTI" %in% names(bnti) && all(!is.finite(suppressWarnings(as.numeric(bnti$bNTI))))) {
  bnti$bNTI <- "not_estimable"
  bnti$bNTI_status <- "\u7f6e\u6362\u6807\u51c6\u5dee\u4e3a 0 \u6216\u7ed3\u679c\u4e0d\u53ef\u4f30\u8ba1\uff1b\u8bf7\u589e\u52a0\u7f6e\u6362\u6b21\u6570\u6216\u4f7f\u7528\u66f4\u5b8c\u6574\u6570\u636e\u3002"
}
write_sheet2(ctx$workbook, "bNTI_results", bnti)
save_amp_workbook(ctx)

