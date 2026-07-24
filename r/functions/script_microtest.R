source(file.path(Sys.getenv("SCRIPT_DIR", "/project/yun/scripts"), "amp_common.R"), encoding = "UTF-8")
params <- read_amp_params()
ctx <- init_amp_context(params, "02_beta_diversity", "beta_diversity.xlsx")
ps.16s <- ctx$ps

method <- normalize_microtest_method(param_chr(params, "microtest_method", "adonis"), "adonis")
dist_method <- param_chr(params, "distance_method", "bray")

dat <- MicroTest.micro(ps = ps.16s, Micromet = method, dist = dist_method)
write_sheet2(ctx$workbook, "microtest_results", dat)
save_amp_workbook(ctx)

