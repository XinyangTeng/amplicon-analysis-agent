source(file.path(Sys.getenv("SCRIPT_DIR", "/project/yun/scripts"), "amp_common.R"), encoding = "UTF-8")
suppressPackageStartupMessages({ library(igraph); library(ggClusterNet) })

params <- read_amp_params()
ctx <- init_amp_context(params, "06_network", "network_analysis.xlsx")
ps.16s <- ctx$ps

safe_network_step <- function(step_name, expr) {
  tryCatch(
    expr,
    error = function(e) {
      message("Network properties step skipped: ", step_name, ". Reason: ", conditionMessage(e))
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
network_ids <- names(cor)

safe_network_step("network_properties", {
  dat2 <- NULL
  for (id in network_ids) {
    graph_obj <- cor[[id]] %>% make_igraph()
    dat <- net_properties.4(graph_obj, n.hub = FALSE)
    dat <- as.data.frame(dat, check.names = FALSE)
    colnames(dat) <- id
    dat2 <- if (is.null(dat2)) dat else cbind(dat2, dat)
  }
  dat2 <- dat2 %>% tibble::rownames_to_column("Metric")
  write_sheet2(ctx$workbook, "network_properties", dat2)
})

safe_network_step("sample_network_properties", {
  dat.f2 <- NULL
  for (id in network_ids) {
    pst <- ps.16s %>% subset_samples.wt("Group", id) %>% remove.zero()
    dat.f <- netproperties.sample(pst = pst, cor = cor[[id]])
    dat.f2 <- if (is.null(dat.f2)) dat.f else rbind(dat.f2, dat.f)
  }
  map <- data.frame(sample_data(ps.16s), check.names = FALSE)
  map$ID <- rownames(map)
  dat3 <- dat.f2 %>% tibble::rownames_to_column("ID") %>% dplyr::inner_join(map, by = "ID")
  write_sheet2(ctx$workbook, "sample_network_properties", dat3)
})

safe_network_step("node_properties", {
  nodepro2 <- NULL
  for (id in network_ids) {
    graph_obj <- cor[[id]] %>% make_igraph()
    nodepro <- node_properties(graph_obj) %>% as.data.frame()
    nodepro$Group <- id
    colnames(nodepro) <- paste0(colnames(nodepro), ".", id)
    nodepro <- nodepro %>% as.data.frame() %>% tibble::rownames_to_column("ASV.name")
    nodepro2 <- if (is.null(nodepro2)) nodepro else dplyr::full_join(nodepro2, nodepro, by = "ASV.name")
  }
  write_sheet2(ctx$workbook, "node_properties", nodepro2)
})

safe_network_step("negative_correlation_ratio", {
  res4 <- negative.correlation.ratio(ps = ps.16s, corg = cortab, degree = TRUE, zipi = FALSE)
  p5 <- res4[[1]] + ggplot2::theme_classic()
  dat6 <- res4[[2]]
  save_plot2(p5, ctx$out_dir, "negative_correlation_ratio", width = 10, height = 8)
  save_preview_plot(p5, width = 10, height = 8)
  write_sheet2(ctx$workbook, "negative_correlation_ratio", dat6)
})

save_amp_workbook(ctx)
