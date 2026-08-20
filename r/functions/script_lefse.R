source(file.path(Sys.getenv("SCRIPT_DIR"), "amp_common.R"), encoding = "UTF-8")
params <- read_amp_params()
ctx <- init_amp_context(params, "05_biomarker_lefse", "lefse_results.xlsx")
amp_lefse_native(ctx, params)
