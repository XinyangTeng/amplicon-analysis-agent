source(file.path(Sys.getenv("SCRIPT_DIR"), "amp_common.R"), encoding = "UTF-8")
params <- read_amp_params()
ctx <- init_amp_context(params, "04_differential", "differential_results.xlsx")
amp_edger_native(ctx, "volcano", params, rank = param_chr(params, "tax_level", "Genus"))
