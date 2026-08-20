# -*- coding: utf-8 -*-

if (capabilities("cairo")) options(bitmapType = "cairo")

suppressPackageStartupMessages({
  required_packages <- c("jsonlite", "phyloseq", "tidyverse", "Biostrings", "ggsci",
                         "openxlsx", "ape", "picante", "minpack.lm", "Hmisc", "fs")
  missing_required <- required_packages[!vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing_required)) stop("Missing required analysis packages: ", paste(missing_required, collapse = ", "))
  for (pkg_name in required_packages) library(pkg_name, character.only = TRUE)
  for (pkg_name in c("ggClusterNet", "EasyMicroPlot", "EasyStat", "TOmicsVis")) {
    if (requireNamespace(pkg_name, quietly = TRUE)) library(pkg_name, character.only = TRUE)
  }
  library(parallel)
})

load_amp_legacy_packages <- function() {
  package_candidates <- c("EasyMicroPlot", "EasyStat", "TOmicsVis", "ggClusterNet")
  for (pkg in package_candidates) {
    if (requireNamespace(pkg, quietly = TRUE)) {
      suppressPackageStartupMessages(library(pkg, character.only = TRUE))
    }
  }

  invisible(TRUE)
}

load_amp_legacy_packages()

if (!exists("package.amp", mode = "function")) {
  package.amp <- function() invisible(TRUE)
}

if (!exists("theme_my", mode = "function")) {
  theme_my <- function(ps = NULL) {
    base_theme <- ggplot2::theme_bw() +
      ggplot2::theme(
        panel.grid = ggplot2::element_blank(),
        axis.text = ggplot2::element_text(color = "black"),
        axis.title = ggplot2::element_text(color = "black")
      )
    colors <- grDevices::hcl.colors(12, palette = "Dark 3")
    list(base_theme, base_theme, colors, colors, colors, colors)
  }
}

if (!exists("theme_nature", mode = "function")) {
  theme_nature <- function() {
    ggplot2::theme_bw() +
      ggplot2::theme(
        panel.grid = ggplot2::element_blank(),
        axis.text = ggplot2::element_text(color = "black"),
        axis.title = ggplot2::element_text(color = "black"),
        legend.key = ggplot2::element_blank()
      )
  }
}

if (!exists("alpha.micro", mode = "function")) {
  alpha.micro <- function(ps, group = "Group") {
    counts <- as(phyloseq::otu_table(ps), "matrix")
    if (phyloseq::taxa_are_rows(ps)) counts <- t(counts)
    counts <- as.matrix(counts)
    estimates <- vegan::estimateR(counts)
    richness <- rowSums(counts > 0)
    shannon <- vegan::diversity(counts, index = "shannon")
    metadata <- data.frame(phyloseq::sample_data(ps), check.names = FALSE)
    result <- data.frame(
      Shannon = shannon,
      Chao1 = as.numeric(estimates["S.chao1", rownames(counts)]),
      Inv_Simpson = vegan::diversity(counts, index = "invsimpson"),
      Richness = richness,
      ACE = as.numeric(estimates["S.ACE", rownames(counts)]),
      Pielou_evenness = ifelse(richness > 1, shannon / log(richness), 0),
      check.names = FALSE,
      row.names = rownames(counts)
    )
    if (group %in% colnames(metadata)) {
      result[[group]] <- metadata[rownames(result), group]
    }
    result
  }
}

