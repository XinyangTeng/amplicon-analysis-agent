source(file.path(Sys.getenv("SCRIPT_DIR"), "amp_common.R"), encoding = "UTF-8")
params <- read_amp_params()
ctx <- init_amp_context(params, "05_network_spieceasi", "spieceasi_results.xlsx")
amp_spieceasi_native(ctx, params)
