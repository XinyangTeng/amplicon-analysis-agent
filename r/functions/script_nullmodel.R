source(file.path(Sys.getenv("SCRIPT_DIR"), "amp_common.R"), encoding = "UTF-8")
params <- read_amp_params()
ctx <- init_amp_context(params, "06_assembly", "assembly_results.xlsx")
amp_group_null_model_native(ctx, params)
