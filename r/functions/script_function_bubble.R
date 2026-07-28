source(file.path(Sys.getenv("SCRIPT_DIR"), "amp_common.R"), encoding = "UTF-8")
params <- read_amp_params()
ctx <- init_amp_context(params, "08_function", "function_results.xlsx")
amp_differential_native(ctx, "function_bubble", params, rank = "KO")
