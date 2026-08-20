source(file.path(Sys.getenv("SCRIPT_DIR"), "amp_common.R"), encoding = "UTF-8")
params <- read_amp_params()
ctx <- init_amp_context(params, "05_differential_ancombc2", "ancombc2_results.xlsx")
amp_ancombc2_native(ctx, params)
