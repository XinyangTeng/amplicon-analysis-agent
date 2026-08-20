source(file.path(Sys.getenv("SCRIPT_DIR"), "amp_common.R"), encoding = "UTF-8")
params <- read_amp_params()
ctx <- init_amp_context(params, "05_differential_maaslin3", "maaslin3_results.xlsx")
amp_maaslin3_native(ctx, params)
