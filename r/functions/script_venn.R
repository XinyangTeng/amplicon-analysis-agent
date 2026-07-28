source(file.path(Sys.getenv("SCRIPT_DIR"), "amp_common.R"), encoding = "UTF-8")
params <- read_amp_params()
ctx <- init_amp_context(params, "03_composition", "composition_results.xlsx")
amp_composition_native(ctx, "venn", params)
