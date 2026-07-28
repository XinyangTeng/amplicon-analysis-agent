source(file.path(Sys.getenv("SCRIPT_DIR", "/project/yun/scripts"), "amp_common.R"), encoding = "UTF-8")
params <- read_amp_params()
ctx <- init_amp_context(params, "06_community_assembly", "community_assembly_results.xlsx")
psphy <- filter_taxa(ctx$ps, function(x) sum(x) > param_num(params, "min_taxa_sum", 10), TRUE)
max_taxa <- param_int(params, "filter_top_n", 500)
if (ntaxa(psphy) > max_taxa) {
  keep_taxa <- names(sort(taxa_sums(psphy), decreasing = TRUE))[seq_len(max_taxa)]
  psphy <- prune_taxa(keep_taxa, psphy)
}

result <- RCbary(ps = psphy, group = "Group", num = param_int(params, "permutations", 10), thread = param_int(params, "threads", 1))
write_sheet2(ctx$workbook, "RCbray_results", result[[1]])
save_amp_workbook(ctx)

