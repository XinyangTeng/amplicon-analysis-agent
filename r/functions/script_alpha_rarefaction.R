source(file.path(Sys.getenv("SCRIPT_DIR"), "amp_common.R"), encoding = "UTF-8")
params <- read_amp_params()
ctx <- init_amp_context(params, "01_alpha_diversity", "alpha_results.xlsx")
amp_alpha_rarefaction_native(ctx, params)