`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0 || (length(x) == 1 && is.na(x))) y else x
}

amp_plot_font_family <- function() {
  Sys.getenv("AMPLICON_PLOT_FONT", unset = "")
}

amp_prepare_plot <- function(plot) {
  font_family <- amp_plot_font_family()
  if (inherits(plot, "ggplot") && nzchar(font_family)) {
    plot <- plot + ggplot2::theme(text = ggplot2::element_text(family = font_family))
  }
  plot
}

amp_alpha_tests <- function(data, metrics, group_col = "group", p_adjust = "BH") {
  if (!group_col %in% names(data)) stop("Alpha test data does not contain the grouping column: ", group_col)
  metrics <- intersect(as.character(metrics), names(data))
  if (!length(metrics)) stop("Alpha test data does not contain any requested metric columns.")

  rows <- list()
  add_row <- function(metric, test, contrast = NA_character_, statistic = NA_real_,
                      p_value = NA_real_, p_adjusted = NA_real_, status = "succeeded",
                      reason = NA_character_) {
    data.frame(
      metric = metric,
      test = test,
      contrast = contrast,
      statistic = as.numeric(statistic),
      p_value = as.numeric(p_value),
      p_adjust = as.numeric(p_adjusted),
      significance = if (is.finite(p_adjusted)) {
        if (p_adjusted < 0.001) "***" else if (p_adjusted < 0.01) "**" else if (p_adjusted < 0.05) "*" else "ns"
      } else {
        NA_character_
      },
      status = status,
      reason = reason,
      stringsAsFactors = FALSE
    )
  }

  for (metric in metrics) {
    values <- suppressWarnings(as.numeric(data[[metric]]))
    groups <- as.character(data[[group_col]])
    keep <- is.finite(values) & !is.na(groups) & nzchar(groups)
    test_data <- data.frame(value = values[keep], group = factor(groups[keep]))
    if (!nrow(test_data) || nlevels(test_data$group) < 2L) {
      rows[[length(rows) + 1L]] <- add_row(
        metric, "Kruskal-Wallis", status = "not_applicable",
        reason = "At least two groups with finite values are required."
      )
      next
    }

    kw <- tryCatch(stats::kruskal.test(value ~ group, data = test_data), error = identity)
    if (inherits(kw, "error")) {
      rows[[length(rows) + 1L]] <- add_row(
        metric, "Kruskal-Wallis", status = "failed", reason = conditionMessage(kw)
      )
      next
    }
    rows[[length(rows) + 1L]] <- add_row(
      metric, "Kruskal-Wallis", statistic = unname(kw$statistic), p_value = kw$p.value
    )

    pairwise <- tryCatch(
      suppressWarnings(stats::pairwise.wilcox.test(
        test_data$value, test_data$group, p.adjust.method = p_adjust, exact = FALSE
      )),
      error = identity
    )
    if (!inherits(pairwise, "error") && length(pairwise$p.value)) {
      p_matrix <- pairwise$p.value
      for (row_name in rownames(p_matrix)) {
        for (column_name in colnames(p_matrix)) {
          adjusted <- p_matrix[row_name, column_name]
          if (is.na(adjusted)) next
          rows[[length(rows) + 1L]] <- add_row(
            metric,
            paste0("pairwise Wilcoxon (", p_adjust, ")"),
            paste(row_name, "vs", column_name),
            p_adjusted = adjusted
          )
        }
      }
    }
  }

  result <- dplyr::bind_rows(rows)
  omnibus <- result$test == "Kruskal-Wallis" & is.finite(result$p_value)
  result$p_adjust[omnibus] <- stats::p.adjust(result$p_value[omnibus], method = p_adjust)
  result$significance[omnibus] <- vapply(result$p_adjust[omnibus], function(value) {
    if (value < 0.001) "***" else if (value < 0.01) "**" else if (value < 0.05) "*" else "ns"
  }, character(1))
  result
}

amp_alpha_test_labels <- function(test_table, facet_col = "index") {
  omnibus <- test_table[test_table$test == "Kruskal-Wallis" & test_table$status == "succeeded", , drop = FALSE]
  if (!nrow(omnibus)) {
    output <- data.frame(label = character(), stringsAsFactors = FALSE)
    output[[facet_col]] <- character()
    return(output[, c(facet_col, "label"), drop = FALSE])
  }
  labels <- ifelse(
    omnibus$p_adjust < 0.001,
    "Kruskal-Wallis FDR < 0.001",
    paste0("Kruskal-Wallis FDR = ", formatC(omnibus$p_adjust, format = "g", digits = 3))
  )
  output <- data.frame(label = labels, stringsAsFactors = FALSE)
  output[[facet_col]] <- omnibus$metric
  output[, c(facet_col, "label"), drop = FALSE]
}

read_amp_params <- function(param_file = "params.json") {
  normalize_amp_params <- function(params) {
    aliases <- list(
      group_col = c("group_column"),
      color_theme = c("color_palette"),
      top_n = c("comp_top_n", "biomarker_top_n", "function_top_n", "ml_top_variance_n", "beta_feature_top_n"),
      filter_top_n = c("feature_top_n", "top_n", "ml_top_variance_n", "beta_feature_top_n"),
      optimal = c("ml_top_variance_n", "biomarker_top_n", "top_n"),
      folds = c("ml_cv_folds"),
      repnum = c("ml_cv_folds"),
      p_cutoff = c("da_p_cutoff", "net_p_cutoff"),
      cor_cutoff = c("net_cor_cutoff"),
      network_method = c("net_method"),
      network_q_cutoff = c("net_q_cutoff", "p_cutoff"),
      network_pseudocount = c("net_pseudocount"),
      network_group1 = c("control_group"),
      network_group2 = c("case_group"),
      network_permutations = c("net_permutations", "permutations"),
      network_min_prevalence = c("net_min_prevalence", "min_taxa_prevalence"),
      network_min_mean_abundance = c("net_min_mean_abundance"),
      network_hub_quantile = c("net_hub_quantile"),
      network_diff_q_cutoff = c("net_diff_q_cutoff"),
      network_diff_min = c("net_diff_min"),
      distance_method = c("beta_distance_metric", "assembly_distance"),
      dist = c("comp_distance_metric", "distance_method"),
      hcluter_method = c("comp_cluster_method", "beta_cluster_method"),
      cuttree = c("comp_cutree_k", "beta_cutree_k"),
      heatnum = c("heatmap_feature_n"),
      tax_rank = c(
        "comp_tax_level", "da_tax_level", "lefse_tax_level", "net_tax_level",
        "assembly_tax_level", "ml_tax_level", "alpha_tax_level"
      ),
      tax_level = c("da_tax_level", "comp_tax_level", "lefse_tax_level"),
      fill_rank = c("net_tax_level", "comp_tax_level"),
      layout_net = c("net_layout"),
      permutations = c("beta_permutations", "assembly_null_model_runs"),
      lda_cutoff = c("lefse_lda_cutoff"),
      adjust_p = c("lefse_p_adjust", "da_p_adjust", "alpha_p_adjust"),
      lfc_cutoff = c("da_logfc_cutoff"),
      microtest_method = c("beta_stat_method"),
      pair_method = c("beta_stat_method"),
      sink_group = c("reference_group"),
      source_groups = c("comparison_pairs"),
      min_taxa_sum = c("min_total_count"),
      min_taxa_prevalence = c("min_prevalence"),
      rarefy_method = c("rarefy_depth_strategy"),
      rarefy_depth = c("rarefy_depth"),
      plot_width = c("plot_width"),
      plot_height = c("plot_height"),
      plot_dpi = c("plot_dpi")
    )

    for (target in names(aliases)) {
      if (!is.null(params[[target]]) && length(params[[target]]) > 0 && !identical(params[[target]], "")) {
        next
      }
      for (source in aliases[[target]]) {
        if (!is.null(params[[source]]) && length(params[[source]]) > 0 && !identical(params[[source]], "")) {
          params[[target]] <- params[[source]]
          break
        }
      }
    }

    if (!is.null(params$alpha_rarefy_status) && tolower(as.character(params$alpha_rarefy_status[[1]])) %in% c("false", "0", "no", "none")) {
      params$rarefy_method <- "none"
    }
    if (!is.null(params$beta_rarefy_status) && tolower(as.character(params$beta_rarefy_status[[1]])) %in% c("false", "0", "no", "none")) {
      params$rarefy_method <- "none"
    }
    if (!is.null(params$alpha_rarefy_depth_strategy)) {
      strategy <- as.character(params$alpha_rarefy_depth_strategy[[1]])
      params$rarefy_method <- switch(
        strategy,
        auto_min = "min",
        manual = "manual",
        none = "none",
        params$rarefy_method %||% "none"
      )
    }
    if (!is.null(params$rarefy_method)) {
      method <- as.character(params$rarefy_method[[1]])
      if (method %in% c("auto_recommend", "auto_q25")) params$rarefy_method <- "none"
    }
    if (!is.null(params$layout_net)) {
      layout_value <- as.character(params$layout_net[[1]])
      params$layout_net <- switch(
        layout_value,
        fr = "model_maptree2",
        kk = "model_maptree2",
        circle = "model_maptree2",
        layout_value
      )
    }

    params
  }

  if (file.exists(param_file)) {
    message("params.json status checked.")
    params <- normalize_amp_params(jsonlite::fromJSON(param_file, simplifyVector = TRUE))
  } else {
    message("params.json status checked.")
    params <- list()
  }
  options(
    amp.plot_width = param_num(params, "plot_width", NA_real_),
    amp.plot_height = param_num(params, "plot_height", NA_real_),
    amp.plot_dpi = param_int(params, "plot_dpi", 300)
  )
  params
}

param_chr <- function(params, key, default) {
  value <- params[[key]] %||% default
  as.character(value[[1]])
}

param_num <- function(params, key, default) {
  value <- suppressWarnings(as.numeric(params[[key]] %||% default))
  if (is.na(value[[1]])) default else value[[1]]
}

param_int <- function(params, key, default) {
  as.integer(param_num(params, key, default))
}

param_bool <- function(params, key, default = FALSE) {
  value <- params[[key]]
  if (is.null(value)) return(default)
  if (is.logical(value)) return(isTRUE(value[[1]]))
  tolower(as.character(value[[1]])) %in% c("1", "true", "yes", "y", "on")
}

normalize_microtest_method <- function(method, default = "adonis") {
  value <- tolower(trimws(as.character(method %||% default)))
  if (value %in% c("permanova", "adonis", "adonis2")) return("adonis")
  if (value %in% c("anosim")) return("anosim")
  if (value %in% c("mrpp")) return("MRPP")
  default
}

param_vec <- function(params, key, default = character()) {
  value <- params[[key]]
  if (is.null(value) || length(value) == 0) return(default)
  if (length(value) == 1 && grepl(",", value)) {
    return(trimws(strsplit(value, ",", fixed = TRUE)[[1]]))
  }
  as.character(value)
}

get_group_cols_robust <- function(groups, palette = c("npg", "nejm", "lancet")) {
  palette <- match.arg(palette)
  groups <- unique(as.character(groups))
  n_groups <- length(groups)
  if (n_groups == 0L) return(character())

  max_colors <- switch(palette, npg = 10, nejm = 8, lancet = 9)
  if (n_groups > max_colors) {
    if (!requireNamespace("randomcoloR", quietly = TRUE)) {
      stop("Please install the randomcoloR package.")
    }
    cols <- randomcoloR::distinctColorPalette(n_groups)
  } else {
    pal_fun <- switch(
      palette,
      npg = ggsci::pal_npg("nrc"),
      nejm = ggsci::pal_nejm(),
      lancet = ggsci::pal_lancet()
    )
    cols <- pal_fun(n_groups)
  }
  stats::setNames(cols, groups)
}

get_group_cols <- function(groups, palette = "npg") {
  get_group_cols_robust(groups, palette = palette)
}

load_amp_phyloseq <- function(params = list()) {
  group_col <- param_chr(params, "group_col", "Group")

  if (file.exists("ps.rds")) {
    ps <- readRDS("ps.rds")
  } else if (file.exists("ps_its.rds")) {
    ps <- readRDS("ps_its.rds")
  } else if (file.exists("otutab.txt") && file.exists("metadata.tsv")) {
    metadata <- read.delim("./metadata.tsv", row.names = 1, stringsAsFactors = FALSE, check.names = FALSE)
    otutab <- read.delim("./otutab.txt", row.names = 1, stringsAsFactors = FALSE, check.names = FALSE)
    ps <- phyloseq(
      sample_data(metadata),
      otu_table(as.matrix(otutab), taxa_are_rows = TRUE)
    )

    if (file.exists("taxonomy.txt")) {
      taxonomy <- read.table("./taxonomy.txt", row.names = 1, header = TRUE, stringsAsFactors = FALSE, check.names = FALSE)
      tax_table(ps) <- tax_table(as.matrix(taxonomy))
    }
    if (file.exists("otus.tree")) {
      phy_tree(ps) <- read_tree("./otus.tree")
    }
    if (file.exists("otus.fa")) {
      rep <- readDNAStringSet("./otus.fa")
      ps <- merge_phyloseq(ps, rep)
    }
    saveRDS(ps, "ps.rds")
  } else {
    stop("Input data not found. Provide ps.rds or otutab.txt plus metadata.tsv.")
  }

  meta <- as.data.frame(sample_data(ps))
  if (!group_col %in% colnames(meta)) {
    stop(sprintf("Group column not found in metadata: %s", group_col))
  }
  meta$Group <- meta[[group_col]]
  sample_data(ps) <- sample_data(meta)

  exclude_groups <- param_vec(params, "exclude_groups", character())
  exclude_groups <- exclude_groups[nzchar(exclude_groups)]
  if (length(exclude_groups) > 0) {
    keep_samples <- !(sample_data(ps)$Group %in% exclude_groups)
    ps <- prune_samples(keep_samples, ps)
    ps <- prune_taxa(taxa_sums(ps) > 0, ps)
  }

  rarefy_method <- param_chr(params, "rarefy_method", "none")
  rarefy_depth <- param_int(params, "rarefy_depth", 0)
  if (rarefy_method == "min") {
    depth <- min(sample_sums(ps))
    ps <- rarefy_even_depth(ps, sample.size = depth, rngseed = 123, replace = FALSE, trimOTUs = TRUE, verbose = FALSE)
  } else if (rarefy_method == "manual" && rarefy_depth > 0) {
    keep_samples <- sample_sums(ps) >= rarefy_depth
    ps <- prune_samples(keep_samples, ps)
    ps <- rarefy_even_depth(ps, sample.size = rarefy_depth, rngseed = 123, replace = FALSE, trimOTUs = TRUE, verbose = FALSE)
  }

  ps
}

open_amp_workbook <- function(workbook_path) {
  if (file.exists(workbook_path)) {
    openxlsx::loadWorkbook(workbook_path)
  } else {
    openxlsx::createWorkbook()
  }
}

init_amp_context <- function(params = list(), result_subdir, workbook_name) {
  ps <- load_amp_phyloseq(params)
  amplicon_path <- "."
  out_dir <- file.path(amplicon_path, result_subdir)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  workbook_path <- file.path(out_dir, workbook_name)
  workbook <- open_amp_workbook(workbook_path)

  axis_order <- sample_data(ps)$Group %>% unique()
  color_theme <- param_chr(params, "color_theme", "npg")
  if (!color_theme %in% c("npg", "nejm", "lancet")) color_theme <- "npg"
  col.g <- get_group_cols_robust(axis_order, color_theme)

  package.amp()
  theme_res <- theme_my(ps)

  list(
    ps = ps,
    params = params,
    out_dir = out_dir,
    workbook_path = workbook_path,
    workbook = workbook,
    axis_order = axis_order,
    col.g = col.g,
    mytheme1 = theme_res[[1]],
    mytheme2 = theme_res[[2]],
    colset1 = theme_res[[3]],
    colset2 = theme_res[[4]],
    colset3 = theme_res[[5]],
    colset4 = theme_res[[6]]
  )
}

save_amp_workbook <- function(ctx) {
  openxlsx::saveWorkbook(ctx$workbook, ctx$workbook_path, overwrite = TRUE)
}

save_preview_plot <- function(plot, width = 10, height = 8) {
  width <- getOption("amp.plot_width", width)
  height <- getOption("amp.plot_height", height)
  if (!is.finite(width)) width <- 10
  if (!is.finite(height)) height <- 8
  plot <- amp_prepare_plot(plot)
  save_args <- list(
    filename = "preview.png", plot = plot, device = grDevices::png,
    width = width, height = height,
    dpi = 150, limitsize = FALSE, bg = "white"
  )
  if (capabilities("cairo")) save_args$type <- "cairo-png"
  do.call(ggplot2::ggsave, save_args)
}

save_plot2 <- function(plot, out_dir, prefix, width = NULL, height = NULL, base_width = NULL, base_height = NULL, dpi = 300) {
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  width <- width %||% base_width %||% 10
  height <- height %||% base_height %||% 8
  param_width <- getOption("amp.plot_width", NA_real_)
  param_height <- getOption("amp.plot_height", NA_real_)
  param_dpi <- getOption("amp.plot_dpi", dpi)
  if (is.finite(param_width)) width <- param_width
  if (is.finite(param_height)) height <- param_height
  if (is.finite(param_dpi)) dpi <- param_dpi
  png_path <- file.path(out_dir, paste0(prefix, ".png"))
  pdf_path <- file.path(out_dir, paste0(prefix, ".pdf"))
  plot <- amp_prepare_plot(plot)
  png_args <- list(
    filename = png_path, plot = plot, device = grDevices::png,
    width = width, height = height,
    dpi = dpi, limitsize = FALSE, bg = "white"
  )
  if (capabilities("cairo")) png_args$type <- "cairo-png"
  do.call(ggplot2::ggsave, png_args)
  if (capabilities("cairo")) {
    ggplot2::ggsave(
      pdf_path, plot = plot, width = width, height = height,
      device = grDevices::cairo_pdf, limitsize = FALSE, bg = "white"
    )
  } else {
    ggplot2::ggsave(pdf_path, plot = plot, width = width, height = height, limitsize = FALSE, bg = "white")
  }
  if (!file.exists("preview.png")) {
    preview_args <- list(
      filename = "preview.png", plot = plot, device = grDevices::png,
      width = width, height = height,
      dpi = 150, limitsize = FALSE, bg = "white"
    )
    if (capabilities("cairo")) preview_args$type <- "cairo-png"
    do.call(ggplot2::ggsave, preview_args)
  }
  invisible(list(png = png_path, pdf = pdf_path))
}

write_sheet2 <- function(workbook, sheet_name, data) {
  sheet_name <- substr(gsub("[\\\\/*?:\\[\\]]", "_", sheet_name), 1, 31)
  data <- tryCatch(
    as.data.frame(data, check.names = FALSE),
    error = function(e) {
      data.frame(Output = capture.output(print(data)), stringsAsFactors = FALSE)
    }
  )
  names(data) <- make.unique(names(data), sep = "_")
  if (nrow(data) == 0 || ncol(data) == 0) {
    original_columns <- if (length(names(data))) paste(names(data), collapse = ", ") else ""
    data <- data.frame(
      status = "empty_result",
      reason = "\u5206\u6790\u5b8c\u6210\uff0c\u4f46\u5f53\u524d\u6570\u636e\u6216\u53c2\u6570\u6ca1\u6709\u4ea7\u751f\u53ef\u5c55\u793a\u7684\u8868\u683c\u884c\u3002",
      original_columns = original_columns,
      stringsAsFactors = FALSE
    )
  }
  data_rownames <- rownames(data)
  has_informative_rownames <- !is.null(data_rownames) &&
    nrow(data) > 0 &&
    !identical(data_rownames, as.character(seq_len(nrow(data)))) &&
    !any(names(data) %in% c("ID", "Id", "id", "Metric", "metric", "ASV_ID", "ASV.name", "OTU", "OTU.ID", "Feature", "feature"))
  if (has_informative_rownames) {
    data <- tibble::rownames_to_column(data, "RowName")
  }
  id_columns <- c("ASV_ID", "Sample_ID", "ID", "Id", "id", "ASV.name", "OTU", "OTU.ID", "Feature", "feature", "Metric", "metric", "Term")
  leading_id <- id_columns[id_columns %in% names(data)]
  if (length(leading_id) > 0 && names(data)[1] != leading_id[1]) {
    data <- data[, c(leading_id[1], setdiff(names(data), leading_id[1])), drop = FALSE]
  }
  existing_sheets <- tryCatch(openxlsx::sheets(workbook), error = function(e) character())
  if (sheet_name %in% existing_sheets) {
    openxlsx::removeWorksheet(workbook, sheet_name)
  }
  openxlsx::addWorksheet(workbook, sheet_name)
  openxlsx::writeData(workbook, sheet_name, data)
  invisible(workbook)
}

amp_note_table <- function(function_name, message, suggestion = "") {
  data.frame(
    function_name = function_name,
    status = "skipped_or_fallback",
    message = as.character(message),
    suggestion = as.character(suggestion),
    stringsAsFactors = FALSE
  )
}

amp_note_plot <- function(title, message) {
  ggplot2::ggplot() +
    ggplot2::annotate("text", x = 0, y = 0.08, label = title, size = 5, fontface = "bold", color = "#14324a") +
    ggplot2::annotate("text", x = 0, y = -0.08, label = message, size = 3.5, color = "#466173") +
    ggplot2::xlim(-1, 1) +
    ggplot2::ylim(-0.5, 0.5) +
    ggplot2::theme_void() +
    ggplot2::theme(plot.background = ggplot2::element_rect(fill = "white", color = NA))
}

rowCV <- function(x, na.rm = TRUE) {
  x <- as.matrix(x)
  means <- rowMeans(x, na.rm = na.rm)
  sds <- apply(x, 1, stats::sd, na.rm = na.rm)
  out <- sds / means
  out[!is.finite(out)] <- 0
  out
}

Microheatmap.micro <- function(ps_rela, id, label = TRUE, col_cluster = TRUE, row_cluster = TRUE,
                               ord.col = FALSE, scale = TRUE, axis_order.s = NULL,
                               row.lab = NULL,
                               col1 = (ggsci::pal_gsea(alpha = 1))(12),
                               col.group = NULL) {
  otu <- as.data.frame(t(ggClusterNet::vegan_otu(ps_rela)))
  keep_id <- intersect(id, rownames(otu))
  if (length(keep_id) == 0) {
    stop("Input data not found. Provide ps.rds or otutab.txt plus metadata.tsv.")
  }
  otu <- otu[keep_id, , drop = FALSE]

  if (isTRUE(scale)) {
    otu <- t(scale(t(as.matrix(otu))))
    otu[is.na(otu)] <- 0
    otu <- as.data.frame(otu)
  }

  plotdata <- otu
  plotdata$id <- rownames(plotdata)
  plotdata <- tidyr::pivot_longer(plotdata, -id, names_to = "Sample", values_to = "value")

  meta <- data.frame(phyloseq::sample_data(ps_rela), check.names = FALSE)
  meta$Sample <- rownames(meta)
  if ("Group" %in% colnames(meta)) {
    plotdata <- dplyr::left_join(plotdata, meta[, c("Sample", "Group"), drop = FALSE], by = "Sample")
    sample_order <- meta %>% dplyr::arrange(Group) %>% dplyr::pull(Sample)
  } else {
    sample_order <- colnames(otu)
  }
  if (isTRUE(ord.col) && !is.null(axis_order.s)) {
    sample_order <- axis_order.s
  }
  sample_order <- intersect(sample_order, unique(plotdata$Sample))

  feature_order <- keep_id
  if (isTRUE(row_cluster) && length(keep_id) > 1) {
    feature_order <- rownames(otu)[stats::hclust(stats::dist(as.matrix(otu)))$order]
  }
  if (isTRUE(col_cluster) && ncol(otu) > 1) {
    sample_order <- colnames(otu)[stats::hclust(stats::dist(t(as.matrix(otu))))$order]
  }

  plotdata$id <- factor(plotdata$id, levels = rev(feature_order))
  plotdata$Sample <- factor(plotdata$Sample, levels = sample_order)

  p1 <- ggplot2::ggplot(plotdata, ggplot2::aes(x = Sample, y = id, fill = value)) +
    ggplot2::geom_tile() +
    ggplot2::scale_fill_gradientn(colours = col1) +
    ggplot2::labs(x = NULL, y = NULL, fill = "Abundance") +
    ggplot2::theme_minimal() +
    ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 90, hjust = 1, vjust = 0.5))

  p2 <- ggplot2::ggplot(plotdata, ggplot2::aes(x = Sample, y = id, size = abs(value), fill = value)) +
    ggplot2::geom_point(shape = 21, alpha = 0.8) +
    ggplot2::scale_fill_gradientn(colours = col1) +
    ggplot2::labs(x = NULL, y = NULL, size = "Abundance", fill = "Abundance") +
    ggplot2::theme_minimal() +
    ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 90, hjust = 1, vjust = 0.5))

  list(p1, p2, plotdata = as.data.frame(plotdata))
}

# Self-contained exploratory machine-learning adapter. It uses stratified
# out-of-fold predictions and writes the evidence needed to audit performance.
amp_ml_analysis <- function(ctx, method, params = list()) {
  set.seed(param_int(params, "seed", 20260728))
  ps <- ctx$ps
  otu <- as(phyloseq::otu_table(ps), "matrix")
  if (phyloseq::taxa_are_rows(ps)) otu <- t(otu)
  otu <- sweep(otu, 1, pmax(rowSums(otu), 1), "/")
  y <- factor(as.character(phyloseq::sample_data(ps)$Group))
  top <- min(param_int(params, "top_n", 30), ncol(otu))
  variance <- apply(otu, 2, stats::var)
  keep <- names(sort(variance, decreasing = TRUE))[seq_len(top)]
  x <- as.data.frame(otu[, keep, drop = FALSE], check.names = FALSE)
  names(x) <- make.names(names(x), unique = TRUE)
  k <- max(2L, min(param_int(params, "folds", 5), min(table(y))))
  fold_id <- integer(length(y))
  for (level in levels(y)) {
    ids <- which(y == level)
    fold_id[ids] <- sample(rep(seq_len(k), length.out = length(ids)))
  }

  fit_model <- function(train_x, train_y) {
    switch(
      method,
      random_forest = randomForest::randomForest(x = train_x, y = train_y, importance = TRUE),
      rfcv = randomForest::randomForest(x = train_x, y = train_y, importance = TRUE),
      roc = randomForest::randomForest(x = train_x, y = train_y, importance = TRUE),
      svm = e1071::svm(x = train_x, y = train_y, probability = TRUE, scale = TRUE),
      naive_bayes = e1071::naiveBayes(x = train_x, y = train_y),
      decision_tree = rpart::rpart(train_y ~ ., data = data.frame(train_y, train_x), method = "class"),
      bagging = ipred::bagging(train_y ~ ., data = data.frame(train_y, train_x), nbagg = 50),
      nnet = nnet::nnet(x = as.matrix(train_x), y = nnet::class.ind(train_y), size = min(5, ncol(train_x)),
                        maxit = 300, trace = FALSE, decay = 0.01),
      lda = MASS::lda(x = train_x, grouping = train_y),
      lasso = glmnet::cv.glmnet(
        x = as.matrix(train_x), y = train_y,
        family = if (nlevels(train_y) == 2) "binomial" else "multinomial",
        type.measure = "class", nfolds = max(2, min(5, min(table(train_y))))
      ),
      stop("Unsupported ML method: ", method)
    )
  }
  predict_model <- function(model, new_x, levels_y, probability = FALSE) {
    if (method == "nnet") {
      raw <- predict(model, as.matrix(new_x), type = "raw")
      if (is.null(dim(raw))) raw <- cbind(1 - raw, raw)
      colnames(raw) <- levels_y
      if (probability) return(raw)
      return(factor(levels_y[max.col(raw)], levels = levels_y))
    }
    if (method == "lasso") {
      type <- if (probability) "response" else "class"
      raw <- predict(model, newx = as.matrix(new_x), s = "lambda.min", type = type)
      if (probability) return(raw)
      return(factor(as.character(drop(raw)), levels = levels_y))
    }
    if (method == "lda") {
      return(factor(as.character(predict(model, new_x)$class), levels = levels_y))
    }
    if (probability && method %in% c("random_forest", "rfcv", "roc")) {
      return(predict(model, new_x, type = "prob"))
    }
    factor(as.character(predict(model, new_x, type = "class")), levels = levels_y)
  }

  predicted <- factor(rep(NA_character_, length(y)), levels = levels(y))
  probabilities <- matrix(NA_real_, nrow = length(y), ncol = nlevels(y),
                          dimnames = list(rownames(x), levels(y)))
  for (fold in seq_len(k)) {
    train <- fold_id != fold
    test <- !train
    model <- fit_model(x[train, , drop = FALSE], droplevels(y[train]))
    predicted[test] <- predict_model(model, x[test, , drop = FALSE], levels(y))
    if (method %in% c("random_forest", "rfcv", "roc", "nnet", "lasso")) {
      prob <- tryCatch(predict_model(model, x[test, , drop = FALSE], levels(y), TRUE),
                       error = function(e) NULL)
      if (!is.null(prob)) {
        prob <- as.matrix(drop(prob))
        if (nrow(prob) == sum(test) && ncol(prob) == nlevels(y)) probabilities[test, ] <- prob
      }
    }
  }
  predictions <- data.frame(
    SampleID = phyloseq::sample_names(ps), observed = y, predicted = predicted,
    fold = fold_id, correct = y == predicted, stringsAsFactors = FALSE
  )
  predictions <- cbind(predictions, as.data.frame(probabilities, check.names = FALSE))
  confusion <- as.data.frame.matrix(table(observed = y, predicted = predicted))
  confusion <- tibble::rownames_to_column(confusion, "observed")
  metrics <- data.frame(
    method = method, folds = k, samples = length(y),
    accuracy = mean(y == predicted, na.rm = TRUE),
    balanced_accuracy = mean(vapply(levels(y), function(level) {
      mean(predicted[y == level] == level, na.rm = TRUE)
    }, numeric(1))),
    validation = "stratified out-of-fold; exploratory, not external validation",
    macro_auc = NA_real_,
    stringsAsFactors = FALSE
  )
  full_model <- fit_model(x, y)
  importance <- if (method %in% c("random_forest", "rfcv", "roc")) {
    imp <- randomForest::importance(full_model)
    data.frame(feature = rownames(imp), importance = imp[, ncol(imp)], row.names = NULL)
  } else if (method == "decision_tree") {
    data.frame(feature = names(full_model$variable.importance),
               importance = as.numeric(full_model$variable.importance), row.names = NULL)
  } else {
    base_accuracy <- mean(predict_model(full_model, x, levels(y)) == y)
    data.frame(feature = names(x), importance = vapply(names(x), function(feature) {
      shuffled <- x
      shuffled[[feature]] <- sample(shuffled[[feature]])
      base_accuracy - mean(predict_model(full_model, shuffled, levels(y)) == y)
    }, numeric(1)), row.names = NULL)
  }
  importance <- importance[order(importance$importance, decreasing = TRUE), , drop = FALSE]
  importance$importance[!is.finite(importance$importance)] <- 0
  p_conf <- ggplot2::ggplot(predictions, ggplot2::aes(observed, predicted)) +
    ggplot2::geom_bin_2d() + ggplot2::scale_fill_viridis_c() +
    ggplot2::labs(title = paste(method, "out-of-fold confusion"), fill = "samples") +
    theme_nature()
  extra_tables <- list()
  if (method == "roc") {
    roc_table <- do.call(rbind, lapply(levels(y), function(level) {
      truth <- y == level
      score <- probabilities[, level]
      thresholds <- seq(1, 0, length.out = 101)
      data.frame(
        Class = level, Threshold = thresholds,
        TPR = vapply(thresholds, function(threshold) {
          predicted_positive <- score >= threshold
          sum(predicted_positive & truth) / max(sum(truth), 1)
        }, numeric(1)),
        FPR = vapply(thresholds, function(threshold) {
          predicted_positive <- score >= threshold
          sum(predicted_positive & !truth) / max(sum(!truth), 1)
        }, numeric(1)),
        stringsAsFactors = FALSE
      )
    }))
    auc_table <- do.call(rbind, lapply(split(roc_table, roc_table$Class), function(frame) {
      frame <- frame[order(frame$FPR, frame$TPR), ]
      data.frame(
        Class = frame$Class[1],
        AUC = sum(diff(frame$FPR) * (head(frame$TPR, -1) + tail(frame$TPR, -1)) / 2),
        stringsAsFactors = FALSE
      )
    }))
    metrics$macro_auc <- mean(auc_table$AUC)
    p_conf <- ggplot2::ggplot(roc_table, ggplot2::aes(FPR, TPR, color = Class)) +
      ggplot2::geom_path(linewidth = 0.9) +
      ggplot2::geom_abline(slope = 1, intercept = 0, linetype = 2, color = "grey55") +
      ggplot2::coord_equal() +
      ggplot2::labs(title = "One-vs-rest out-of-fold ROC", x = "False positive rate",
                    y = "True positive rate") + theme_nature()
    extra_tables$roc_curve <- roc_table
    extra_tables$roc_auc <- auc_table
  } else if (method == "rfcv") {
    curve <- randomForest::rfcv(
      trainx = x, trainy = y, cv.fold = k, step = 0.75,
      scale = "log", recursive = TRUE
    )
    rfcv_table <- data.frame(
      feature_count = as.integer(names(curve$error.cv)),
      cross_validated_error = as.numeric(curve$error.cv),
      stringsAsFactors = FALSE
    )
    p_conf <- ggplot2::ggplot(rfcv_table,
                              ggplot2::aes(feature_count, cross_validated_error)) +
      ggplot2::geom_line(color = "#217a61", linewidth = 0.9) +
      ggplot2::geom_point(color = "#217a61") +
      ggplot2::scale_x_log10() +
      ggplot2::labs(title = "Random-forest recursive feature CV",
                    x = "Number of features", y = "Cross-validated error") +
      theme_nature()
    extra_tables$rfcv_curve <- rfcv_table
  }
  p_imp <- ggplot2::ggplot(head(importance, 20),
                           ggplot2::aes(stats::reorder(feature, importance), importance)) +
    ggplot2::geom_col(fill = "#147d64") + ggplot2::coord_flip() +
    ggplot2::labs(title = paste(method, "feature importance"), x = NULL) + theme_nature()
  save_plot2(p_conf, ctx$out_dir, paste0(method, "_confusion"), width = 8, height = 6)
  save_plot2(p_imp, ctx$out_dir, paste0(method, "_importance"), width = 9, height = 7)
  amp_save_table(ctx, paste0(method, "_metrics"), metrics, paste0(method, "_metrics.csv"))
  amp_save_table(ctx, paste0(method, "_predictions"), predictions, paste0(method, "_predictions.csv"))
  amp_save_table(ctx, paste0(method, "_confusion"), confusion, paste0(method, "_confusion.csv"))
  amp_save_table(ctx, paste0(method, "_importance"), importance, paste0(method, "_importance.csv"))
  for (table_name in names(extra_tables)) {
    amp_save_table(ctx, table_name, extra_tables[[table_name]], paste0(table_name, ".csv"))
  }
  save_amp_workbook(ctx)
  invisible(list(metrics = metrics, predictions = predictions, importance = importance))
}

amp_sample_matrix <- function(ps, relative = FALSE) {
  x <- as(phyloseq::otu_table(ps), "matrix")
  if (phyloseq::taxa_are_rows(ps)) x <- t(x)
  storage.mode(x) <- "double"
  if (relative) x <- sweep(x, 1, pmax(rowSums(x), 1), "/")
  x
}

amp_tax_rank <- function(ps, requested = "Genus") {
  ranks <- phyloseq::rank_names(ps)
  if (requested %in% ranks) return(requested)
  preferred <- c("Species", "Genus", "Family", "Order", "Class", "Phylum", "Kingdom")
  available <- preferred[preferred %in% ranks]
  if (!length(available)) stop("No usable taxonomy rank is available.")
  available[[1]]
}

amp_aggregate_taxa <- function(ps, rank = "Genus", relative = FALSE) {
  rank <- amp_tax_rank(ps, rank)
  x <- amp_sample_matrix(ps, relative = FALSE)
  tax <- as.data.frame(phyloseq::tax_table(ps), stringsAsFactors = FALSE)
  labels <- as.character(tax[colnames(x), rank])
  labels[is.na(labels) | !nzchar(labels)] <- "Unassigned"
  aggregated <- rowsum(t(x), group = labels, reorder = FALSE)
  out <- t(aggregated)
  if (relative) out <- sweep(out, 1, pmax(rowSums(out), 1), "/")
  out
}

amp_save_table <- function(ctx, sheet, data, csv_name = NULL) {
  write_sheet2(ctx$workbook, sheet, data)
  if (!is.null(csv_name)) {
    utils::write.csv(data, file.path(ctx$out_dir, csv_name), row.names = FALSE)
  }
}

amp_require_package <- function(package, method_name = package) {
  if (!requireNamespace(package, quietly = TRUE)) {
    stop("分析方法 ", method_name, " 需要已安装的R包：", package)
  }
  invisible(as.character(utils::packageVersion(package)))
}

amp_package_method_table <- function(package, method, extra = list()) {
  version <- amp_require_package(package, method)
  base <- list(
    backend_package = package,
    package_version = version,
    method = method,
    executed_by = "amplicon-analysis-agent"
  )
  as.data.frame(c(base, extra), stringsAsFactors = FALSE, check.names = FALSE)
}

amp_result_barplot <- function(result, effect_column, q_column, title, top_n = 25) {
  result <- as.data.frame(result, check.names = FALSE)
  if (!all(c("feature", effect_column, q_column) %in% names(result))) {
    return(amp_note_plot(title, "结果表缺少可绘制的feature、effect或q值列。"))
  }
  result[[effect_column]] <- suppressWarnings(as.numeric(result[[effect_column]]))
  result[[q_column]] <- suppressWarnings(as.numeric(result[[q_column]]))
  result <- result[is.finite(result[[effect_column]]), , drop = FALSE]
  if (!nrow(result)) return(amp_note_plot(title, "当前数据没有产生可绘制的有限效应量。"))
  result <- result[order(result[[q_column]], -abs(result[[effect_column]]), na.last = TRUE), , drop = FALSE]
  result <- head(result, top_n)
  result$significant <- is.finite(result[[q_column]]) & result[[q_column]] <= 0.05
  ggplot2::ggplot(
    result,
    ggplot2::aes(x = .data[[effect_column]], y = stats::reorder(.data$feature, .data[[effect_column]]),
                 color = .data$significant)
  ) +
    ggplot2::geom_point(size = 2.6) +
    ggplot2::geom_vline(xintercept = 0, linetype = 2, color = "grey55") +
    ggplot2::scale_color_manual(values = c("FALSE" = "grey65", "TRUE" = "#c13a35")) +
    ggplot2::labs(title = title, x = effect_column, y = NULL, color = "q <= 0.05") +
    theme_nature()
}

amp_group_contrast <- function(ctx, params = list(), minimum_per_group = 3) {
  metadata <- data.frame(phyloseq::sample_data(ctx$ps), check.names = FALSE)
  groups <- unique(as.character(metadata$Group))
  reference <- param_chr(params, "reference_group", param_chr(params, "control_group", ""))
  comparison <- param_chr(params, "comparison_group", param_chr(params, "case_group", ""))
  if (!nzchar(reference) || !nzchar(comparison)) {
    if (length(groups) != 2) {
      stop("数据包含两个以上分组时，必须指定reference_group和comparison_group。")
    }
    reference <- groups[[1]]
    comparison <- groups[[2]]
  }
  if (!all(c(reference, comparison) %in% groups) || identical(reference, comparison)) {
    stop("reference_group和comparison_group必须是数据中两个不同的实际分组。")
  }
  keep <- as.character(metadata$Group) %in% c(reference, comparison)
  selected <- metadata[keep, , drop = FALSE]
  counts <- table(as.character(selected$Group))
  if (min(counts[c(reference, comparison)]) < minimum_per_group) {
    stop("该方法要求所选每组至少", minimum_per_group, "个独立样本。")
  }
  list(
    metadata = selected,
    sample_ids = rownames(selected),
    reference = reference,
    comparison = comparison,
    group = factor(as.character(selected$Group), levels = c(reference, comparison))
  )
}

amp_rank_contrast_data <- function(ctx, params = list(), minimum_per_group = 3,
                                   relative = FALSE) {
  contrast <- amp_group_contrast(ctx, params, minimum_per_group)
  rank <- amp_tax_rank(ctx$ps, param_chr(params, "tax_rank", "Genus"))
  matrix <- amp_aggregate_taxa(ctx$ps, rank, relative = relative)
  matrix <- matrix[contrast$sample_ids, , drop = FALSE]
  list(
    matrix = matrix,
    metadata = contrast$metadata,
    group = contrast$group,
    reference = contrast$reference,
    comparison = contrast$comparison,
    rank = rank
  )
}

amp_rank_phyloseq <- function(data) {
  counts <- round(data$matrix)
  taxonomy <- matrix(colnames(counts), ncol = 1,
                     dimnames = list(colnames(counts), data$rank))
  metadata <- data$metadata
  metadata$Group <- data$group
  phyloseq::phyloseq(
    phyloseq::otu_table(t(counts), taxa_are_rows = TRUE),
    phyloseq::tax_table(taxonomy),
    phyloseq::sample_data(metadata)
  )
}

amp_save_package_result <- function(ctx, package, method, result, effect_column,
                                    q_column, prefix, extra = list()) {
  method_table <- amp_package_method_table(package, method, extra)
  plot <- amp_result_barplot(
    result, effect_column, q_column,
    paste0(method, "：主要结果"), param_int(ctx$params, "top_n", 25)
  )
  save_plot2(plot, ctx$out_dir, paste0(prefix, "_results"), width = 9, height = 8)
  amp_save_table(ctx, paste0(prefix, "_method"), method_table, paste0(prefix, "_method.csv"))
  amp_save_table(ctx, paste0(prefix, "_results"), result, paste0(prefix, "_results.csv"))
  save_amp_workbook(ctx)
  invisible(result)
}

amp_beta_native <- function(ctx, variant = "ordination", params = list()) {
  x <- amp_sample_matrix(ctx$ps, relative = TRUE)
  meta <- data.frame(phyloseq::sample_data(ctx$ps), check.names = FALSE)
  meta$SampleID <- rownames(meta)
  meta$Group <- factor(meta$Group)
  distance_method <- param_chr(params, "distance_method", "bray")
  d <- vegan::vegdist(x, method = distance_method)
  coords <- stats::cmdscale(d, k = 2, eig = TRUE, add = TRUE)
  points <- data.frame(
    SampleID = rownames(coords$points), Axis1 = coords$points[, 1],
    Axis2 = coords$points[, 2], stringsAsFactors = FALSE
  )
  points <- merge(points, meta[, c("SampleID", "Group"), drop = FALSE], by = "SampleID")
  variance <- pmax(coords$eig, 0) / sum(pmax(coords$eig, 0))
  p_ord <- ggplot2::ggplot(points, ggplot2::aes(Axis1, Axis2, color = Group)) +
    ggplot2::geom_point(size = 3, alpha = 0.85) +
    ggplot2::stat_ellipse(ggplot2::aes(group = Group), linewidth = 0.6,
                         type = "norm", level = 0.68, show.legend = FALSE) +
    ggplot2::labs(
      title = paste("PCoA -", distance_method),
      x = sprintf("Axis 1 (%.1f%%)", 100 * variance[1]),
      y = sprintf("Axis 2 (%.1f%%)", 100 * variance[2])
    ) + theme_nature()
  save_plot2(p_ord, ctx$out_dir, paste0(variant, "_ordination"), width = 9, height = 7)

  permutations <- param_int(params, "permutations", 999)
  adonis <- vegan::adonis2(d ~ Group, data = meta, permutations = permutations)
  dispersion <- vegan::betadisper(d, meta$Group)
  dispersion_test <- vegan::permutest(dispersion, permutations = permutations)
  tests <- data.frame(
    test = c("PERMANOVA", "PERMDISP"),
    statistic = c(adonis$F[1], dispersion_test$tab$F[1]),
    R2 = c(adonis$R2[1], NA_real_),
    p_value = c(adonis$`Pr(>F)`[1], dispersion_test$tab$`Pr(>F)`[1]),
    permutations = permutations,
    stringsAsFactors = FALSE
  )
  amp_save_table(ctx, paste0(variant, "_coordinates"), points, paste0(variant, "_coordinates.csv"))
  amp_save_table(ctx, paste0(variant, "_tests"), tests, paste0(variant, "_tests.csv"))

  if (variant %in% c("distance", "cluster")) {
    dm <- as.matrix(d)
    order_ids <- rownames(dm)[stats::hclust(d)$order]
    long <- as.data.frame(as.table(dm), stringsAsFactors = FALSE)
    names(long) <- c("Sample1", "Sample2", "Distance")
    long$Sample1 <- factor(long$Sample1, levels = order_ids)
    long$Sample2 <- factor(long$Sample2, levels = rev(order_ids))
    p_heat <- ggplot2::ggplot(long, ggplot2::aes(Sample1, Sample2, fill = Distance)) +
      ggplot2::geom_tile() + ggplot2::scale_fill_viridis_c() +
      ggplot2::theme_minimal() +
      ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 90, hjust = 1)) +
      ggplot2::labs(title = paste("Sample", distance_method, "distance"), x = NULL, y = NULL)
    save_plot2(p_heat, ctx$out_dir, paste0(variant, "_distance_heatmap"), width = 10, height = 9)
    amp_save_table(ctx, paste0(variant, "_distance"), long, paste0(variant, "_distance.csv"))
    if (variant == "cluster") {
      hc <- stats::hclust(d)
      cluster_count <- min(param_int(params, "cuttree", 3), length(unique(meta$Group)))
      membership <- data.frame(
        SampleID = names(stats::cutree(hc, k = cluster_count)),
        Cluster = as.integer(stats::cutree(hc, k = cluster_count)),
        stringsAsFactors = FALSE
      )
      amp_save_table(ctx, "cluster_membership", membership, "cluster_membership.csv")
      png_path <- file.path(ctx$out_dir, "cluster_dendrogram.png")
      pdf_path <- file.path(ctx$out_dir, "cluster_dendrogram.pdf")
      grDevices::png(png_path, width = 2400, height = 1600, res = 240)
      graphics::plot(hc, main = paste(distance_method, "hierarchical clustering"), xlab = "", sub = "")
      grDevices::dev.off()
      grDevices::pdf(pdf_path, width = 10, height = 7)
      graphics::plot(hc, main = paste(distance_method, "hierarchical clustering"), xlab = "", sub = "")
      grDevices::dev.off()
    }
  }
  save_amp_workbook(ctx)
  invisible(list(points = points, tests = tests))
}

amp_pairwise_beta_native <- function(ctx, params = list()) {
  x <- amp_sample_matrix(ctx$ps, relative = TRUE)
  meta <- data.frame(phyloseq::sample_data(ctx$ps), check.names = FALSE)
  meta$Group <- factor(meta$Group)
  groups <- levels(meta$Group)
  pairs <- utils::combn(groups, 2, simplify = FALSE)
  rows <- lapply(pairs, function(pair) {
    keep <- meta$Group %in% pair
    sub_meta <- droplevels(meta[keep, , drop = FALSE])
    sub_d <- vegan::vegdist(x[keep, , drop = FALSE], method = param_chr(params, "distance_method", "bray"))
    fit <- vegan::adonis2(sub_d ~ Group, data = sub_meta,
                          permutations = param_int(params, "permutations", 999))
    disp <- vegan::permutest(vegan::betadisper(sub_d, sub_meta$Group),
                             permutations = param_int(params, "permutations", 999))
    data.frame(
      group1 = pair[1], group2 = pair[2], R2 = fit$R2[1], F = fit$F[1],
      permanova_p = fit$`Pr(>F)`[1], dispersion_F = disp$tab$F[1],
      dispersion_p = disp$tab$`Pr(>F)`[1], stringsAsFactors = FALSE
    )
  })
  result <- do.call(rbind, rows)
  result$FDR <- stats::p.adjust(result$permanova_p, method = "BH")
  p <- ggplot2::ggplot(result, ggplot2::aes(paste(group1, group2, sep = " vs "), R2,
                                            fill = FDR < 0.05)) +
    ggplot2::geom_col(show.legend = FALSE) + ggplot2::coord_flip() +
    ggplot2::labs(title = "Pairwise PERMANOVA effect sizes", x = NULL, y = "R2") +
    theme_nature()
  save_plot2(p, ctx$out_dir, "pairwise_permanova", width = 8, height = 6)
  amp_save_table(ctx, "pairwise_permanova", result, "pairwise_permanova.csv")
  save_amp_workbook(ctx)
  invisible(result)
}

amp_pca_native <- function(ctx, params = list()) {
  x <- amp_sample_matrix(ctx$ps, relative = TRUE)
  x <- log1p(x * 1e6)
  fit <- stats::prcomp(x, center = TRUE, scale. = TRUE)
  explained <- fit$sdev^2 / sum(fit$sdev^2)
  scores <- data.frame(
    SampleID = rownames(fit$x), PC1 = fit$x[, 1], PC2 = fit$x[, 2],
    stringsAsFactors = FALSE
  )
  meta <- data.frame(phyloseq::sample_data(ctx$ps), check.names = FALSE)
  scores$Group <- meta[scores$SampleID, "Group"]
  p <- ggplot2::ggplot(scores, ggplot2::aes(PC1, PC2, color = Group)) +
    ggplot2::geom_point(size = 3, alpha = 0.85) +
    ggplot2::stat_ellipse(level = 0.68, type = "norm", show.legend = FALSE) +
    ggplot2::labs(
      title = "PCA of log relative abundance",
      x = sprintf("PC1 (%.1f%%)", explained[1] * 100),
      y = sprintf("PC2 (%.1f%%)", explained[2] * 100)
    ) + theme_nature()
  save_plot2(p, ctx$out_dir, "PCA_scores", width = 9, height = 7)
  amp_save_table(ctx, "PCA_scores", scores, "PCA_scores.csv")
  amp_save_table(
    ctx, "PCA_loadings",
    data.frame(Feature = rownames(fit$rotation), fit$rotation, check.names = FALSE),
    "PCA_loadings.csv"
  )
  save_amp_workbook(ctx)
  invisible(scores)
}

amp_mantel_native <- function(ctx, params = list()) {
  x <- amp_sample_matrix(ctx$ps, relative = TRUE)
  meta <- data.frame(phyloseq::sample_data(ctx$ps), check.names = FALSE)
  community <- vegan::vegdist(x, method = param_chr(params, "distance_method", "bray"))
  design <- stats::model.matrix(~ Group, data = meta)[, -1, drop = FALSE]
  if (!ncol(design)) stop("Mantel group-design distance requires at least two groups.")
  environment <- stats::dist(design)
  result <- vegan::mantel(
    community, environment,
    method = param_chr(params, "beta_mantel_method", "spearman"),
    permutations = param_int(params, "permutations", 999)
  )
  pair <- which(upper.tri(as.matrix(community)), arr.ind = TRUE)
  plot_data <- data.frame(
    CommunityDistance = as.matrix(community)[pair],
    DesignDistance = as.matrix(environment)[pair]
  )
  p <- ggplot2::ggplot(plot_data, ggplot2::aes(DesignDistance, CommunityDistance)) +
    ggplot2::geom_jitter(width = 0.03, alpha = 0.45, color = "#217a61") +
    ggplot2::geom_smooth(method = "lm", se = TRUE, color = "#b5453c") +
    ggplot2::labs(
      title = sprintf("Mantel r = %.3f, p = %.4g", result$statistic, result$signif),
      x = "Experimental-design distance", y = "Community distance"
    ) + theme_nature()
  table <- data.frame(
    method = result$method, statistic = unname(result$statistic),
    p_value = result$signif, permutations = result$permutations,
    stringsAsFactors = FALSE
  )
  save_plot2(p, ctx$out_dir, "mantel_test", width = 9, height = 7)
  amp_save_table(ctx, "mantel_test", table, "mantel_test.csv")
  amp_save_table(ctx, "mantel_pairs", plot_data, "mantel_pairs.csv")
  save_amp_workbook(ctx)
  invisible(table)
}

amp_alpha_rarefaction_native <- function(ctx, params = list()) {
  x <- amp_sample_matrix(ctx$ps, relative = FALSE)
  steps <- unique(round(seq(1, min(rowSums(x)), length.out = 30)))
  rows <- do.call(rbind, lapply(seq_len(nrow(x)), function(i) {
    richness <- vegan::rarefy(x[i, ], sample = steps)
    data.frame(SampleID = rownames(x)[i], Depth = steps, Richness = as.numeric(richness))
  }))
  meta <- data.frame(phyloseq::sample_data(ctx$ps), check.names = FALSE)
  rows$Group <- meta[rows$SampleID, "Group"]
  p1 <- ggplot2::ggplot(rows, ggplot2::aes(Depth, Richness, group = SampleID, color = Group)) +
    ggplot2::geom_line(alpha = 0.6) + theme_nature() +
    ggplot2::labs(title = "Rarefaction curves")
  summary <- rows |>
    dplyr::group_by(Group, Depth) |>
    dplyr::summarise(mean_richness = mean(Richness), se = stats::sd(Richness) / sqrt(dplyr::n()),
                     .groups = "drop")
  p2 <- ggplot2::ggplot(summary, ggplot2::aes(Depth, mean_richness, color = Group, fill = Group)) +
    ggplot2::geom_line(linewidth = 0.8) +
    ggplot2::geom_ribbon(ggplot2::aes(ymin = mean_richness - se, ymax = mean_richness + se),
                         alpha = 0.16, color = NA) + theme_nature() +
    ggplot2::labs(title = "Group mean rarefaction")
  save_plot2(p1, ctx$out_dir, "rarefaction_samples", width = 9, height = 7)
  save_plot2(p2, ctx$out_dir, "rarefaction_groups", width = 9, height = 7)
  amp_save_table(ctx, "rarefaction", rows, "rarefaction.csv")
  save_amp_workbook(ctx)
  invisible(rows)
}

amp_composition_native <- function(ctx, variant = "bar", params = list()) {
  rank <- amp_tax_rank(ctx$ps, param_chr(params, "tax_rank", param_chr(params, "comp_tax_level", "Genus")))
  rel <- amp_aggregate_taxa(ctx$ps, rank, relative = TRUE)
  meta <- data.frame(phyloseq::sample_data(ctx$ps), check.names = FALSE)
  meta$SampleID <- rownames(meta)
  top_n <- min(param_int(params, "top_n", 10), ncol(rel))
  keep <- names(sort(colMeans(rel), decreasing = TRUE))[seq_len(top_n)]
  plot_matrix <- rel[, keep, drop = FALSE]
  other <- pmax(0, 1 - rowSums(plot_matrix))
  plot_matrix <- cbind(plot_matrix, Other = other)
  long <- as.data.frame(plot_matrix, check.names = FALSE)
  long$SampleID <- rownames(long)
  long <- tidyr::pivot_longer(long, -SampleID, names_to = "Taxon", values_to = "RelativeAbundance")
  long <- dplyr::left_join(long, meta[, c("SampleID", "Group"), drop = FALSE], by = "SampleID")
  group_mean <- long |>
    dplyr::group_by(Group, Taxon) |>
    dplyr::summarise(RelativeAbundance = mean(RelativeAbundance), .groups = "drop")

  if (variant %in% c("cir_barplot", "cir_plot")) {
    p <- ggplot2::ggplot(group_mean, ggplot2::aes(Group, RelativeAbundance, fill = Taxon)) +
      ggplot2::geom_col(width = 1) + ggplot2::coord_polar() +
      ggplot2::labs(title = paste(rank, "circular composition"), x = NULL, y = NULL) +
      ggplot2::theme_void()
  } else if (variant %in% c("sankey", "sankey_group") && requireNamespace("ggalluvial", quietly = TRUE)) {
    p <- ggplot2::ggplot(group_mean,
                         ggplot2::aes(axis1 = Group, axis2 = Taxon, y = RelativeAbundance)) +
      ggalluvial::geom_alluvium(ggplot2::aes(fill = Taxon), width = 0.16, alpha = 0.8) +
      ggalluvial::geom_stratum(width = 0.16, fill = "grey92", color = "grey45") +
      ggalluvial::stat_stratum(
        geom = "text", ggplot2::aes(label = ggplot2::after_stat(stratum)), size = 3
      ) +
      ggplot2::scale_x_discrete(limits = c("Group", rank), expand = c(0.05, 0.05)) +
      ggplot2::labs(title = paste("Group-to-", rank, "alluvial"), y = "Mean relative abundance") +
      theme_nature()
  } else if (variant %in% c("venn", "upset", "venn_detail")) {
    presence <- rel > param_num(params, "presence_threshold", 0)
    pattern <- apply(presence, 2, function(values) {
      paste(sort(unique(as.character(meta$Group[values]))), collapse = " & ")
    })
    intersections <- as.data.frame(table(pattern), stringsAsFactors = FALSE)
    names(intersections) <- c("Intersection", "FeatureCount")
    intersections <- intersections[nzchar(intersections$Intersection), , drop = FALSE]
    p <- ggplot2::ggplot(intersections, ggplot2::aes(stats::reorder(Intersection, FeatureCount), FeatureCount)) +
      ggplot2::geom_col(fill = "#217a61") + ggplot2::coord_flip() +
      ggplot2::labs(title = "Feature-presence intersections", x = NULL) + theme_nature()
    amp_save_table(ctx, paste0(variant, "_intersections"), intersections,
                   paste0(variant, "_intersections.csv"))
  } else if (variant %in% c("ven_network", "maptree")) {
    edges <- group_mean[group_mean$Taxon != "Other" & group_mean$RelativeAbundance > 0, ]
    p <- ggplot2::ggplot(edges, ggplot2::aes(Group, Taxon, size = RelativeAbundance,
                                             color = RelativeAbundance)) +
      ggplot2::geom_point(alpha = 0.85) + ggplot2::scale_color_viridis_c() +
      ggplot2::labs(title = paste("Group-", rank, "association map"), x = NULL, y = NULL) +
      theme_nature()
    amp_save_table(ctx, paste0(variant, "_edges"), edges, paste0(variant, "_edges.csv"))
  } else {
    p <- ggplot2::ggplot(group_mean, ggplot2::aes(Group, RelativeAbundance, fill = Taxon)) +
      ggplot2::geom_col() + ggplot2::labs(title = paste(rank, "group composition"),
                                          x = NULL, y = "Mean relative abundance") +
      theme_nature()
  }
  save_plot2(p, ctx$out_dir, variant, width = 10, height = 8)
  amp_save_table(ctx, paste0(variant, "_sample"), long, paste0(variant, "_sample.csv"))
  amp_save_table(ctx, paste0(variant, "_group"), group_mean, paste0(variant, "_group.csv"))
  save_amp_workbook(ctx)
  invisible(list(sample = long, group = group_mean))
}

amp_differential_native <- function(ctx, variant = "volcano", params = list(), rank = NULL) {
  rank <- rank %||% param_chr(params, "tax_level", param_chr(params, "tax_rank", "Genus"))
  rank <- amp_tax_rank(ctx$ps, rank)
  counts <- amp_aggregate_taxa(ctx$ps, rank, relative = FALSE)
  meta <- data.frame(phyloseq::sample_data(ctx$ps), check.names = FALSE)
  groups <- unique(as.character(meta$Group))
  control <- param_chr(params, "control_group", groups[1])
  case <- param_chr(params, "case_group", groups[min(2, length(groups))])
  if (!all(c(control, case) %in% groups)) stop("Requested contrast groups were not found.")
  keep <- meta$Group %in% c(control, case)
  x <- counts[keep, , drop = FALSE]
  g <- factor(meta$Group[keep], levels = c(control, case))
  relative <- sweep(x, 1, pmax(rowSums(x), 1), "/")
  result <- do.call(rbind, lapply(seq_len(ncol(x)), function(j) {
    a <- relative[g == control, j]
    b <- relative[g == case, j]
    test <- suppressWarnings(stats::wilcox.test(b, a, exact = FALSE))
    data.frame(
      Feature = colnames(x)[j], Control = control, Case = case,
      mean_control = mean(a), mean_case = mean(b),
      log2FC = log2((mean(b) + 1e-8) / (mean(a) + 1e-8)),
      p_value = test$p.value, stringsAsFactors = FALSE
    )
  }))
  result$FDR <- stats::p.adjust(result$p_value, method = "BH")
  result$significant <- result$FDR < param_num(params, "p_cutoff", 0.05) &
    abs(result$log2FC) >= param_num(params, "lfc_cutoff", 1)
  result <- result[order(result$FDR), , drop = FALSE]
  if (variant == "function_bubble") {
    top <- head(result, param_int(params, "top_n", 20))
    p <- ggplot2::ggplot(
      top,
      ggplot2::aes(log2FC, stats::reorder(Feature, log2FC),
                   size = -log10(pmax(FDR, 1e-300)), color = log2FC)
    ) +
      ggplot2::geom_point(alpha = 0.85) +
      ggplot2::scale_color_gradient2(low = "#3465a4", mid = "grey90", high = "#c13a35",
                                     midpoint = 0) +
      ggplot2::labs(title = paste(case, "vs", control, rank, "bubble"),
                    x = "log2 fold change", y = NULL, size = "-log10(FDR)") +
      theme_nature()
  } else if (variant == "manhattan") {
    result$Index <- seq_len(nrow(result))
    p <- ggplot2::ggplot(result, ggplot2::aes(Index, -log10(pmax(FDR, 1e-300)),
                                              color = log2FC > 0)) +
      ggplot2::geom_point(size = 2) + ggplot2::geom_hline(yintercept = -log10(0.05), linetype = 2) +
      ggplot2::labs(title = paste(case, "vs", control, rank, "Manhattan view"),
                    y = "-log10(FDR)") + theme_nature()
  } else if (variant == "stamp") {
    top <- head(result, param_int(params, "top_n", 20))
    p <- ggplot2::ggplot(top, ggplot2::aes(stats::reorder(Feature, mean_case - mean_control),
                                           mean_case - mean_control,
                                           fill = significant)) +
      ggplot2::geom_col(show.legend = FALSE) + ggplot2::coord_flip() +
      ggplot2::labs(title = paste(case, "-", control, "mean abundance difference"),
                    x = NULL, y = "Difference") + theme_nature()
  } else {
    p <- ggplot2::ggplot(result, ggplot2::aes(log2FC, -log10(pmax(FDR, 1e-300)),
                                              color = significant)) +
      ggplot2::geom_point(alpha = 0.8) +
      ggplot2::scale_color_manual(values = c("FALSE" = "grey70", "TRUE" = "#c43c39")) +
      ggplot2::geom_vline(xintercept = c(-1, 1), linetype = 2) +
      ggplot2::geom_hline(yintercept = -log10(0.05), linetype = 2) +
      ggplot2::labs(title = paste(case, "vs", control, rank, variant), color = "FDR & FC") +
      theme_nature()
  }
  save_plot2(p, ctx$out_dir, paste0(variant, "_", rank), width = 9, height = 7)
  amp_save_table(ctx, paste0(variant, "_", rank), result, paste0(variant, "_", rank, ".csv"))
  save_amp_workbook(ctx)
  invisible(result)
}

amp_edger_native <- function(ctx, variant = "edger", params = list(), rank = "Genus") {
  if (!requireNamespace("edgeR", quietly = TRUE)) stop("The edgeR package is required.")
  rank <- amp_tax_rank(ctx$ps, rank)
  counts <- amp_aggregate_taxa(ctx$ps, rank, relative = FALSE)
  meta <- data.frame(phyloseq::sample_data(ctx$ps), check.names = FALSE)
  groups <- unique(as.character(meta$Group))
  control <- param_chr(params, "control_group", groups[1])
  case <- param_chr(params, "case_group", groups[min(2, length(groups))])
  keep <- meta$Group %in% c(control, case)
  group <- factor(meta$Group[keep], levels = c(control, case))
  y <- edgeR::DGEList(counts = t(round(counts[keep, , drop = FALSE])), group = group)
  retained <- edgeR::filterByExpr(y, group = group)
  if (sum(retained) < 2) stop("Too few features passed edgeR filtering.")
  y <- edgeR::calcNormFactors(y[retained, , keep.lib.sizes = FALSE])
  design <- stats::model.matrix(~ group)
  y <- edgeR::estimateDisp(y, design, robust = TRUE)
  fit <- edgeR::glmQLFit(y, design, robust = TRUE)
  test <- edgeR::glmQLFTest(fit, coef = 2)
  result <- edgeR::topTags(test, n = Inf, sort.by = "PValue")$table
  result <- tibble::rownames_to_column(as.data.frame(result), "Feature")
  result$Control <- control
  result$Case <- case
  result$significant <- result$FDR < param_num(params, "p_cutoff", 0.05) &
    abs(result$logFC) >= param_num(params, "lfc_cutoff", 1)
  if (variant == "manhattan") {
    result$Index <- seq_len(nrow(result))
    p <- ggplot2::ggplot(result, ggplot2::aes(Index, -log10(pmax(FDR, 1e-300)),
                                              color = logFC > 0)) +
      ggplot2::geom_point(size = 2) + ggplot2::geom_hline(yintercept = -log10(0.05), linetype = 2) +
      ggplot2::labs(title = paste("edgeR", case, "vs", control), y = "-log10(FDR)") +
      theme_nature()
  } else {
    p <- ggplot2::ggplot(result, ggplot2::aes(logFC, -log10(pmax(FDR, 1e-300)),
                                              color = significant)) +
      ggplot2::geom_point(alpha = 0.8) +
      ggplot2::scale_color_manual(values = c("FALSE" = "grey70", "TRUE" = "#c43c39")) +
      ggplot2::geom_vline(xintercept = c(-1, 1), linetype = 2) +
      ggplot2::geom_hline(yintercept = -log10(0.05), linetype = 2) +
      ggplot2::labs(title = paste("edgeR", case, "vs", control, rank), color = "FDR & FC") +
      theme_nature()
  }
  save_plot2(p, ctx$out_dir, paste0(variant, "_", rank), width = 9, height = 7)
  amp_save_table(ctx, paste0(variant, "_", rank), result, paste0(variant, "_", rank, ".csv"))
  save_amp_workbook(ctx)
  invisible(result)
}

amp_kegg_enrichment_native <- function(ctx, params = list()) {
  ranks <- phyloseq::rank_names(ctx$ps)
  if (!all(c("KO", "Pathway") %in% ranks)) {
    stop("KO and Pathway annotation columns are required for offline enrichment.")
  }
  differential <- amp_differential_native(ctx, "function_diff", params, rank = "KO")
  tax <- as.data.frame(phyloseq::tax_table(ctx$ps), stringsAsFactors = FALSE)
  mapping <- unique(tax[, c("KO", "Pathway"), drop = FALSE])
  mapping <- mapping[!is.na(mapping$KO) & !is.na(mapping$Pathway), , drop = FALSE]
  selected <- differential$Feature[differential$FDR < 0.1]
  if (length(selected) < 2) selected <- head(differential$Feature, min(10, nrow(differential)))
  universe <- unique(mapping$KO)
  rows <- lapply(unique(mapping$Pathway), function(pathway) {
    members <- unique(mapping$KO[mapping$Pathway == pathway])
    a <- length(intersect(selected, members))
    b <- length(setdiff(selected, members))
    c <- length(setdiff(members, selected))
    d <- length(setdiff(universe, union(selected, members)))
    test <- stats::fisher.test(matrix(c(a, b, c, d), nrow = 2))
    data.frame(
      Pathway = pathway, selected_hits = a, pathway_size = length(members),
      gene_ratio = a / max(length(selected), 1), p_value = test$p.value,
      stringsAsFactors = FALSE
    )
  })
  result <- do.call(rbind, rows)
  result$FDR <- stats::p.adjust(result$p_value, "BH")
  result <- result[order(result$FDR), , drop = FALSE]
  p <- ggplot2::ggplot(head(result, 20),
                       ggplot2::aes(gene_ratio, stats::reorder(Pathway, gene_ratio),
                                    size = selected_hits, color = -log10(pmax(FDR, 1e-300)))) +
    ggplot2::geom_point() + ggplot2::scale_color_viridis_c() +
    ggplot2::labs(title = "Offline KO pathway over-representation", y = NULL,
                  color = "-log10(FDR)") + theme_nature()
  save_plot2(p, ctx$out_dir, "KO_pathway_enrichment", width = 10, height = 8)
  amp_save_table(ctx, "KO_enrichment", result, "KO_pathway_enrichment.csv")
  save_amp_workbook(ctx)
  invisible(result)
}

amp_network_native <- function(ctx, variant = "network", params = list()) {
  x <- amp_sample_matrix(ctx$ps, relative = TRUE)
  top <- min(param_int(params, "top_n", 40), ncol(x))
  keep <- names(sort(colMeans(x), decreasing = TRUE))[seq_len(top)]
  x <- x[, keep, drop = FALSE]
  cor_mat <- stats::cor(x, method = "spearman")
  n <- nrow(x)
  t_stat <- cor_mat * sqrt(pmax(n - 2, 1) / pmax(1 - cor_mat^2, 1e-12))
  p_mat <- 2 * stats::pt(-abs(t_stat), df = pmax(n - 2, 1))
  idx <- which(upper.tri(cor_mat) &
                 abs(cor_mat) >= param_num(params, "cor_cutoff", 0.6) &
                 p_mat <= param_num(params, "p_cutoff", 0.05), arr.ind = TRUE)
  edges <- data.frame(
    from = colnames(cor_mat)[idx[, 1]], to = colnames(cor_mat)[idx[, 2]],
    correlation = cor_mat[idx], p_value = p_mat[idx], stringsAsFactors = FALSE
  )
  if (!nrow(edges)) stop("No network edges passed the configured correlation and p-value thresholds.")
  graph <- igraph::graph_from_data_frame(edges, directed = FALSE)
  nodes <- data.frame(
    node = igraph::V(graph)$name,
    degree = igraph::degree(graph),
    betweenness = igraph::betweenness(graph, normalized = TRUE),
    stringsAsFactors = FALSE
  )
  components <- igraph::components(graph)
  network_summary <- data.frame(
    nodes = igraph::vcount(graph), edges = igraph::ecount(graph),
    density = igraph::edge_density(graph),
    mean_degree = mean(igraph::degree(graph)),
    transitivity = igraph::transitivity(graph, type = "global"),
    components = components$no,
    largest_component_fraction = max(components$csize) / igraph::vcount(graph),
    positive_edge_fraction = mean(edges$correlation > 0),
    stringsAsFactors = FALSE
  )
  set.seed(param_int(params, "seed", 20260728))
  layout <- igraph::layout_with_fr(graph)
  node_plot <- data.frame(node = igraph::V(graph)$name, x = layout[, 1], y = layout[, 2])
  edge_plot <- data.frame(
    x = layout[match(edges$from, node_plot$node), 1],
    y = layout[match(edges$from, node_plot$node), 2],
    xend = layout[match(edges$to, node_plot$node), 1],
    yend = layout[match(edges$to, node_plot$node), 2],
    correlation = edges$correlation
  )
  node_plot <- merge(node_plot, nodes, by = "node")
  p <- ggplot2::ggplot() +
    ggplot2::geom_segment(data = edge_plot,
                          ggplot2::aes(x, y, xend = xend, yend = yend, color = correlation),
                          alpha = 0.55, linewidth = 0.5) +
    ggplot2::geom_point(data = node_plot, ggplot2::aes(x, y, size = degree),
                        color = "#165c48", fill = "white", shape = 21) +
    ggplot2::scale_color_gradient2(low = "#3465a4", mid = "grey85", high = "#c13a35",
                                   midpoint = 0) +
    ggplot2::theme_void() + ggplot2::labs(title = paste("Association", variant))

  if (variant == "network_properties") {
    p <- ggplot2::ggplot(nodes, ggplot2::aes(degree)) +
      ggplot2::geom_histogram(binwidth = 1, boundary = 0, fill = "#217a61", color = "white") +
      ggplot2::labs(title = "Network degree distribution", x = "Degree", y = "Node count") +
      theme_nature()
  } else if (variant == "network_robustness") {
    fractions <- seq(0, 0.8, by = 0.1)
    robustness <- do.call(rbind, lapply(c("random", "targeted"), function(mode) {
      data.frame(fraction_removed = fractions, giant_fraction = vapply(fractions, function(frac) {
        remove_n <- floor(igraph::vcount(graph) * frac)
        if (!remove_n) return(1)
        vertices <- if (mode == "targeted") {
          names(sort(igraph::degree(graph), decreasing = TRUE))[seq_len(remove_n)]
        } else {
          sample(igraph::V(graph)$name, remove_n)
        }
        reduced <- igraph::delete_vertices(graph, vertices)
        if (!igraph::vcount(reduced)) return(0)
        max(igraph::components(reduced)$csize) / igraph::vcount(graph)
      }, numeric(1)), mode = mode)
    }))
    p <- ggplot2::ggplot(robustness, ggplot2::aes(fraction_removed, giant_fraction, color = mode)) +
      ggplot2::geom_line(linewidth = 0.9) + ggplot2::geom_point() +
      ggplot2::labs(title = "Network robustness", y = "Largest component / original nodes") +
      theme_nature()
    amp_save_table(ctx, "network_robustness", robustness, "network_robustness.csv")
  } else if (variant == "network_stability") {
    boot <- param_int(params, "bootstrap_times", 30)
    edge_keys <- paste(pmin(edges$from, edges$to), pmax(edges$from, edges$to), sep = "::")
    stability <- vapply(seq_len(boot), function(i) {
      sampled <- x[sample(seq_len(nrow(x)), replace = TRUE), , drop = FALSE]
      cm <- stats::cor(sampled, method = "spearman")
      bi <- which(upper.tri(cm) & abs(cm) >= param_num(params, "cor_cutoff", 0.6), arr.ind = TRUE)
      keys <- paste(pmin(colnames(cm)[bi[, 1]], colnames(cm)[bi[, 2]]),
                    pmax(colnames(cm)[bi[, 1]], colnames(cm)[bi[, 2]]), sep = "::")
      length(intersect(edge_keys, keys)) / length(union(edge_keys, keys))
    }, numeric(1))
    stability_table <- data.frame(iteration = seq_len(boot), edge_jaccard = stability)
    p <- ggplot2::ggplot(stability_table, ggplot2::aes(edge_jaccard)) +
      ggplot2::geom_histogram(bins = 12, fill = "#217a61", color = "white") +
      ggplot2::labs(title = "Bootstrap network stability", x = "Edge-set Jaccard") + theme_nature()
    amp_save_table(ctx, "network_stability", stability_table, "network_stability.csv")
  }
  save_plot2(p, ctx$out_dir, variant, width = 10, height = 8)
  amp_save_table(ctx, "network_edges", edges, "network_edges.csv")
  amp_save_table(ctx, "network_nodes", nodes, "network_nodes.csv")
  amp_save_table(ctx, "network_summary", network_summary, "network_summary.csv")
  save_amp_workbook(ctx)
  invisible(list(edges = edges, nodes = nodes))
}

# Lightweight compositional network workflow. The implementation follows commonly used
# published workflow stages (filter -> zero handling -> normalization -> association ->
# sparsification -> properties/comparison), but is independently implemented here and
# does not require an additional network package.
amp_network_prepare <- function(ctx, params = list()) {
  requested_rank <- param_chr(params, "tax_rank", "Genus")
  rank <- amp_tax_rank(ctx$ps, requested_rank)
  counts <- amp_aggregate_taxa(ctx$ps, rank = rank, relative = FALSE)
  relative <- sweep(counts, 1, pmax(rowSums(counts), 1), "/")
  prevalence <- colMeans(counts > 0)
  mean_abundance <- colMeans(relative)
  min_prevalence <- param_num(params, "network_min_prevalence", 0.2)
  min_mean <- param_num(params, "network_min_mean_abundance", 0)
  keep <- prevalence >= min_prevalence & mean_abundance >= min_mean & colSums(counts) > 0
  candidates <- data.frame(
    node = colnames(counts), prevalence = prevalence,
    mean_relative_abundance = mean_abundance, retained = keep,
    stringsAsFactors = FALSE
  )
  counts <- counts[, keep, drop = FALSE]
  top_n <- min(param_int(params, "top_n", 50), ncol(counts))
  if (top_n > 0 && ncol(counts) > top_n) {
    selected <- names(sort(colMeans(relative[, colnames(counts), drop = FALSE]), decreasing = TRUE))[seq_len(top_n)]
    counts <- counts[, selected, drop = FALSE]
    candidates$retained <- candidates$node %in% selected
  }
  if (ncol(counts) < 4) {
    stop("组成型网络分析在过滤后至少需要4个分类单元。")
  }

  method <- tolower(param_chr(params, "network_method", "clr_spearman"))
  pseudocount <- param_num(params, "network_pseudocount", 0.5)
  if (!is.finite(pseudocount) || pseudocount <= 0) pseudocount <- 0.5
  transformed <- if (method %in% c("clr_spearman", "clr_pearson")) {
    logged <- log(counts + pseudocount)
    logged - rowMeans(logged)
  } else if (method == "spearman") {
    sweep(counts, 1, pmax(rowSums(counts), 1), "/")
  } else {
    stop("network_method 必须是 clr_spearman、clr_pearson 或 spearman。")
  }
  correlation_method <- if (method == "clr_pearson") "pearson" else "spearman"
  list(
    counts = counts, transformed = transformed, filter = candidates,
    rank = rank, method = method, correlation_method = correlation_method,
    pseudocount = pseudocount
  )
}

amp_network_associations <- function(x, params = list(), correlation_method = "spearman",
                                     allow_empty = FALSE) {
  if (nrow(x) < 4) stop("关联计算至少需要4个独立样本。")
  cor_mat <- suppressWarnings(stats::cor(x, method = correlation_method, use = "pairwise.complete.obs"))
  cor_mat[!is.finite(cor_mat)] <- 0
  diag(cor_mat) <- 1
  n <- nrow(x)
  t_stat <- cor_mat * sqrt(pmax(n - 2, 1) / pmax(1 - cor_mat^2, 1e-12))
  p_mat <- 2 * stats::pt(-abs(t_stat), df = pmax(n - 2, 1))
  pairs <- which(upper.tri(cor_mat), arr.ind = TRUE)
  all_edges <- data.frame(
    from = colnames(cor_mat)[pairs[, 1]],
    to = colnames(cor_mat)[pairs[, 2]],
    association = cor_mat[pairs],
    p_value = p_mat[pairs],
    stringsAsFactors = FALSE
  )
  all_edges$q_value <- stats::p.adjust(all_edges$p_value, method = "BH")
  all_edges$sign <- ifelse(all_edges$association >= 0, "positive", "negative")
  all_edges$weight <- abs(all_edges$association)
  cor_cutoff <- param_num(params, "cor_cutoff", 0.5)
  q_cutoff <- param_num(params, "network_q_cutoff", 0.05)
  selected <- all_edges$weight >= cor_cutoff & all_edges$q_value <= q_cutoff
  edges <- all_edges[selected, , drop = FALSE]
  if (!nrow(edges) && !allow_empty) {
    stop("没有关联边同时通过相关性阈值和FDR阈值。")
  }
  list(edges = edges, all_edges = all_edges, correlation = cor_mat)
}

amp_adjusted_rand <- function(x, y) {
  tab <- table(x, y)
  choose2 <- function(z) z * (z - 1) / 2
  n <- sum(tab)
  if (n < 2) return(NA_real_)
  sum_cells <- sum(choose2(tab))
  sum_rows <- sum(choose2(rowSums(tab)))
  sum_cols <- sum(choose2(colSums(tab)))
  total <- choose2(n)
  expected <- sum_rows * sum_cols / total
  maximum <- (sum_rows + sum_cols) / 2
  if (maximum == expected) return(1)
  (sum_cells - expected) / (maximum - expected)
}

amp_network_graph_summary <- function(edges, taxa, hub_quantile = 0.95) {
  vertices <- data.frame(name = taxa, stringsAsFactors = FALSE)
  graph <- igraph::graph_from_data_frame(edges, directed = FALSE, vertices = vertices)
  if (igraph::ecount(graph)) {
    igraph::E(graph)$weight <- edges$weight
    igraph::E(graph)$association <- edges$association
  }
  degree <- igraph::degree(graph)
  strength <- if (igraph::ecount(graph)) igraph::strength(graph, weights = igraph::E(graph)$weight) else rep(0, length(degree))
  betweenness <- if (igraph::ecount(graph)) igraph::betweenness(graph, directed = FALSE, normalized = TRUE) else rep(0, length(degree))
  closeness <- rep(0, length(degree))
  eigenvector <- rep(0, length(degree))
  components <- igraph::components(graph)
  lcc_vertices <- which(components$membership == which.max(components$csize))
  if (length(lcc_vertices) > 1 && igraph::ecount(graph)) {
    lcc <- igraph::induced_subgraph(graph, lcc_vertices)
    closeness[lcc_vertices] <- igraph::closeness(lcc, normalized = TRUE, weights = NA)
    eigenvector[lcc_vertices] <- igraph::eigen_centrality(
      lcc, directed = FALSE, weights = igraph::E(lcc)$weight
    )$vector
  }
  # Keep isolates comparable across runs instead of encoding their community as missing.
  community <- seq_len(igraph::vcount(graph))
  modularity <- NA_real_
  if (igraph::ecount(graph) && igraph::vcount(graph) > 2) {
    comm <- igraph::cluster_louvain(graph, weights = igraph::E(graph)$weight)
    community <- igraph::membership(comm)
    modularity <- igraph::modularity(comm)
  }
  hub_quantile <- min(max(hub_quantile, 0.5), 0.999)
  hub_cutoff <- if (any(eigenvector > 0)) stats::quantile(eigenvector[eigenvector > 0], hub_quantile, names = FALSE) else Inf
  nodes <- data.frame(
    node = igraph::V(graph)$name,
    degree = as.numeric(degree), strength = as.numeric(strength),
    betweenness = as.numeric(betweenness), closeness = as.numeric(closeness),
    eigenvector = as.numeric(eigenvector), component = as.integer(components$membership),
    community = as.integer(community),
    is_hub = as.numeric(eigenvector) >= hub_cutoff & as.numeric(degree) > 0,
    stringsAsFactors = FALSE
  )
  lcc_fraction <- max(components$csize) / max(igraph::vcount(graph), 1)
  avg_path <- NA_real_
  if (length(lcc_vertices) > 1) {
    avg_path <- igraph::mean_distance(igraph::induced_subgraph(graph, lcc_vertices), directed = FALSE)
  }
  global <- data.frame(
    nodes = igraph::vcount(graph), edges = igraph::ecount(graph),
    density = igraph::edge_density(graph), mean_degree = mean(degree),
    clustering_coefficient = if (igraph::ecount(graph)) igraph::transitivity(graph, type = "global") else 0,
    modularity = modularity, components = components$no,
    largest_component_fraction = lcc_fraction,
    positive_edge_fraction = if (nrow(edges)) mean(edges$association > 0) else NA_real_,
    average_path_length_lcc = avg_path,
    hubs = sum(nodes$is_hub), stringsAsFactors = FALSE
  )
  list(graph = graph, nodes = nodes, global = global)
}

amp_network_layout <- function(graph, seed = 20260812) {
  set.seed(seed)
  if (igraph::vcount(graph) == 1) return(matrix(c(0, 0), nrow = 1))
  if (!igraph::ecount(graph)) return(igraph::layout_in_circle(graph))
  igraph::layout_with_fr(graph, weights = if ("weight" %in% igraph::edge_attr_names(graph)) igraph::E(graph)$weight else NA)
}

amp_network_plot_data <- function(summary, layout, group_name) {
  nodes <- summary$nodes
  nodes$x <- layout[match(nodes$node, igraph::V(summary$graph)$name), 1]
  nodes$y <- layout[match(nodes$node, igraph::V(summary$graph)$name), 2]
  nodes$group <- group_name
  edges <- igraph::as_data_frame(summary$graph, what = "edges")
  if (nrow(edges)) {
    edges$x <- layout[match(edges$from, igraph::V(summary$graph)$name), 1]
    edges$y <- layout[match(edges$from, igraph::V(summary$graph)$name), 2]
    edges$xend <- layout[match(edges$to, igraph::V(summary$graph)$name), 1]
    edges$yend <- layout[match(edges$to, igraph::V(summary$graph)$name), 2]
    edges$group <- group_name
  } else {
    edges <- data.frame(
      from = character(), to = character(), association = numeric(), weight = numeric(),
      x = numeric(), y = numeric(), xend = numeric(), yend = numeric(), group = character(),
      stringsAsFactors = FALSE
    )
  }
  list(nodes = nodes, edges = edges)
}

amp_plot_compositional_network <- function(summary, title, layout = NULL) {
  if (is.null(layout)) layout <- amp_network_layout(summary$graph)
  plot_data <- amp_network_plot_data(summary, layout, title)
  p <- ggplot2::ggplot()
  if (nrow(plot_data$edges)) {
    p <- p + ggplot2::geom_segment(
      data = plot_data$edges,
      ggplot2::aes(x, y, xend = xend, yend = yend, color = association, linewidth = weight),
      alpha = 0.6
    )
  }
  p +
    ggplot2::geom_point(
      data = plot_data$nodes,
      ggplot2::aes(x, y, size = pmax(degree, 1), shape = is_hub, fill = factor(community)),
      color = "grey20", stroke = 0.3
    ) +
    ggplot2::geom_text(
      data = plot_data$nodes[plot_data$nodes$is_hub, , drop = FALSE],
      ggplot2::aes(x, y, label = node), nudge_y = 0.08, size = 3, check_overlap = TRUE
    ) +
    ggplot2::scale_color_gradient2(low = "#3465a4", mid = "grey85", high = "#c13a35", midpoint = 0) +
    ggplot2::scale_linewidth(range = c(0.3, 1.4), guide = "none") +
    ggplot2::scale_shape_manual(values = c("FALSE" = 21, "TRUE" = 23)) +
    ggplot2::guides(fill = "none") +
    ggplot2::theme_void() + ggplot2::labs(title = title, size = "Degree", shape = "Hub节点")
}

amp_ancombc2_native <- function(ctx, params = list()) {
  amp_require_package("ANCOMBC", "ANCOM-BC2")
  data <- amp_rank_contrast_data(ctx, params, minimum_per_group = 3)
  ps <- amp_rank_phyloseq(data)
  sample_data <- data.frame(phyloseq::sample_data(ps), check.names = FALSE)
  sample_data$Group <- stats::relevel(factor(sample_data$Group), ref = data$reference)
  phyloseq::sample_data(ps) <- phyloseq::sample_data(sample_data)
  output <- ANCOMBC::ancombc2(
    data = ps, fix_formula = "Group", group = "Group", p_adj_method = "BH",
    prv_cut = param_num(params, "min_prevalence", 0.1),
    pseudo_sens = param_bool(params, "ancombc_pseudo_sensitivity", FALSE),
    struc_zero = param_bool(params, "ancombc_structural_zero", TRUE),
    neg_lb = TRUE, alpha = param_num(params, "p_cutoff", 0.05),
    n_cl = max(1, param_int(params, "threads", 1)), verbose = FALSE,
    global = TRUE, pairwise = FALSE
  )
  result <- as.data.frame(output$res, check.names = FALSE)
  if (!"taxon" %in% names(result)) result$taxon <- rownames(result)
  lfc_col <- grep(paste0("^lfc_.*", data$comparison), names(result), value = TRUE)[1]
  q_col <- grep(paste0("^q_.*", data$comparison), names(result), value = TRUE)[1]
  p_col <- grep(paste0("^p_.*", data$comparison), names(result), value = TRUE)[1]
  if (is.na(lfc_col) || is.na(q_col)) stop("ANCOM-BC2结果中没有找到所选比较的效应量或q值列。")
  standardized <- data.frame(
    feature = result$taxon,
    log_fold_change = result[[lfc_col]],
    p_value = if (!is.na(p_col)) result[[p_col]] else NA_real_,
    q_value = result[[q_col]], stringsAsFactors = FALSE
  )
  amp_save_package_result(
    ctx, "ANCOMBC", "ANCOM-BC2", standardized, "log_fold_change", "q_value", "ancombc2",
    list(reference = data$reference, comparison = data$comparison, taxonomic_rank = data$rank,
         interpretation_boundary = "偏倚校正后的差异丰度关联不等同因果关系")
  )
}

amp_aldex2_native <- function(ctx, params = list()) {
  amp_require_package("ALDEx2", "ALDEx2")
  data <- amp_rank_contrast_data(ctx, params, minimum_per_group = 3)
  output <- ALDEx2::aldex(
    t(round(data$matrix)), as.character(data$group),
    mc.samples = max(16, param_int(params, "aldex_mc_samples", 128)),
    test = "t", effect = TRUE, denom = param_chr(params, "aldex_denom", "all"),
    verbose = FALSE
  )
  result <- as.data.frame(output, check.names = FALSE)
  result$feature <- rownames(result)
  effect_col <- if ("effect" %in% names(result)) "effect" else "diff.btw"
  q_col <- if ("we.eBH" %in% names(result)) "we.eBH" else "wi.eBH"
  standardized <- data.frame(
    feature = result$feature, effect = result[[effect_col]],
    p_value = result[[if ("we.ep" %in% names(result)) "we.ep" else "wi.ep"]],
    q_value = result[[q_col]], result[, setdiff(names(result), c("feature", effect_col, q_col)), drop = FALSE],
    check.names = FALSE, stringsAsFactors = FALSE
  )
  amp_save_package_result(
    ctx, "ALDEx2", "ALDEx2 Monte Carlo CLR", standardized, "effect", "q_value", "aldex2",
    list(reference = data$reference, comparison = data$comparison,
         mc_samples = max(16, param_int(params, "aldex_mc_samples", 128)), taxonomic_rank = data$rank)
  )
}

amp_maaslin2_native <- function(ctx, params = list()) {
  amp_require_package("Maaslin2", "MaAsLin2")
  data <- amp_rank_contrast_data(ctx, params, minimum_per_group = 3, relative = TRUE)
  metadata <- data$metadata
  metadata$Group <- stats::relevel(factor(data$group), ref = data$reference)
  output_dir <- file.path(ctx$out_dir, "maaslin2_backend")
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  fit <- Maaslin2::Maaslin2(
    input_data = data$matrix, input_metadata = metadata, output = output_dir,
    min_abundance = param_num(params, "min_mean_abundance", 0),
    min_prevalence = param_num(params, "min_prevalence", 0.1),
    normalization = "NONE", transform = param_chr(params, "maaslin_transform", "LOG"),
    analysis_method = "LM", max_significance = 1,
    fixed_effects = "Group", correction = "BH", standardize = FALSE,
    cores = max(1, param_int(params, "threads", 1)), plot_heatmap = FALSE,
    plot_scatter = FALSE, save_models = FALSE, reference = paste0("Group,", data$reference)
  )
  result <- as.data.frame(fit$results, check.names = FALSE)
  result <- result[result$metadata == "Group" & result$value == data$comparison, , drop = FALSE]
  standardized <- data.frame(
    feature = result$feature, coefficient = result$coef,
    standard_error = result$stderr, p_value = result$pval, q_value = result$qval,
    stringsAsFactors = FALSE
  )
  amp_save_package_result(
    ctx, "Maaslin2", "MaAsLin2 multivariable linear model", standardized,
    "coefficient", "q_value", "maaslin2",
    list(reference = data$reference, comparison = data$comparison, taxonomic_rank = data$rank,
         covariate_support = "通过maaslin_fixed_effects扩展；当前默认模型为Group")
  )
}

amp_linda_native <- function(ctx, params = list()) {
  amp_require_package("MicrobiomeStat", "LinDA")
  data <- amp_rank_contrast_data(ctx, params, minimum_per_group = 3)
  metadata <- data$metadata
  metadata$Group <- stats::relevel(factor(data$group), ref = data$reference)
  fit <- MicrobiomeStat::linda(
    feature.dat = t(data$matrix), meta.dat = metadata, formula = "~ Group",
    feature.dat.type = "count", prev.filter = param_num(params, "min_prevalence", 0.1),
    mean.abund.filter = param_num(params, "min_mean_abundance", 0),
    zero.handling = param_chr(params, "linda_zero_handling", "pseudo-count"),
    pseudo.cnt = param_num(params, "network_pseudocount", 0.5),
    p.adj.method = "BH", alpha = param_num(params, "p_cutoff", 0.05),
    n.cores = max(1, param_int(params, "threads", 1)), verbose = FALSE
  )
  result <- as.data.frame(fit$output[[1]], check.names = FALSE)
  result$feature <- rownames(result)
  standardized <- data.frame(
    feature = result$feature,
    coefficient = result$baseMean * 0 + result$log2FoldChange,
    standard_error = result$lfcSE,
    p_value = result$pvalue, q_value = result$padj,
    stringsAsFactors = FALSE
  )
  amp_save_package_result(
    ctx, "MicrobiomeStat", "LinDA", standardized, "coefficient", "q_value", "linda",
    list(reference = data$reference, comparison = data$comparison, taxonomic_rank = data$rank)
  )
}

amp_corncob_native <- function(ctx, params = list()) {
  amp_require_package("corncob", "corncob")
  data <- amp_rank_contrast_data(ctx, params, minimum_per_group = 3)
  metadata <- data$metadata
  metadata$Group <- stats::relevel(factor(data$group), ref = data$reference)
  fit <- corncob::differentialTest(
    formula = ~ Group, phi.formula = ~ Group,
    formula_null = ~ 1, phi.formula_null = ~ Group,
    data = t(round(data$matrix)), test = "Wald", sample_data = metadata,
    taxa_are_rows = TRUE, fdr_cutoff = param_num(params, "p_cutoff", 0.05),
    fdr = "BH", full_output = FALSE, verbose = FALSE
  )
  group_mean <- aggregate(data$matrix, by = list(Group = data$group), FUN = mean)
  ref_mean <- as.numeric(group_mean[group_mean$Group == data$reference, -1, drop = TRUE])
  cmp_mean <- as.numeric(group_mean[group_mean$Group == data$comparison, -1, drop = TRUE])
  standardized <- data.frame(
    feature = colnames(data$matrix),
    descriptive_log2_fold_change = log2((cmp_mean + 0.5) / (ref_mean + 0.5)),
    p_value = as.numeric(fit$p[colnames(data$matrix)]),
    q_value = as.numeric(fit$p_fdr[colnames(data$matrix)]), stringsAsFactors = FALSE
  )
  amp_save_package_result(
    ctx, "corncob", "beta-binomial differential abundance", standardized,
    "descriptive_log2_fold_change", "q_value", "corncob",
    list(reference = data$reference, comparison = data$comparison, taxonomic_rank = data$rank,
         effect_note = "图中fold change为组均值描述量；显著性来自beta-binomial模型")
  )
}

amp_metagenomeseq_native <- function(ctx, params = list()) {
  amp_require_package("metagenomeSeq", "metagenomeSeq fitZig")
  data <- amp_rank_contrast_data(ctx, params, minimum_per_group = 3)
  metadata <- data$metadata
  metadata$Group <- stats::relevel(factor(data$group), ref = data$reference)
  pheno <- Biobase::AnnotatedDataFrame(metadata)
  obj <- metagenomeSeq::newMRexperiment(t(round(data$matrix)), phenoData = pheno)
  obj <- metagenomeSeq::cumNorm(obj, p = metagenomeSeq::cumNormStatFast(obj))
  model <- stats::model.matrix(~ Group, data = metadata)
  fit <- metagenomeSeq::fitZig(obj, model, useCSSoffset = TRUE)
  result <- metagenomeSeq::MRcoefs(fit, number = ncol(data$matrix), coef = 2)
  result$feature <- rownames(result)
  effect_col <- c("logFC", "Estimate", "coef", grep("^Group", names(result), value = TRUE))
  effect_col <- effect_col[effect_col %in% names(result)][1]
  p_col <- c("P.Value", "pvalue", "pvalues", "p.value")
  p_col <- p_col[p_col %in% names(result)][1]
  q_col <- c("adj.P.Val", "adjPvalues", "qvalue")
  q_col <- q_col[q_col %in% names(result)][1]
  if (any(is.na(c(effect_col, p_col, q_col)))) {
    stop("metagenomeSeq结果列结构与当前适配器不兼容：", paste(names(result), collapse = ", "))
  }
  standardized <- data.frame(
    feature = result$feature, coefficient = result[[effect_col]],
    p_value = result[[p_col]], q_value = result[[q_col]],
    stringsAsFactors = FALSE
  )
  amp_save_package_result(
    ctx, "metagenomeSeq", "CSS + zero-inflated Gaussian model", standardized,
    "coefficient", "q_value", "metagenomeseq",
    list(reference = data$reference, comparison = data$comparison, taxonomic_rank = data$rank)
  )
}

amp_maaslin3_native <- function(ctx, params = list()) {
  amp_require_package("maaslin3", "MaAsLin3")
  data <- amp_rank_contrast_data(ctx, params, minimum_per_group = 3, relative = TRUE)
  metadata <- data$metadata
  metadata$Group <- stats::relevel(factor(data$group), ref = data$reference)
  output_dir <- file.path(ctx$out_dir, "maaslin3_backend")
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  fit <- maaslin3::maaslin3(
    input_data = data$matrix, input_metadata = metadata, output = output_dir,
    formula = "~ Group", reference = paste0("Group,", data$reference),
    min_prevalence = param_num(params, "min_prevalence", 0.1),
    normalization = "NONE", transform = param_chr(params, "maaslin_transform", "LOG"),
    correction = "BH", standardize = FALSE, max_significance = 1,
    cores = max(1, param_int(params, "threads", 1)),
    plot_summary_plot = FALSE, plot_associations = FALSE, save_models = FALSE,
    verbosity = "WARN"
  )
  result <- if (!is.null(fit$results)) as.data.frame(fit$results, check.names = FALSE) else {
    candidates <- c(file.path(output_dir, "all_results.tsv"), file.path(output_dir, "all_results.csv"))
    existing <- candidates[file.exists(candidates)]
    if (!length(existing)) stop("MaAsLin3没有生成可识别的结果表。")
    utils::read.delim(existing[[1]], check.names = FALSE)
  }
  effect_col <- c("coef", "coefficient")
  effect_col <- effect_col[effect_col %in% names(result)][1]
  q_col <- c("qval", "q_value", "qval_individual", "qval_joint")
  q_col <- q_col[q_col %in% names(result)][1]
  p_col <- c("pval", "p_value", "pval_individual", "pval_joint")
  p_col <- p_col[p_col %in% names(result)][1]
  feature_col <- c("feature", "metadata")
  feature_col <- feature_col[feature_col %in% names(result)][1]
  if (any(is.na(c(effect_col, q_col, feature_col)))) stop("MaAsLin3结果列结构与当前适配器不兼容。")
  standardized <- data.frame(
    feature = result[[feature_col]], coefficient = result[[effect_col]],
    p_value = if (!is.na(p_col)) result[[p_col]] else NA_real_, q_value = result[[q_col]],
    stringsAsFactors = FALSE
  )
  amp_save_package_result(
    ctx, "maaslin3", "MaAsLin3", standardized, "coefficient", "q_value", "maaslin3",
    list(reference = data$reference, comparison = data$comparison, taxonomic_rank = data$rank)
  )
}

amp_lefse_native <- function(ctx, params = list()) {
  amp_require_package("lefser", "LEfSe")
  data <- amp_rank_contrast_data(ctx, params, minimum_per_group = 3, relative = TRUE)
  experiment <- SummarizedExperiment::SummarizedExperiment(
    assays = list(relative_abundance = t(data$matrix)),
    colData = S4Vectors::DataFrame(Group = data$group, row.names = rownames(data$matrix))
  )
  result <- lefser::lefser(
    experiment, kruskal.threshold = param_num(params, "p_cutoff", 0.05),
    lda.threshold = param_num(params, "lda_cutoff", 2),
    classCol = "Group", checkAbundances = TRUE, method = "BH"
  )
  result <- as.data.frame(result, check.names = FALSE)
  if (!nrow(result)) {
    standardized <- data.frame(
      feature = character(), lda_score = numeric(), p_value = numeric(),
      q_value = numeric(), enriched_group = character(), stringsAsFactors = FALSE
    )
    return(amp_save_package_result(
      ctx, "lefser", "LEfSe", standardized, "lda_score", "q_value", "lefse",
      list(reference = data$reference, comparison = data$comparison, taxonomic_rank = data$rank,
           result_note = "当前阈值下没有筛选到显著候选特征")
    ))
  }
  feature_col <- names(result)[1]
  effect_col <- names(result)[2]
  standardized <- data.frame(
    feature = result[[feature_col]], lda_score = result[[effect_col]],
    p_value = NA_real_, q_value = NA_real_,
    enriched_group = ifelse(result[[effect_col]] >= 0, data$comparison, data$reference),
    stringsAsFactors = FALSE
  )
  amp_save_package_result(
    ctx, "lefser", "LEfSe", standardized, "lda_score", "q_value", "lefse",
    list(reference = data$reference, comparison = data$comparison, taxonomic_rank = data$rank,
         interpretation_boundary = "LEfSe用于候选标志物筛选，不证明因果或诊断性能")
  )
}

amp_breakaway_native <- function(ctx, params = list()) {
  amp_require_package("breakaway", "breakaway richness")
  counts <- amp_sample_matrix(ctx$ps, relative = FALSE)
  metadata <- data.frame(phyloseq::sample_data(ctx$ps), check.names = FALSE)
  rows <- lapply(seq_len(nrow(counts)), function(i) {
    positive <- counts[i, counts[i, ] > 0]
    frequency <- table(as.integer(round(positive)))
    input <- data.frame(index = as.numeric(names(frequency)), frequency = as.numeric(frequency))
    fit <- tryCatch(
      breakaway::breakaway(input, plot = FALSE, output = FALSE, answers = TRUE),
      error = function(e) breakaway::breakaway_nof1(input, plot = FALSE, output = FALSE, answers = TRUE)
    )
    data.frame(
      SampleID = rownames(counts)[i], estimate = fit$estimate %||% fit$est,
      standard_error = fit$error %||% fit$seest,
      lower = (fit$interval %||% fit$ci)[1], upper = (fit$interval %||% fit$ci)[2],
      model = fit$name %||% fit$model, stringsAsFactors = FALSE
    )
  })
  result <- do.call(rbind, rows)
  result$Group <- as.character(metadata[result$SampleID, "Group"])
  p <- ggplot2::ggplot(result, ggplot2::aes(Group, estimate, color = Group)) +
    ggplot2::geom_boxplot(outlier.shape = NA, alpha = 0.18) +
    ggplot2::geom_point(position = ggplot2::position_jitter(width = 0.12), size = 2) +
    ggplot2::labs(title = "breakaway未观测丰富度估计", x = NULL, y = "估计丰富度") + theme_nature()
  save_plot2(p, ctx$out_dir, "breakaway_richness", width = 9, height = 7)
  amp_save_table(ctx, "breakaway_method", amp_package_method_table(
    "breakaway", "frequency-ratio richness estimator",
    list(interpretation_boundary = "估计依赖频数结构；极稀疏样本可能具有宽置信区间")
  ), "breakaway_method.csv")
  amp_save_table(ctx, "breakaway_results", result, "breakaway_results.csv")
  save_amp_workbook(ctx)
  invisible(result)
}

amp_gunifrac_native <- function(ctx, params = list()) {
  amp_require_package("GUniFrac", "Generalized UniFrac")
  tree <- phyloseq::phy_tree(ctx$ps, errorIfNULL = FALSE)
  if (is.null(tree)) stop("Generalized UniFrac需要与特征表匹配的系统发育树。")
  counts <- amp_sample_matrix(ctx$ps, relative = FALSE)
  output <- GUniFrac::GUniFrac(counts, tree, alpha = c(0, 0.5, 1), verbose = FALSE)$unifracs
  metric <- param_chr(params, "gunifrac_metric", "d_0.5")
  if (!metric %in% dimnames(output)[[3]]) stop("gunifrac_metric不在可用距离中。")
  distance <- stats::as.dist(output[, , metric])
  metadata <- data.frame(phyloseq::sample_data(ctx$ps), check.names = FALSE)
  ord <- stats::cmdscale(distance, k = 2, eig = TRUE, add = TRUE)
  points <- data.frame(SampleID = rownames(ord$points), Axis1 = ord$points[, 1], Axis2 = ord$points[, 2])
  points$Group <- as.character(metadata[points$SampleID, "Group"])
  p <- ggplot2::ggplot(points, ggplot2::aes(Axis1, Axis2, color = Group)) +
    ggplot2::geom_point(size = 3) +
    ggplot2::stat_ellipse(level = 0.68, show.legend = FALSE) +
    ggplot2::labs(title = paste0("Generalized UniFrac PCoA（", metric, "）")) + theme_nature()
  adonis <- vegan::adonis2(distance ~ Group, data = transform(metadata, Group = factor(Group)),
                           permutations = param_int(params, "permutations", 999))
  dispersion <- vegan::betadisper(distance, factor(metadata$Group))
  disp <- vegan::permutest(dispersion, permutations = param_int(params, "permutations", 999))
  tests <- data.frame(
    test = c("PERMANOVA", "PERMDISP"), statistic = c(adonis$F[1], disp$tab$F[1]),
    R2 = c(adonis$R2[1], NA_real_), p_value = c(adonis$`Pr(>F)`[1], disp$tab$`Pr(>F)`[1]),
    stringsAsFactors = FALSE
  )
  save_plot2(p, ctx$out_dir, "generalized_unifrac_pcoa", width = 9, height = 7)
  amp_save_table(ctx, "gunifrac_method", amp_package_method_table(
    "GUniFrac", "Generalized UniFrac", list(metric = metric, permutations = param_int(params, "permutations", 999))
  ), "generalized_unifrac_method.csv")
  amp_save_table(ctx, "gunifrac_points", points, "generalized_unifrac_coordinates.csv")
  amp_save_table(ctx, "gunifrac_tests", tests, "generalized_unifrac_tests.csv")
  save_amp_workbook(ctx)
  invisible(list(points = points, tests = tests))
}

amp_coda_pca_native <- function(ctx, params = list()) {
  amp_require_package("zCompositions", "zero replacement")
  amp_require_package("compositions", "CLR transformation")
  amp_require_package("robCompositions", "CoDA PCA")
  rank <- amp_tax_rank(ctx$ps, param_chr(params, "tax_rank", "Genus"))
  counts <- amp_aggregate_taxa(ctx$ps, rank, relative = FALSE)
  prevalence <- colMeans(counts > 0)
  counts <- counts[, prevalence >= param_num(params, "min_prevalence", 0.1), drop = FALSE]
  top_n <- min(param_int(params, "top_n", 50), ncol(counts))
  if (ncol(counts) > top_n) counts <- counts[, names(sort(colMeans(counts), decreasing = TRUE))[seq_len(top_n)], drop = FALSE]
  if (ncol(counts) < 3) stop("CoDA PCA过滤后至少需要3个分类单元。")
  replaced <- zCompositions::cmultRepl(
    counts, label = 0, method = param_chr(params, "zero_replacement_method", "CZM"),
    output = "prop", suppress.print = TRUE
  )
  clr <- compositions::clr(replaced)
  fit <- robCompositions::pcaCoDa(replaced, method = param_chr(params, "coda_pca_method", "classical"))
  metadata <- data.frame(phyloseq::sample_data(ctx$ps), check.names = FALSE)
  scores <- data.frame(
    SampleID = rownames(counts), PC1 = fit$scores[, 1], PC2 = fit$scores[, 2],
    Group = as.character(metadata[rownames(counts), "Group"]), stringsAsFactors = FALSE
  )
  loadings <- data.frame(
    feature = rownames(fit$loadings), PC1 = fit$loadings[, 1], PC2 = fit$loadings[, 2],
    stringsAsFactors = FALSE
  )
  variance <- fit$eigenvalues / sum(fit$eigenvalues)
  p <- ggplot2::ggplot(scores, ggplot2::aes(PC1, PC2, color = Group)) +
    ggplot2::geom_point(size = 3) +
    ggplot2::stat_ellipse(level = 0.68, show.legend = FALSE) +
    ggplot2::labs(
      title = "组成数据分析PCA（零值替换 + CLR）",
      x = sprintf("PC1（%.1f%%）", 100 * variance[1]),
      y = sprintf("PC2（%.1f%%）", 100 * variance[2])
    ) + theme_nature()
  save_plot2(p, ctx$out_dir, "coda_pca", width = 9, height = 7)
  versions <- paste0(
    "zCompositions ", utils::packageVersion("zCompositions"), "; compositions ",
    utils::packageVersion("compositions"), "; robCompositions ", utils::packageVersion("robCompositions")
  )
  amp_save_table(ctx, "coda_pca_method", data.frame(
    backend_packages = versions, method = "multiplicative zero replacement + CLR + CoDA PCA",
    zero_replacement = param_chr(params, "zero_replacement_method", "CZM"),
    taxonomic_rank = rank, retained_taxa = ncol(counts),
    interpretation_boundary = "PCA分离是探索性结构，不等同显著处理效应或因果关系",
    stringsAsFactors = FALSE
  ), "coda_pca_method.csv")
  amp_save_table(ctx, "coda_pca_scores", scores, "coda_pca_scores.csv")
  amp_save_table(ctx, "coda_pca_loadings", loadings, "coda_pca_loadings.csv")
  amp_save_table(ctx, "coda_clr", cbind(SampleID = rownames(clr), as.data.frame(clr)), "coda_clr_matrix.csv")
  save_amp_workbook(ctx)
  invisible(list(scores = scores, loadings = loadings))
}

amp_spieceasi_native <- function(ctx, params = list()) {
  amp_require_package("SpiecEasi", "SPIEC-EASI")
  data <- amp_rank_contrast_data(ctx, params, minimum_per_group = 10)
  counts <- data$matrix
  prevalence <- colMeans(counts > 0)
  keep <- prevalence >= param_num(params, "network_min_prevalence", 0.2)
  counts <- counts[, keep, drop = FALSE]
  top_n <- min(param_int(params, "top_n", 50), ncol(counts))
  if (ncol(counts) > top_n) {
    selected <- names(sort(colMeans(counts), decreasing = TRUE))[seq_len(top_n)]
    counts <- counts[, selected, drop = FALSE]
  }
  if (ncol(counts) < 4) stop("SPIEC-EASI过滤后至少需要4个分类单元。")
  rep_num <- max(10, param_int(params, "spieceasi_rep_num", 20))
  # SpiecEasi passes this exported estimator to pulsar by name. Bind it in the
  # global search environment so the Windows worker can resolve the function.
  assign("sparseiCov", SpiecEasi::sparseiCov, envir = .GlobalEnv)
  on.exit(if (exists("sparseiCov", envir = .GlobalEnv, inherits = FALSE)) {
    rm("sparseiCov", envir = .GlobalEnv)
  }, add = TRUE)
  fit <- SpiecEasi::spiec.easi(
    counts, method = param_chr(params, "spieceasi_method", "mb"),
    nlambda = max(10, param_int(params, "spieceasi_nlambda", 20)),
    lambda.min.ratio = param_num(params, "spieceasi_lambda_min_ratio", 0.01),
    pulsar.params = list(rep.num = rep_num, ncores = 1,
                         seed = param_int(params, "seed", 20260812))
  )
  beta <- SpiecEasi::symBeta(SpiecEasi::getOptBeta(fit), mode = "ave")
  adjacency <- sign(beta) * (beta != 0)
  dimnames(adjacency) <- list(colnames(counts), colnames(counts))
  pairs <- which(upper.tri(adjacency) & adjacency != 0, arr.ind = TRUE)
  edges <- data.frame(
    from = colnames(adjacency)[pairs[, 1]], to = colnames(adjacency)[pairs[, 2]],
    association = adjacency[pairs], weight = abs(adjacency[pairs]),
    sign = ifelse(adjacency[pairs] >= 0, "positive", "negative"), stringsAsFactors = FALSE
  )
  summary <- amp_network_graph_summary(edges, colnames(counts),
                                       param_num(params, "network_hub_quantile", 0.95))
  plot <- amp_plot_compositional_network(summary, "SPIEC-EASI稀疏条件依赖网络")
  stability <- tryCatch(SpiecEasi::getStability(fit), error = function(e) NULL)
  save_plot2(plot, ctx$out_dir, "spieceasi_network", width = 10, height = 8)
  amp_save_table(ctx, "spieceasi_method", amp_package_method_table(
    "SpiecEasi", "SPIEC-EASI",
    list(method = param_chr(params, "spieceasi_method", "mb"), stability_subsamples = rep_num,
         retained_taxa = ncol(counts), samples = nrow(counts),
         interpretation_boundary = "条件依赖边是统计网络假设，不是已证明的生态互作")
  ), "spieceasi_method.csv")
  amp_save_table(ctx, "spieceasi_edges", edges, "spieceasi_edges.csv")
  amp_save_table(ctx, "spieceasi_nodes", summary$nodes, "spieceasi_nodes.csv")
  amp_save_table(ctx, "spieceasi_summary", summary$global, "spieceasi_summary.csv")
  if (!is.null(stability) && length(unlist(stability))) {
    stability_values <- unlist(stability)
    stability_names <- names(stability_values)
    if (is.null(stability_names) || length(stability_names) != length(stability_values)) {
      stability_names <- paste0("stability_", seq_along(stability_values))
    }
    amp_save_table(ctx, "spieceasi_stability", data.frame(
      metric = stability_names, value = as.character(stability_values),
      stringsAsFactors = FALSE
    ), "spieceasi_stability.csv")
  }
  save_amp_workbook(ctx)
  invisible(list(edges = edges, nodes = summary$nodes, summary = summary$global))
}

amp_splsda_native <- function(ctx, params = list()) {
  amp_require_package("mixOmics", "sPLS-DA")
  data <- amp_rank_contrast_data(ctx, params, minimum_per_group = 10)
  counts <- data$matrix
  logged <- log(counts + param_num(params, "network_pseudocount", 0.5))
  x <- logged - rowMeans(logged)
  y <- data$group
  ncomp <- min(2, nlevels(y), ncol(x))
  keep_n <- min(max(2, param_int(params, "optimal", 20)), ncol(x))
  fit <- mixOmics::splsda(x, y, ncomp = ncomp, keepX = rep(keep_n, ncomp), scale = TRUE)
  scores <- data.frame(
    SampleID = rownames(x), Component1 = fit$variates$X[, 1],
    Component2 = if (ncomp >= 2) fit$variates$X[, 2] else 0,
    Group = y, stringsAsFactors = FALSE
  )
  selected <- do.call(rbind, lapply(seq_len(ncomp), function(component) {
    item <- mixOmics::selectVar(fit, comp = component)
    data.frame(feature = item$name, loading = as.numeric(item$value[[1]]),
               component = component, stringsAsFactors = FALSE)
  }))
  folds <- min(param_int(params, "folds", 5), min(table(y)))
  performance <- mixOmics::perf(
    fit, validation = "Mfold", folds = folds,
    nrepeat = max(2, param_int(params, "ml_repeats", 5)), progressBar = FALSE
  )
  error_values <- as.data.frame(performance$error.rate$BER, check.names = FALSE)
  error_values$component <- rownames(error_values)
  p_scores <- ggplot2::ggplot(scores, ggplot2::aes(Component1, Component2, color = Group)) +
    ggplot2::geom_point(size = 3) +
    ggplot2::stat_ellipse(level = 0.68, show.legend = FALSE) +
    ggplot2::labs(title = "sPLS-DA样本得分（仅探索性）") + theme_nature()
  p_loadings <- ggplot2::ggplot(head(selected[order(-abs(selected$loading)), ], 30),
                                ggplot2::aes(stats::reorder(feature, loading), loading,
                                             fill = factor(component))) +
    ggplot2::geom_col() + ggplot2::coord_flip() +
    ggplot2::labs(title = "sPLS-DA入选特征", x = NULL, fill = "Component") + theme_nature()
  save_plot2(p_scores, ctx$out_dir, "splsda_scores", width = 9, height = 7)
  save_plot2(p_loadings, ctx$out_dir, "splsda_loadings", width = 9, height = 8)
  amp_save_table(ctx, "splsda_method", amp_package_method_table(
    "mixOmics", "sPLS-DA",
    list(folds = folds, repeats = max(2, param_int(params, "ml_repeats", 5)), selected_per_component = keep_n,
         interpretation_boundary = "监督降维和载荷用于候选特征探索；没有独立验证时不能称为稳定生物标志物")
  ), "splsda_method.csv")
  amp_save_table(ctx, "splsda_scores", scores, "splsda_scores.csv")
  amp_save_table(ctx, "splsda_loadings", selected, "splsda_loadings.csv")
  amp_save_table(ctx, "splsda_cv", error_values, "splsda_cross_validation.csv")
  save_amp_workbook(ctx)
  invisible(list(scores = scores, loadings = selected, performance = error_values))
}

amp_siamcat_native <- function(ctx, params = list()) {
  amp_require_package("SIAMCAT", "SIAMCAT")
  data <- amp_rank_contrast_data(ctx, params, minimum_per_group = 10, relative = TRUE)
  feature_matrix <- t(data$matrix)
  label_values <- as.character(data$group)
  names(label_values) <- rownames(data$matrix)
  label <- SIAMCAT::create.label(label_values, case = data$comparison, control = data$reference)
  siamcat <- SIAMCAT::siamcat(feat = feature_matrix, label = label, meta = data$metadata, verbose = 0)
  siamcat <- SIAMCAT::filter.features(
    siamcat, filter.method = "prevalence",
    cutoff = param_num(params, "min_prevalence", 0.1), verbose = 0
  )
  siamcat <- SIAMCAT::normalize.features(siamcat, norm.method = "log.clr", verbose = 0)
  folds <- min(param_int(params, "folds", 5), min(table(data$group)))
  siamcat <- SIAMCAT::create.data.split(
    siamcat, num.folds = folds, num.resample = max(2, param_int(params, "ml_repeats", 5)),
    stratify = TRUE, verbose = 0
  )
  siamcat <- SIAMCAT::train.model(
    siamcat, method = param_chr(params, "siamcat_method", "ridge"),
    measure = "classif.acc", min.nonzero = 1, verbose = 0
  )
  siamcat <- SIAMCAT::make.predictions(siamcat, verbose = 0)
  siamcat <- SIAMCAT::evaluate.predictions(siamcat, verbose = 0)
  predictions <- as.data.frame(SIAMCAT::pred_matrix(siamcat), check.names = FALSE)
  predictions$SampleID <- rownames(predictions)
  evaluation_raw <- SIAMCAT::eval_data(siamcat)
  evaluation <- data.frame(
    metric = c("AUROC", "AUPRC"),
    value = c(as.numeric(evaluation_raw$auroc), as.numeric(evaluation_raw$auprc)),
    stringsAsFactors = FALSE
  )
  fold_evaluation <- data.frame(
    fold = seq_along(evaluation_raw$auroc.all),
    AUROC = as.numeric(evaluation_raw$auroc.all),
    AUPRC = as.numeric(evaluation_raw$auprc.all), stringsAsFactors = FALSE
  )
  weights <- tryCatch(as.data.frame(SIAMCAT::feature_weights(siamcat), check.names = FALSE),
                      error = function(e) data.frame())
  long <- tidyr::pivot_longer(fold_evaluation, c("AUROC", "AUPRC"), names_to = "metric", values_to = "value")
  p <- ggplot2::ggplot(long, ggplot2::aes(metric, value)) +
    ggplot2::geom_boxplot(fill = "#217a61", alpha = 0.35) +
    ggplot2::geom_point(position = ggplot2::position_jitter(width = 0.08)) +
    ggplot2::labs(title = "SIAMCAT交叉验证性能", x = NULL) + theme_nature()
  save_plot2(p, ctx$out_dir, "siamcat_performance", width = 8, height = 6)
  amp_save_table(ctx, "siamcat_method", amp_package_method_table(
    "SIAMCAT", "cross-validated microbiome classifier",
    list(model = param_chr(params, "siamcat_method", "lasso"), folds = folds,
         repeats = max(2, param_int(params, "ml_repeats", 5)),
         interpretation_boundary = "内部交叉验证不替代独立外部验证")
  ), "siamcat_method.csv")
  amp_save_table(ctx, "siamcat_predictions", predictions, "siamcat_predictions.csv")
  amp_save_table(ctx, "siamcat_evaluation", evaluation, "siamcat_evaluation.csv")
  amp_save_table(ctx, "siamcat_fold_evaluation", fold_evaluation, "siamcat_fold_evaluation.csv")
  if (nrow(weights)) amp_save_table(ctx, "siamcat_weights", weights, "siamcat_feature_weights.csv")
  save_amp_workbook(ctx)
  invisible(list(predictions = predictions, evaluation = evaluation, weights = weights))
}

amp_wgcna_native <- function(ctx, params = list()) {
  amp_require_package("WGCNA", "WGCNA")
  # blockwiseModules resolves `cor` on the search path. Loading the namespace as
  # an attached package ensures it finds WGCNA::cor rather than stats::cor.
  suppressPackageStartupMessages(library(WGCNA))
  data <- amp_rank_contrast_data(ctx, params, minimum_per_group = 10)
  counts <- data$matrix
  prevalence <- colMeans(counts > 0)
  counts <- counts[, prevalence >= param_num(params, "network_min_prevalence", 0.2), drop = FALSE]
  top_n <- min(max(20, param_int(params, "top_n", 100)), ncol(counts))
  if (ncol(counts) > top_n) counts <- counts[, names(sort(apply(counts, 2, stats::var), decreasing = TRUE))[seq_len(top_n)], drop = FALSE]
  if (ncol(counts) < 10) stop("WGCNA过滤后至少需要10个分类单元。")
  logged <- log(counts + param_num(params, "network_pseudocount", 0.5))
  x <- logged - rowMeans(logged)
  min_module <- min(max(5, param_int(params, "wgcna_min_module_size", 10)), floor(ncol(x) / 2))
  fit <- WGCNA::blockwiseModules(
    x, power = max(1, param_int(params, "wgcna_power", 6)),
    networkType = param_chr(params, "wgcna_network_type", "signed"),
    TOMType = "signed", minModuleSize = min_module,
    mergeCutHeight = param_num(params, "wgcna_merge_cut_height", 0.25),
    numericLabels = FALSE, pamRespectsDendro = FALSE,
    nThreads = max(1, param_int(params, "threads", 1)),
    useInternalMatrixAlgebra = TRUE, verbose = 0
  )
  modules <- data.frame(feature = colnames(x), module = fit$colors, stringsAsFactors = FALSE)
  eigengenes <- as.data.frame(WGCNA::moduleEigengenes(x, colors = fit$colors)$eigengenes)
  trait <- as.numeric(data$group == data$comparison)
  associations <- do.call(rbind, lapply(names(eigengenes), function(name) {
    test <- suppressWarnings(stats::cor.test(eigengenes[[name]], trait, method = "pearson"))
    data.frame(module = sub("^ME", "", name), correlation = unname(test$estimate),
               p_value = test$p.value, stringsAsFactors = FALSE)
  }))
  associations$q_value <- stats::p.adjust(associations$p_value, "BH")
  p_modules <- ggplot2::ggplot(as.data.frame(table(modules$module)),
                               ggplot2::aes(stats::reorder(Var1, Freq), Freq, fill = Var1)) +
    ggplot2::geom_col() + ggplot2::coord_flip() +
    ggplot2::guides(fill = "none") +
    ggplot2::labs(title = "WGCNA模块大小", x = "Module", y = "分类单元数") + theme_nature()
  p_assoc <- ggplot2::ggplot(associations,
                             ggplot2::aes(stats::reorder(module, correlation), correlation,
                                          fill = q_value <= 0.05)) +
    ggplot2::geom_col() + ggplot2::coord_flip() +
    ggplot2::labs(title = paste0("WGCNA模块与", data$comparison, "的关联"), x = "Module") + theme_nature()
  save_plot2(p_modules, ctx$out_dir, "wgcna_module_sizes", width = 8, height = 7)
  save_plot2(p_assoc, ctx$out_dir, "wgcna_module_trait", width = 8, height = 7)
  amp_save_table(ctx, "wgcna_method", amp_package_method_table(
    "WGCNA", "weighted correlation network modules",
    list(samples = nrow(x), retained_taxa = ncol(x), reference = data$reference,
         comparison = data$comparison,
         interpretation_boundary = "模块-处理相关性不证明模块受处理直接调控")
  ), "wgcna_method.csv")
  amp_save_table(ctx, "wgcna_modules", modules, "wgcna_modules.csv")
  amp_save_table(ctx, "wgcna_eigengenes", cbind(SampleID = rownames(eigengenes), eigengenes), "wgcna_eigengenes.csv")
  amp_save_table(ctx, "wgcna_associations", associations, "wgcna_module_trait_associations.csv")
  save_amp_workbook(ctx)
  invisible(list(modules = modules, associations = associations))
}

amp_network_compositional_native <- function(ctx, params = list()) {
  prepared <- amp_network_prepare(ctx, params)
  association <- amp_network_associations(
    prepared$transformed, params, prepared$correlation_method, allow_empty = TRUE
  )
  summary <- amp_network_graph_summary(
    association$edges, colnames(prepared$transformed),
    hub_quantile = param_num(params, "network_hub_quantile", 0.95)
  )
  p_network <- amp_plot_compositional_network(
    summary, paste0("组成型关联网络（", prepared$method, "）")
  )
  p_degree <- ggplot2::ggplot(summary$nodes, ggplot2::aes(degree)) +
    ggplot2::geom_histogram(binwidth = 1, boundary = 0, fill = "#217a61", color = "white") +
    ggplot2::labs(title = "网络节点度分布", x = "Degree", y = "节点数") +
    theme_nature()
  method_table <- data.frame(
    taxonomic_rank = prepared$rank, transform = prepared$method,
    zero_replacement = if (grepl("clr", prepared$method)) paste0("pseudocount=", prepared$pseudocount) else "none",
    association = prepared$correlation_method,
    association_test = if (identical(prepared$correlation_method, "spearman")) {
      "Spearman相关的t近似检验（探索性）"
    } else {
      "Pearson相关的t检验"
    },
    sparsification = paste0("|association| >= ", param_num(params, "cor_cutoff", 0.5),
                            "; BH q <= ", param_num(params, "network_q_cutoff", 0.05)),
    samples = nrow(prepared$transformed), retained_taxa = ncol(prepared$transformed),
    edge_stability = "本方法未进行bootstrap稳定性重采样",
    interpretation_boundary = "关联边是待验证假设，不能直接等同生态互作或因果关系",
    stringsAsFactors = FALSE
  )
  save_plot2(p_network, ctx$out_dir, "compositional_network", width = 10, height = 8)
  save_plot2(p_degree, ctx$out_dir, "compositional_network_degree", width = 8, height = 6)
  amp_save_table(ctx, "network_method", method_table, "compositional_network_method.csv")
  amp_save_table(ctx, "network_filter", prepared$filter, "compositional_network_filter.csv")
  amp_save_table(ctx, "network_all_associations", association$all_edges, "compositional_network_all_associations.csv")
  amp_save_table(ctx, "network_edges", association$edges, "compositional_network_edges.csv")
  amp_save_table(ctx, "network_nodes", summary$nodes, "compositional_network_nodes.csv")
  amp_save_table(ctx, "network_summary", summary$global, "compositional_network_summary.csv")
  save_amp_workbook(ctx)
  invisible(list(method = method_table, edges = association$edges, nodes = summary$nodes, summary = summary$global))
}

amp_network_compare_native <- function(ctx, params = list()) {
  prepared <- amp_network_prepare(ctx, params)
  metadata <- data.frame(phyloseq::sample_data(ctx$ps), check.names = FALSE)
  metadata <- metadata[rownames(prepared$transformed), , drop = FALSE]
  groups <- unique(as.character(metadata$Group))
  group1 <- param_chr(params, "network_group1", "")
  group2 <- param_chr(params, "network_group2", "")
  if (!nzchar(group1) || !nzchar(group2)) {
    if (length(groups) != 2) {
      stop("metadata包含两个以上分组时，必须指定network_group1和network_group2。")
    }
    group1 <- groups[[1]]
    group2 <- groups[[2]]
  }
  if (!all(c(group1, group2) %in% groups) || identical(group1, group2)) {
    stop("network_group1和network_group2必须对应数据中两个不同的实际分组。")
  }
  x1 <- prepared$transformed[as.character(metadata$Group) == group1, , drop = FALSE]
  x2 <- prepared$transformed[as.character(metadata$Group) == group2, , drop = FALSE]
  if (min(nrow(x1), nrow(x2)) < 10) {
    stop("组间网络比较要求所选每组至少有10个独立样本。")
  }
  association1 <- amp_network_associations(x1, params, prepared$correlation_method, allow_empty = TRUE)
  association2 <- amp_network_associations(x2, params, prepared$correlation_method, allow_empty = TRUE)
  summary1 <- amp_network_graph_summary(
    association1$edges, colnames(prepared$transformed),
    hub_quantile = param_num(params, "network_hub_quantile", 0.95)
  )
  summary2 <- amp_network_graph_summary(
    association2$edges, colnames(prepared$transformed),
    hub_quantile = param_num(params, "network_hub_quantile", 0.95)
  )

  edge_key <- function(edges) {
    if (!nrow(edges)) return(character())
    paste(pmin(edges$from, edges$to), pmax(edges$from, edges$to), sep = "::")
  }
  keys1 <- edge_key(association1$edges)
  keys2 <- edge_key(association2$edges)
  hubs1 <- summary1$nodes$node[summary1$nodes$is_hub]
  hubs2 <- summary2$nodes$node[summary2$nodes$is_hub]
  jaccard <- function(a, b) {
    union_n <- length(union(a, b))
    if (!union_n) return(1)
    length(intersect(a, b)) / union_n
  }
  overlap <- data.frame(
    group1 = group1, group2 = group2,
    edge_jaccard = jaccard(keys1, keys2), hub_jaccard = jaccard(hubs1, hubs2),
    community_adjusted_rand = amp_adjusted_rand(summary1$nodes$community, summary2$nodes$community),
    stringsAsFactors = FALSE
  )

  global1 <- summary1$global
  global2 <- summary2$global
  metric_names <- setdiff(colnames(global1), "nodes")
  global_comparison <- data.frame(
    metric = metric_names,
    group1_value = vapply(metric_names, function(name) as.numeric(global1[[name]][[1]]), numeric(1)),
    group2_value = vapply(metric_names, function(name) as.numeric(global2[[name]][[1]]), numeric(1)),
    stringsAsFactors = FALSE
  )
  global_comparison$difference_group2_minus_group1 <- global_comparison$group2_value - global_comparison$group1_value

  node_comparison <- merge(
    summary1$nodes[, c("node", "degree", "strength", "betweenness", "closeness", "eigenvector", "community", "is_hub")],
    summary2$nodes[, c("node", "degree", "strength", "betweenness", "closeness", "eigenvector", "community", "is_hub")],
    by = "node", suffixes = c(paste0("_", group1), paste0("_", group2)), all = TRUE
  )
  node_comparison$degree_difference <- node_comparison[[paste0("degree_", group2)]] - node_comparison[[paste0("degree_", group1)]]
  node_comparison$eigenvector_difference <- node_comparison[[paste0("eigenvector_", group2)]] - node_comparison[[paste0("eigenvector_", group1)]]

  pairs <- association1$all_edges[, c("from", "to", "association"), drop = FALSE]
  colnames(pairs)[3] <- "association_group1"
  pair2 <- association2$all_edges[, c("from", "to", "association"), drop = FALSE]
  colnames(pair2)[3] <- "association_group2"
  differential <- merge(pairs, pair2, by = c("from", "to"), all = TRUE)
  differential$difference_group2_minus_group1 <- differential$association_group2 - differential$association_group1
  z1 <- atanh(pmin(pmax(differential$association_group1, -0.999999), 0.999999))
  z2 <- atanh(pmin(pmax(differential$association_group2, -0.999999), 0.999999))
  z_stat <- (z2 - z1) / sqrt(1 / (nrow(x1) - 3) + 1 / (nrow(x2) - 3))
  differential$p_value <- 2 * stats::pnorm(-abs(z_stat))
  differential$q_value <- stats::p.adjust(differential$p_value, method = "BH")
  differential$test_note <- if (identical(prepared$correlation_method, "spearman")) {
    "Fisher z approximation; exploratory for Spearman correlations"
  } else {
    "Fisher z comparison of independent correlations"
  }
  differential$selected_group1 <- edge_key(differential) %in% keys1
  differential$selected_group2 <- edge_key(differential) %in% keys2
  differential$significant <- differential$q_value <= param_num(params, "network_diff_q_cutoff", 0.05) &
    abs(differential$difference_group2_minus_group1) >= param_num(params, "network_diff_min", 0.2)
  differential <- differential[order(differential$q_value, -abs(differential$difference_group2_minus_group1)), , drop = FALSE]

  permutations <- max(param_int(params, "network_permutations", 99), 0)
  permutation_table <- data.frame()
  if (permutations > 0) {
    observed_diff <- global_comparison$difference_group2_minus_group1
    names(observed_diff) <- global_comparison$metric
    labels <- c(rep(group1, nrow(x1)), rep(group2, nrow(x2)))
    combined <- rbind(x1, x2)
    set.seed(param_int(params, "seed", 20260812))
    null_diffs <- matrix(NA_real_, nrow = permutations, ncol = length(metric_names), dimnames = list(NULL, metric_names))
    for (i in seq_len(permutations)) {
      permuted <- sample(labels, replace = FALSE)
      perm1 <- amp_network_associations(combined[permuted == group1, , drop = FALSE], params,
                                        prepared$correlation_method, allow_empty = TRUE)
      perm2 <- amp_network_associations(combined[permuted == group2, , drop = FALSE], params,
                                        prepared$correlation_method, allow_empty = TRUE)
      prop1 <- amp_network_graph_summary(perm1$edges, colnames(combined),
                                         param_num(params, "network_hub_quantile", 0.95))$global
      prop2 <- amp_network_graph_summary(perm2$edges, colnames(combined),
                                         param_num(params, "network_hub_quantile", 0.95))$global
      null_diffs[i, ] <- vapply(metric_names, function(name) as.numeric(prop2[[name]][[1]] - prop1[[name]][[1]]), numeric(1))
    }
    permutation_table <- data.frame(
      metric = metric_names,
      observed_difference = as.numeric(observed_diff[metric_names]),
      permutation_p_value = vapply(metric_names, function(name) {
        values <- null_diffs[, name]
        values <- values[is.finite(values)]
        if (!length(values) || !is.finite(observed_diff[[name]])) return(NA_real_)
        (1 + sum(abs(values) >= abs(observed_diff[[name]]))) / (1 + length(values))
      }, numeric(1)),
      permutations = permutations, stringsAsFactors = FALSE
    )
    permutation_table$q_value <- stats::p.adjust(permutation_table$permutation_p_value, method = "BH")
    global_comparison <- merge(global_comparison, permutation_table[, c("metric", "permutation_p_value", "q_value")], by = "metric", all.x = TRUE)
  }

  union_edges <- rbind(association1$edges, association2$edges)
  if (nrow(union_edges)) union_edges <- union_edges[!duplicated(edge_key(union_edges)), , drop = FALSE]
  union_graph <- igraph::graph_from_data_frame(
    union_edges, directed = FALSE,
    vertices = data.frame(name = colnames(prepared$transformed), stringsAsFactors = FALSE)
  )
  if (igraph::ecount(union_graph)) igraph::E(union_graph)$weight <- union_edges$weight
  shared_layout <- amp_network_layout(union_graph, param_int(params, "seed", 20260812))
  plot1 <- amp_network_plot_data(summary1, shared_layout, group1)
  plot2 <- amp_network_plot_data(summary2, shared_layout, group2)
  node_plot <- rbind(plot1$nodes, plot2$nodes)
  edge_plot <- rbind(plot1$edges, plot2$edges)
  p_compare <- ggplot2::ggplot()
  if (nrow(edge_plot)) {
    p_compare <- p_compare + ggplot2::geom_segment(
      data = edge_plot,
      ggplot2::aes(x, y, xend = xend, yend = yend, color = association, linewidth = weight), alpha = 0.6
    )
  }
  p_compare <- p_compare +
    ggplot2::geom_point(
      data = node_plot,
      ggplot2::aes(x, y, size = pmax(degree, 1), shape = is_hub, fill = factor(community)),
      color = "grey20", stroke = 0.3
    ) +
    ggplot2::geom_text(
      data = node_plot[node_plot$is_hub, , drop = FALSE],
      ggplot2::aes(x, y, label = node), nudge_y = 0.08, size = 2.7, check_overlap = TRUE
    ) +
    ggplot2::facet_wrap(~group) +
    ggplot2::scale_color_gradient2(low = "#3465a4", mid = "grey85", high = "#c13a35", midpoint = 0) +
    ggplot2::scale_linewidth(range = c(0.3, 1.4), guide = "none") +
    ggplot2::scale_shape_manual(values = c("FALSE" = 21, "TRUE" = 23)) +
    ggplot2::guides(fill = "none") + ggplot2::theme_void() +
    ggplot2::labs(title = "组成型网络组间比较（共享布局）", size = "Degree", shape = "Hub节点")

  plot_global <- global_comparison[is.finite(global_comparison$difference_group2_minus_group1), , drop = FALSE]
  p_global <- ggplot2::ggplot(plot_global, ggplot2::aes(
    stats::reorder(metric, difference_group2_minus_group1), difference_group2_minus_group1,
    fill = difference_group2_minus_group1 > 0
  )) + ggplot2::geom_col() + ggplot2::coord_flip() +
    ggplot2::scale_fill_manual(values = c("FALSE" = "#3465a4", "TRUE" = "#c13a35"), guide = "none") +
    ggplot2::labs(title = paste(group2, "-", group1), x = NULL, y = "网络拓扑指标差值") + theme_nature()

  top_diff <- head(differential, 30)
  top_diff$edge <- paste(top_diff$from, top_diff$to, sep = " -- ")
  p_diff <- ggplot2::ggplot(top_diff, ggplot2::aes(
    difference_group2_minus_group1, stats::reorder(edge, difference_group2_minus_group1),
    color = significant
  )) + ggplot2::geom_point(size = 2.5) +
    ggplot2::scale_color_manual(values = c("FALSE" = "grey65", "TRUE" = "#c13a35")) +
    ggplot2::labs(title = "差异关联", x = paste(group2, "-", group1), y = NULL,
                  color = "FDR与效应阈值") + theme_nature()

  method_table <- data.frame(
    group1 = group1, group1_samples = nrow(x1), group2 = group2, group2_samples = nrow(x2),
    taxonomic_rank = prepared$rank, transform = prepared$method,
    association = prepared$correlation_method,
    association_test = if (identical(prepared$correlation_method, "spearman")) {
      "Spearman相关的t近似检验（探索性）"
    } else {
      "Pearson相关的t检验"
    },
    edge_threshold = param_num(params, "cor_cutoff", 0.5),
    edge_fdr = param_num(params, "network_q_cutoff", 0.05),
    global_permutations = permutations,
    differential_test = if (identical(prepared$correlation_method, "spearman")) {
      "Fisher z近似检验（Spearman时仅作探索性证据）"
    } else {
      "独立相关系数的Fisher z检验"
    },
    interpretation_boundary = "拓扑差异和关联差异不能直接证明生态互作或因果关系",
    stringsAsFactors = FALSE
  )
  safe_group_name <- function(value) {
    cleaned <- gsub("[^A-Za-z0-9._-]+", "_", value)
    if (nzchar(cleaned)) cleaned else "group"
  }
  save_plot2(p_compare, ctx$out_dir, "network_comparison_shared_layout", width = 13, height = 7)
  save_plot2(p_global, ctx$out_dir, "network_global_property_differences", width = 9, height = 7)
  save_plot2(p_diff, ctx$out_dir, "network_differential_associations", width = 10, height = 9)
  amp_save_table(ctx, "comparison_method", method_table, "network_comparison_method.csv")
  amp_save_table(ctx, "network_filter", prepared$filter, "network_comparison_filter.csv")
  amp_save_table(ctx, "global_comparison", global_comparison, "network_global_comparison.csv")
  amp_save_table(ctx, "overlap", overlap, "network_overlap.csv")
  amp_save_table(ctx, "node_comparison", node_comparison, "network_node_comparison.csv")
  amp_save_table(ctx, "differential_edges", differential, "network_differential_associations.csv")
  amp_save_table(ctx, "edges_group1", association1$edges,
                 paste0("network_edges_", safe_group_name(group1), ".csv"))
  amp_save_table(ctx, "edges_group2", association2$edges,
                 paste0("network_edges_", safe_group_name(group2), ".csv"))
  if (nrow(permutation_table)) amp_save_table(ctx, "permutation_tests", permutation_table, "network_permutation_tests.csv")
  save_amp_workbook(ctx)
  invisible(list(method = method_table, global = global_comparison, overlap = overlap,
                 nodes = node_comparison, differential = differential))
}

amp_rcbray_native <- function(ctx, params = list()) {
  x <- amp_sample_matrix(ctx$ps, relative = FALSE)
  observed <- as.matrix(vegan::vegdist(x, method = "bray"))
  permutations <- param_int(params, "permutations", 99)
  null_distances <- array(NA_real_, dim = c(nrow(x), nrow(x), permutations))
  set.seed(param_int(params, "seed", 20260728))
  for (i in seq_len(permutations)) {
    shuffled <- t(apply(x, 1, sample))
    null_distances[, , i] <- as.matrix(vegan::vegdist(shuffled, method = "bray"))
  }
  pairs <- which(upper.tri(observed), arr.ind = TRUE)
  rc <- vapply(seq_len(nrow(pairs)), function(i) {
    values <- null_distances[pairs[i, 1], pairs[i, 2], ]
    2 * (mean(values < observed[pairs[i, 1], pairs[i, 2]]) +
           0.5 * mean(values == observed[pairs[i, 1], pairs[i, 2]])) - 1
  }, numeric(1))
  result <- data.frame(
    Sample1 = rownames(x)[pairs[, 1]], Sample2 = rownames(x)[pairs[, 2]],
    Bray = observed[pairs], RCbray = rc,
    Process = ifelse(rc > 0.95, "Dispersal limitation",
                     ifelse(rc < -0.95, "Homogenizing dispersal", "Undominated")),
    stringsAsFactors = FALSE
  )
  p <- ggplot2::ggplot(result, ggplot2::aes(RCbray, fill = Process)) +
    ggplot2::geom_histogram(bins = 25, color = "white") +
    ggplot2::geom_vline(xintercept = c(-0.95, 0.95), linetype = 2) +
    ggplot2::labs(title = "Modified Raup-Crick Bray-Curtis", x = "RCbray") +
    theme_nature()
  save_plot2(p, ctx$out_dir, "RCbray", width = 9, height = 7)
  amp_save_table(ctx, "RCbray", result, "RCbray.csv")
  save_amp_workbook(ctx)
  invisible(result)
}

amp_bnti_native <- function(ctx, params = list(), include_rcbray = FALSE) {
  if (is.null(phyloseq::phy_tree(ctx$ps, errorIfNULL = FALSE))) stop("A phylogenetic tree is required.")
  x <- amp_sample_matrix(ctx$ps, relative = FALSE)
  tree <- phyloseq::phy_tree(ctx$ps)
  x <- x[, tree$tip.label, drop = FALSE]
  cophenetic <- stats::cophenetic(tree)
  observed <- as.matrix(picante::comdistnt(x, cophenetic, abundance.weighted = TRUE))
  permutations <- param_int(params, "permutations", 99)
  null_values <- array(NA_real_, c(nrow(x), nrow(x), permutations))
  set.seed(param_int(params, "seed", 20260728))
  for (i in seq_len(permutations)) {
    permutation <- sample(seq_len(nrow(cophenetic)))
    permuted <- cophenetic[permutation, permutation]
    rownames(permuted) <- rownames(cophenetic)
    colnames(permuted) <- colnames(cophenetic)
    null_values[, , i] <- as.matrix(picante::comdistnt(x, permuted, abundance.weighted = TRUE))
  }
  pairs <- which(upper.tri(observed), arr.ind = TRUE)
  bnti <- vapply(seq_len(nrow(pairs)), function(i) {
    values <- null_values[pairs[i, 1], pairs[i, 2], ]
    spread <- stats::sd(values)
    if (!is.finite(spread) || spread == 0) return(NA_real_)
    (observed[pairs[i, 1], pairs[i, 2]] - mean(values)) / spread
  }, numeric(1))
  if (!any(is.finite(bnti))) {
    stop("betaNTI null distribution has zero variance; provide a resolved tree with non-uniform branch lengths.")
  }
  result <- data.frame(
    Sample1 = rownames(x)[pairs[, 1]], Sample2 = rownames(x)[pairs[, 2]],
    betaMNTD = observed[pairs], betaNTI = bnti,
    Estimable = is.finite(bnti),
    Process = ifelse(!is.finite(bnti), "Not estimable",
                     ifelse(bnti > 2, "Variable selection",
                            ifelse(bnti < -2, "Homogeneous selection", "Stochastic range"))),
    stringsAsFactors = FALSE
  )
  plot_result <- result[result$Estimable, , drop = FALSE]
  p <- ggplot2::ggplot(plot_result, ggplot2::aes(betaNTI, fill = Process)) +
    ggplot2::geom_histogram(bins = 25, color = "white") +
    ggplot2::geom_vline(xintercept = c(-2, 2), linetype = 2) +
    ggplot2::labs(title = "beta nearest-taxon index", x = "betaNTI") + theme_nature()
  save_plot2(p, ctx$out_dir, "betaNTI", width = 9, height = 7)
  amp_save_table(ctx, "betaNTI", result, "betaNTI.csv")
  amp_save_table(
    ctx,
    "betaNTI_summary",
    data.frame(
      total_pairs = nrow(result),
      estimable_pairs = nrow(plot_result),
      non_estimable_pairs = sum(!result$Estimable),
      permutations = permutations,
      stringsAsFactors = FALSE
    ),
    "betaNTI_summary.csv"
  )
  save_amp_workbook(ctx)
  if (include_rcbray) amp_rcbray_native(ctx, params)
  invisible(result)
}

amp_neutral_model_native <- function(ctx, params = list()) {
  x <- amp_sample_matrix(ctx$ps, relative = FALSE)
  total <- rowSums(x)
  relative <- sweep(x, 1, pmax(total, 1), "/")
  mean_abundance <- colMeans(relative)
  occurrence <- colMeans(x > 0)
  community_size <- mean(total)
  objective <- function(m) {
    alpha <- community_size * m * mean_abundance
    beta <- community_size * m * (1 - mean_abundance)
    predicted <- 1 - stats::pbeta(1 / community_size, pmax(alpha, 1e-8), pmax(beta, 1e-8))
    sum((occurrence - predicted)^2, na.rm = TRUE)
  }
  fit <- stats::optimize(objective, interval = c(1e-6, 1))
  migration <- fit$minimum
  alpha <- community_size * migration * mean_abundance
  beta <- community_size * migration * (1 - mean_abundance)
  predicted <- 1 - stats::pbeta(1 / community_size, pmax(alpha, 1e-8), pmax(beta, 1e-8))
  residuals <- occurrence - predicted
  sigma <- stats::sd(residuals)
  result <- data.frame(
    Feature = names(mean_abundance), MeanRelativeAbundance = mean_abundance,
    ObservedOccurrence = occurrence, PredictedOccurrence = predicted,
    Residual = residuals,
    Classification = ifelse(residuals > 1.96 * sigma, "Above neutral",
                            ifelse(residuals < -1.96 * sigma, "Below neutral", "Neutral")),
    stringsAsFactors = FALSE
  )
  goodness <- data.frame(
    migration = migration,
    R2 = 1 - sum(residuals^2) / sum((occurrence - mean(occurrence))^2),
    community_size = community_size,
    objective = fit$objective,
    stringsAsFactors = FALSE
  )
  p <- ggplot2::ggplot(result, ggplot2::aes(MeanRelativeAbundance, ObservedOccurrence,
                                            color = Classification)) +
    ggplot2::geom_point(alpha = 0.75) +
    ggplot2::geom_line(ggplot2::aes(y = PredictedOccurrence), color = "black", linewidth = 0.8) +
    ggplot2::scale_x_log10() +
    ggplot2::labs(title = sprintf("Sloan neutral model: m=%.3f, R2=%.3f",
                                  migration, goodness$R2),
                  x = "Mean relative abundance", y = "Occurrence frequency") +
    theme_nature()
  save_plot2(p, ctx$out_dir, "neutral_model", width = 9, height = 7)
  amp_save_table(ctx, "neutral_model", result, "neutral_model.csv")
  amp_save_table(ctx, "neutral_model_fit", goodness, "neutral_model_fit.csv")
  save_amp_workbook(ctx)
  invisible(list(features = result, fit = goodness))
}

amp_group_null_model_native <- function(ctx, params = list()) {
  x <- amp_sample_matrix(ctx$ps, relative = TRUE)
  group <- factor(phyloseq::sample_data(ctx$ps)$Group)
  distance <- as.matrix(vegan::vegdist(x, method = param_chr(params, "distance_method", "bray")))
  pair <- which(upper.tri(distance), arr.ind = TRUE)
  observed_within <- mean(distance[pair][group[pair[, 1]] == group[pair[, 2]]])
  observed_between <- mean(distance[pair][group[pair[, 1]] != group[pair[, 2]]])
  observed_effect <- observed_between - observed_within
  permutations <- param_int(params, "permutations", 999)
  set.seed(param_int(params, "seed", 20260728))
  null_effect <- replicate(permutations, {
    shuffled <- sample(group)
    within <- mean(distance[pair][shuffled[pair[, 1]] == shuffled[pair[, 2]]])
    between <- mean(distance[pair][shuffled[pair[, 1]] != shuffled[pair[, 2]]])
    between - within
  })
  result <- data.frame(
    observed_within = observed_within, observed_between = observed_between,
    observed_effect = observed_effect, null_mean = mean(null_effect),
    null_sd = stats::sd(null_effect),
    SES = (observed_effect - mean(null_effect)) / stats::sd(null_effect),
    permutation_p = (1 + sum(abs(null_effect) >= abs(observed_effect))) / (permutations + 1),
    permutations = permutations,
    stringsAsFactors = FALSE
  )
  null_table <- data.frame(iteration = seq_len(permutations), null_effect = null_effect)
  p <- ggplot2::ggplot(null_table, ggplot2::aes(null_effect)) +
    ggplot2::geom_histogram(bins = 30, fill = "#78a995", color = "white") +
    ggplot2::geom_vline(xintercept = observed_effect, color = "#ba3c35", linewidth = 1) +
    ggplot2::labs(title = "Group-label null model", x = "Between minus within distance") +
    theme_nature()
  save_plot2(p, ctx$out_dir, "group_null_model", width = 9, height = 7)
  amp_save_table(ctx, "null_model_summary", result, "null_model_summary.csv")
  amp_save_table(ctx, "null_model_distribution", null_table, "null_model_distribution.csv")
  save_amp_workbook(ctx)
  invisible(result)
}

amp_source_tracking_native <- function(ctx, params = list()) {
  relative <- amp_sample_matrix(ctx$ps, relative = TRUE)
  meta <- data.frame(phyloseq::sample_data(ctx$ps), check.names = FALSE)
  groups <- unique(as.character(meta$Group))
  sink_group <- param_chr(params, "sink_group", groups[length(groups)])
  source_groups <- param_vec(params, "source_groups", setdiff(groups, sink_group))
  source_groups <- intersect(source_groups, groups)
  if (!sink_group %in% groups || !length(source_groups)) {
    stop("Configured source and sink groups were not found.")
  }
  source_profiles <- do.call(rbind, lapply(source_groups, function(source) {
    colMeans(relative[meta$Group == source, , drop = FALSE])
  }))
  rownames(source_profiles) <- source_groups
  sink_ids <- rownames(meta)[meta$Group == sink_group]
  estimates <- do.call(rbind, lapply(sink_ids, function(sample_id) {
    target <- relative[sample_id, ]
    softmax <- function(z) {
      exp_z <- exp(z - max(z))
      exp_z / sum(exp_z)
    }
    objective <- function(z) {
      weights <- softmax(z)
      sum((target - as.numeric(weights %*% source_profiles))^2)
    }
    fit <- stats::optim(rep(0, length(source_groups)), objective, method = "BFGS")
    weights <- softmax(fit$par)
    data.frame(SampleID = sample_id, Source = source_groups, Contribution = weights,
               residual_sse = fit$value, stringsAsFactors = FALSE)
  }))
  p <- ggplot2::ggplot(estimates, ggplot2::aes(SampleID, Contribution, fill = Source)) +
    ggplot2::geom_col() +
    ggplot2::labs(
      title = paste("Constrained source contribution estimate for", sink_group),
      subtitle = "Nonnegative least-squares approximation; not the original FEAST algorithm",
      x = NULL, y = "Estimated contribution"
    ) + theme_nature() +
    ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 45, hjust = 1))
  save_plot2(p, ctx$out_dir, "source_tracking", width = 10, height = 7)
  amp_save_table(ctx, "source_tracking", estimates, "source_tracking.csv")
  save_amp_workbook(ctx)
  invisible(estimates)
}

init_amp_legacy_globals <- function(ps, params = list(), env = parent.frame()) {
  meta <- data.frame(phyloseq::sample_data(ps), check.names = FALSE)
  if (!"Group" %in% colnames(meta)) {
    group_col <- param_chr(params, "group_col", "Group")
    if (group_col %in% colnames(meta)) {
      meta$Group <- meta[[group_col]]
      phyloseq::sample_data(ps) <- phyloseq::sample_data(meta)
    }
  }

  axis_order <- unique(as.character(phyloseq::sample_data(ps)$Group))
  color_theme <- param_chr(params, "color_theme", "npg")
  if (!color_theme %in% c("npg", "nejm", "lancet")) color_theme <- "npg"

  assign("gnum", length(axis_order), envir = env)
  assign("axis_order", axis_order, envir = env)
  assign("col.g", get_group_cols_robust(axis_order, color_theme), envir = env)

  package.amp()
  theme_res <- theme_my(ps)
  assign("mytheme1", theme_res[[1]], envir = env)
  assign("mytheme2", theme_res[[2]], envir = env)
  assign("colset1", theme_res[[3]], envir = env)
  assign("colset2", theme_res[[4]], envir = env)
  assign("colset3", theme_res[[5]], envir = env)
  assign("colset4", theme_res[[6]], envir = env)

  invisible(ps)
}
