source(file.path(Sys.getenv("SCRIPT_DIR"), "amp_common.R"), encoding = "UTF-8")
params <- read_amp_params()
ctx <- init_amp_context(params, "02_beta_gunifrac", "gunifrac_results.xlsx")
amp_gunifrac_native(ctx, params)
