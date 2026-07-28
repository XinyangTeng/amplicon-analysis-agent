source(file.path(Sys.getenv("SCRIPT_DIR"), "amp_common.R"), encoding = "UTF-8")
params <- read_amp_params()
ctx <- init_amp_context(params, "06_assembly", "assembly_results.xlsx")
amp_bnti_native(ctx, params, include_rcbray = TRUE)
