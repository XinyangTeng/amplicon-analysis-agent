source(file.path(Sys.getenv("SCRIPT_DIR"), "amp_common.R"), encoding = "UTF-8")
params <- read_amp_params()
ctx <- init_amp_context(params, "05_differential_maaslin2", "maaslin2_results.xlsx")
amp_maaslin2_native(ctx, params)
