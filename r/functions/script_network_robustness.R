source(file.path(Sys.getenv("SCRIPT_DIR", "/project/yun/scripts"), "amp_common.R"), encoding = "UTF-8")
suppressPackageStartupMessages({
  library(igraph)
  library(ggClusterNet)
  library(patchwork)
  library(pulsar)
  library(ggtern)
})

params <- read_amp_params()
ctx <- init_amp_context(params, "06_network", "network_analysis.xlsx")
ps.16s <- ctx$ps

safe_network_step <- function(step_name, expr) {
  tryCatch(
    expr,
    error = function(e) {
      message("Network robustness step skipped: ", step_name, ". Reason: ", conditionMessage(e))
      write_sheet2(ctx$workbook, paste0(substr(step_name, 1, 24), "_error"), data.frame(
        step = step_name,
        error = conditionMessage(e),
        stringsAsFactors = FALSE
      ))
      NULL
    }
  )
}

tab.r <- network.pip(
  ps = ps.16s,
  N = param_int(params, "top_n", 500),
  big = param_bool(params, "big_network", TRUE),
  select_layout = FALSE,
  layout_net = param_chr(params, "layout_net", "model_maptree2"),
  r.threshold = param_num(params, "cor_cutoff", 0.6),
  p.threshold = param_num(params, "p_cutoff", 0.05),
  maxnode = param_int(params, "maxnode", 2),
  label = FALSE,
  lab = "elements",
  group = "Group",
  fill = param_chr(params, "fill_rank", "Phylum"),
  size = "igraph.degree",
  zipi = TRUE,
  ram.net = TRUE,
  clu_method = param_chr(params, "cluster_method", "cluster_fast_greedy"),
  step = param_int(params, "step", 100),
  R = param_int(params, "random_times", 10),
  ncpus = param_int(params, "ncpus", 1)
)

cortab <- tab.r[[2]]$net.cor.matrix$cortab
cor <- cortab
preview_plot <- NULL

safe_network_step("network_robustness", {
  res <- natural.con.microp(
    ps = ps.16s,
    corg = cor,
    norm = TRUE,
    end = param_int(params, "robustness_end", 150),
    start = param_int(params, "robustness_start", 0)
  )
  p <- res[[1]]
  dat <- res[[2]]
  preview_plot <<- p
  save_plot2(p, ctx$out_dir, "network_robustness", width = 10, height = 8)
  write_sheet2(ctx$workbook, "network_robustness", dat)
})

safe_network_step("robustness_targeted", {
  res <- Robustness.Targeted.removal(ps = ps.16s, corg = cor, degree = TRUE, zipi = FALSE)
  p <- res[[1]]
  dat <- res[[2]]
  if (is.null(preview_plot)) preview_plot <<- p
  save_plot2(p, ctx$out_dir, "robustness_targeted", width = 10, height = 8)
  write_sheet2(ctx$workbook, "robustness_targeted", dat)
})

safe_network_step("robustness_random", {
  res <- Robustness.Random.removal(ps = ps.16s, corg = cortab, Top = param_int(params, "robustness_random_top", 0))
  p <- res[[1]]
  dat <- res[[2]]
  if (is.null(preview_plot)) preview_plot <<- p
  save_plot2(p, ctx$out_dir, "robustness_random", width = 10, height = 8)
  write_sheet2(ctx$workbook, "robustness_random", dat)
})

if (!is.null(preview_plot)) {
  save_preview_plot(preview_plot, width = 10, height = 8)
}
save_amp_workbook(ctx)
