source(file.path(Sys.getenv("SCRIPT_DIR", "/project/yun/scripts"), "amp_common.R"), encoding = "UTF-8")
params <- read_amp_params()
ctx <- init_amp_context(params, "04_differential", "differential_results.xlsx")
ps.16s <- ctx$ps

top_n <- param_int(params, "top_n", 20)
rank <- param_int(params, "tax_rank", 6)
groups <- unique(sample_data(ps.16s)$Group)
if (length(groups) < 2) stop("STAMP analysis requires at least 2 groups.")

meta <- data.frame(sample_data(ps.16s), check.names = FALSE)
meta$ID <- rownames(meta)
sample_data(ps.16s) <- sample_data(meta)

pairs <- combn(groups, 2)
for (i in seq_len(ncol(pairs))) {
  ps_sub <- subset_samples(ps.16s, Group %in% pairs[, i])
  p <- stemp_diff.micro(ps = ps_sub, Top = top_n, ranks = rank)
  save_plot2(p, ctx$out_dir, paste0("28_stamp_plot", i), width = 10, height = 8)
  if (i == 1) save_preview_plot(p, width = 10, height = 8)
}

