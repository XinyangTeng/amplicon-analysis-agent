source(file.path(Sys.getenv("SCRIPT_DIR"), "amp_common.R"), encoding = "UTF-8")
params <- read_amp_params()
ctx <- init_amp_context(params, "05_network_compositional", "network_compositional_results.xlsx")
amp_network_compositional_native(ctx, params)
