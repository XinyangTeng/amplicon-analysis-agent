# -*- coding: utf-8 -*-

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
    Process = ifelse(bnti > 2, "Variable selection",
                     ifelse(bnti < -2, "Homogeneous selection", "Stochastic range")),
    stringsAsFactors = FALSE
  )
  p <- ggplot2::ggplot(result, ggplot2::aes(betaNTI, fill = Process)) +
    ggplot2::geom_histogram(bins = 25, color = "white") +
    ggplot2::geom_vline(xintercept = c(-2, 2), linetype = 2) +
    ggplot2::labs(title = "beta nearest-taxon index", x = "betaNTI") + theme_nature()
  save_plot2(p, ctx$out_dir, "betaNTI", width = 9, height = 7)
  amp_save_table(ctx, "betaNTI", result, "betaNTI.csv")
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
