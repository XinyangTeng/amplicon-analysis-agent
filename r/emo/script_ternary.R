source(file.path(Sys.getenv("SCRIPT_DIR", "/project/yun/scripts"), "amp_common.R"), encoding = "UTF-8")
params <- read_amp_params()
ctx <- init_amp_context(params, "03_composition", "composition_results.xlsx")
ps.16s <- ctx$ps

group_col <- "Group"
taxrank <- param_chr(params, "tax_rank", "Genus")
groups <- unique(as.character(sample_data(ps.16s)[[group_col]]))
ternary_groups <- param_vec(params, "ternary_groups", character())
ternary_groups <- ternary_groups[ternary_groups %in% groups]
if (length(ternary_groups) < 3) ternary_groups <- groups[seq_len(min(3, length(groups)))]
if (length(ternary_groups) > 3) ternary_groups <- ternary_groups[1:3]
ps.16s <- subset_samples(ps.16s, Group %in% ternary_groups)
ps.16s <- prune_taxa(taxa_sums(ps.16s) > 0, ps.16s)
gnum <- length(unique(sample_data(ps.16s)[[group_col]]))

if (gnum < 3) {
  stop("Ternary plot requires at least 3 groups.")
}

if (TRUE) {
  otu <- as.data.frame(ggClusterNet::vegan_otu(ps.16s), check.names = FALSE)
  meta <- data.frame(sample_data(ps.16s), check.names = FALSE)
  if (all(rownames(meta) %in% rownames(otu))) {
    otu <- as.data.frame(t(as.matrix(otu)), check.names = FALSE)
  }
  groups3 <- unique(as.character(meta[[group_col]]))[1:3]
  group_means <- sapply(groups3, function(g) {
    rowMeans(otu[, rownames(meta)[as.character(meta[[group_col]]) == g], drop = FALSE], na.rm = TRUE)
  })
  group_means <- as.data.frame(group_means, check.names = FALSE)
  colnames(group_means) <- groups3
  group_means$taxa <- rownames(group_means)
  total <- rowSums(group_means[, groups3, drop = FALSE])
  dat <- group_means[total > 0, , drop = FALSE]
  total <- rowSums(dat[, groups3, drop = FALSE])
  dat[, groups3] <- sweep(dat[, groups3, drop = FALSE], 1, total, "/")
  dat <- dat[order(total, decreasing = TRUE), , drop = FALSE]
  dat <- head(dat, param_int(params, "top_n", 100))
  dat$x <- dat[[groups3[2]]] + 0.5 * dat[[groups3[3]]]
  dat$y <- sqrt(3) / 2 * dat[[groups3[3]]]
  p <- ggplot2::ggplot(dat, ggplot2::aes(x = x, y = y)) +
    ggplot2::geom_polygon(
      data = data.frame(x = c(0, 1, 0.5), y = c(0, 0, sqrt(3) / 2)),
      ggplot2::aes(x = x, y = y),
      fill = NA,
      color = "grey40",
      inherit.aes = FALSE
    ) +
    ggplot2::geom_point(size = 2, alpha = 0.75, color = "#2C7FB8") +
    ggplot2::annotate("text", x = c(0, 1, 0.5), y = c(-0.04, -0.04, sqrt(3) / 2 + 0.04), label = groups3) +
    ggplot2::coord_equal(clip = "off") +
    ggplot2::theme_void()
  p <- list(p)
}

save_plot2(p[[1]], ctx$out_dir, "15_ternary_plot", base_width = 30, base_height = 24)
write_sheet2(ctx$workbook, "15_ternary_data", dat)
save_amp_workbook(ctx)
save_preview_plot(p[[1]], width = 12, height = 10)

