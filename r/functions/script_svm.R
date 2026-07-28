source(file.path(Sys.getenv("SCRIPT_DIR"), "amp_common.R"), encoding = "UTF-8")
params <- read_amp_params()
ctx <- init_amp_context(params, "07_machine_learning", "machine_learning_results.xlsx")
amp_ml_analysis(ctx, "svm", params)
