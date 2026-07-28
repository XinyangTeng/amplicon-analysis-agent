source(file.path(Sys.getenv("SCRIPT_DIR"), "amp_common.R"), encoding = "UTF-8")
params <- read_amp_params()
ctx <- init_amp_context(params, "02_beta_diversity", "beta_results.xlsx")
amp_beta_native(ctx, "cluster", params)
