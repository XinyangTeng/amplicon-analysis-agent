# -*- coding: utf-8 -*-

suppressPackageStartupMessages({
  required_packages <- c("jsonlite", "phyloseq", "tidyverse", "Biostrings", "ggsci",
                         "openxlsx", "ape", "picante", "minpack.lm", "Hmisc", "fs")
  missing_required <- required_packages[!vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing_required)) stop("Missing required EMO packages: ", paste(missing_required, collapse = ", "))
  for (pkg_name in required_packages) library(pkg_name, character.only = TRUE)
  for (pkg_name in c("ggClusterNet", "EasyMicroPlot", "EasyStat", "TOmicsVis")) {
    if (requireNamespace(pkg_name, quietly = TRUE)) library(pkg_name, character.only = TRUE)
  }
  library(parallel)
})

load_amp_legacy_packages <- function() {
  package_candidates <- c("EasyMultiOmics", "EasyMicroPlot", "EasyStat", "TOmicsVis", "ggClusterNet")
  for (pkg in package_candidates) {
    if (requireNamespace(pkg, quietly = TRUE)) {
      suppressPackageStartupMessages(library(pkg, character.only = TRUE))
    }
  }

  invisible(TRUE)
}

load_amp_legacy_packages()

`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0 || (length(x) == 1 && is.na(x))) y else x
}

read_amp_params <- function(param_file = "params.json") {
  normalize_amp_params <- function(params) {
    aliases <- list(
      group_col = c("group_column"),
      color_theme = c("color_palette"),
      top_n = c("comp_top_n", "biomarker_top_n", "function_top_n", "module_top_n", "ml_top_variance_n", "beta_feature_top_n"),
      filter_top_n = c("feature_top_n", "top_n", "ml_top_variance_n", "beta_feature_top_n"),
      optimal = c("ml_top_variance_n", "biomarker_top_n", "top_n"),
      folds = c("ml_cv_folds"),
      repnum = c("ml_cv_folds"),
      p_cutoff = c("da_p_cutoff", "net_p_cutoff", "module_p_cutoff"),
      cor_cutoff = c("net_cor_cutoff"),
      distance_method = c("beta_distance_metric", "assembly_distance"),
      dist = c("comp_distance_metric", "distance_method"),
      hcluter_method = c("comp_cluster_method", "beta_cluster_method"),
      cuttree = c("comp_cutree_k", "beta_cutree_k"),
      heatnum = c("heatmap_feature_n"),
      tax_rank = c(
        "comp_tax_level", "da_tax_level", "lefse_tax_level", "net_tax_level",
        "assembly_tax_level", "ml_tax_level", "module_tax_level", "alpha_tax_level"
      ),
      tax_level = c("da_tax_level", "comp_tax_level", "lefse_tax_level", "module_tax_level"),
      fill_rank = c("net_tax_level", "comp_tax_level"),
      layout_net = c("net_layout"),
      permutations = c("beta_permutations", "assembly_null_model_runs", "module_permutations"),
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

init_amp_context <- function(params = list(), result_subdir, workbook_name) {
  ps <- load_amp_phyloseq(params)
  amplicon_path <- "."
  out_dir <- file.path(amplicon_path, result_subdir)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  workbook_path <- file.path(out_dir, workbook_name)
  workbook <- if (file.exists(workbook_path)) {
    openxlsx::loadWorkbook(workbook_path)
  } else {
    openxlsx::createWorkbook()
  }

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
  ggplot2::ggsave("preview.png", plot = plot, width = width, height = height, dpi = 150, limitsize = FALSE, bg = "white")
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
  ggplot2::ggsave(png_path, plot = plot, width = width, height = height, dpi = dpi, limitsize = FALSE, bg = "white")
  ggplot2::ggsave(pdf_path, plot = plot, width = width, height = height, limitsize = FALSE, bg = "white")
  if (!file.exists("preview.png")) {
    ggplot2::ggsave("preview.png", plot = plot, width = width, height = height, dpi = 150, limitsize = FALSE, bg = "white")
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

amp_note_table <- function(module, message, suggestion = "") {
  data.frame(
    module = module,
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
