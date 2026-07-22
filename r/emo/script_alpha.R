source(file.path(Sys.getenv("SCRIPT_DIR", "/project/yun/scripts"), "amp_common.R"), encoding = "UTF-8")
library(jsonlite)
library(phyloseq)
library(tidyverse)
library(Biostrings)
load_amp_legacy_packages()
library(ggClusterNet)
library(ggsci)       
library(openxlsx)
library(ape)
library(picante)
library(fs)

# 妤傛ê顕В鏂垮妫版粏澹婇悽鐔稿灇閸戣姤鏆?
get_group_cols_robust <- function (groups, palette = c("npg", "nejm", "lancet")) {
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
    pal_fun <- switch(palette, npg = ggsci::pal_npg("nrc"), nejm = ggsci::pal_nejm(), lancet = ggsci::pal_lancet())
    cols <- pal_fun(n_groups)
  }
  return(stats::setNames(cols, groups))
}

# ===================== 1. 閸欏倹鏆熺憴锝嗙€芥稉搴ｅ箚婢у啫鍨垫慨瀣 =====================

params <- read_amp_params()

group_col   <- param_chr(params, "group_col", "Group")
all.alpha   <- param_vec(params, "alpha_metrics", param_vec(params, "index_types", character()))
if (is.null(all.alpha) || length(all.alpha) == 0) {
  all.alpha <- c("Shannon", "Chao1", "Simpson", "Richness", "ACE", "Pielou")
}
# Older/cached forms submitted checkbox booleans instead of metric names.
# Treat that payload as the default selection so queued tasks can still run.
if (length(all.alpha) > 0 && all(toupper(as.character(all.alpha)) %in% c("TRUE", "FALSE", "ON", "1"))) {
  message("Alpha metric names were submitted as checkbox booleans; using default metrics.")
  all.alpha <- c("Shannon", "Chao1", "Simpson", "Richness", "ACE", "Pielou")
}
plot_ncol   <- param_int(params, "ncol", 4)
save_w      <- param_num(params, "plot_width", 10)
save_h      <- param_num(params, "plot_height", 8)
save_dpi    <- param_int(params, "plot_dpi", 300)
seed_value  <- param_int(params, "seed", 1234)

sig_method  <- param_chr(params, "alpha_sig_label", "abc")
color_theme <- param_chr(params, "color_theme", "npg")
if (!color_theme %in% c("npg", "aaas", "lancet", "nejm", "default")) color_theme <- "npg"

rarefy_method  <- param_chr(params, "rarefy_method", "none") # "min", "manual", "none"
rarefy_depth   <- param_int(params, "rarefy_depth", 0)
x_label        <- param_chr(params, "x_label", "Group")
exclude_groups <- param_vec(params, "exclude_groups", character())

message("--- Alpha diversity task parameters ---")
message("Group column: ", group_col)
message("Rarefaction method: ", rarefy_method, ifelse(rarefy_method == "manual", paste0(", depth: ", rarefy_depth), ""))
message("X label: ", x_label)
message("Indices: ", paste(all.alpha, collapse = ", "))
message("Facet columns: ", plot_ncol, ", color theme: ", color_theme)
message("Random seed: ", seed_value)
message("--------------------")

amplicon_path <- "."

# ===================== 2. 閺佺増宓侀崝鐘烘祰娑?phyloseq 閺嬪嫬缂?=====================

if (file.exists("ps.rds")) {
  ps.16s <- readRDS("ps.rds")
} else if (file.exists("otutab.txt") & file.exists("metadata.tsv")) {
  metadata = read.delim("./metadata.tsv", row.names = 1, stringsAsFactors = FALSE, check.names = FALSE)
  otutab   = read.delim("./otutab.txt", row.names = 1, check.names = FALSE)
  
  ps <- phyloseq(
    sample_data(metadata),
    otu_table(as.matrix(otutab), taxa_are_rows=TRUE)
  )
  
  if (file.exists("taxonomy.txt")) {
    taxonomy = read.table("./taxonomy.txt", row.names=1, header = TRUE, stringsAsFactors = FALSE)
    tax_mat <- as.matrix(taxonomy)
    tax_table(ps) <- tax_table(tax_mat)
  }
  
  if (file.exists("otus.tree")) {
    phy_tree(ps) <- read_tree("./otus.tree")
  }
  
  if (file.exists("otus.fa")) {
    rep <- readDNAStringSet("./otus.fa")
    ps <- merge_phyloseq(ps, rep)
  }
  
  saveRDS(ps, "ps.rds")
  ps.16s <- ps
} else {
  stop("Input data not found. Provide ps.rds or otutab.txt plus metadata.tsv.")
}

# ===================== 閺佺増宓佹潻鍥ㄦ姢娑撳孩濞婇獮?=====================

# 1. 閸撴棃娅庨幐鍥х暰閸掑棛绮?
if (!is.null(exclude_groups) && length(exclude_groups) > 0) {
  message("Exclude groups: ", paste(exclude_groups, collapse = ", "))
  keep_samples <- !(phyloseq::sample_data(ps.16s)[[group_col]] %in% exclude_groups)
  ps.16s <- phyloseq::prune_samples(keep_samples, ps.16s)
  # 濞撳懐鎮婄粚铏瑰⒖缁?  ps.16s <- phyloseq::prune_taxa(phyloseq::taxa_sums(ps.16s) > 0, ps.16s) 
}

# 2. 閹惰棄閽╃粵鏍殣
if (rarefy_method == "min") {
  min_depth <- min(phyloseq::sample_sums(ps.16s))
  message("Rarefaction: using minimum sample depth (", min_depth, ").")
  ps.16s <- phyloseq::rarefy_even_depth(ps.16s, sample.size = min_depth, rngseed = 123, replace = FALSE, trimOTUs = TRUE, verbose = FALSE)
  
} else if (rarefy_method == "manual") {
  message("Rarefaction: checking manual depth (", rarefy_depth, ").")
  keep_samples <- phyloseq::sample_sums(ps.16s) >= rarefy_depth
  dropped_num <- sum(!keep_samples)
  if (dropped_num > 0) {
    message("Warning: ", dropped_num, " samples are below manual rarefaction depth and were removed.")
    ps.16s <- phyloseq::prune_samples(keep_samples, ps.16s)
  }
  ps.16s <- phyloseq::rarefy_even_depth(ps.16s, sample.size = rarefy_depth, rngseed = 123, replace = FALSE, trimOTUs = TRUE, verbose = FALSE)
  
} else if (rarefy_method == "none") {
  message("Rarefaction: skipped.")
}

# 3. 闁插秵鏌婇幓鎰絿閸掑棛绮嶆穱鈩冧紖
group_data <- phyloseq::sample_data(ps.16s)[[group_col]]
if (is.null(group_data)) {
  stop(paste("Group column not found in metadata:", group_col))
}

gnum       <- length(unique(group_data))
axis_order <- unique(group_data)
col.g      <- get_group_cols_robust(axis_order, ifelse(color_theme %in% c("npg", "nejm", "lancet"), color_theme, "npg"))

package.amp()
res      <- theme_my(ps.16s)
mytheme1 <- res[[1]]


# ===================== 3. Alpha 婢舵碍鐗遍幀褍鍨庨弸?=====================

amplicon_alpha_path <- file.path(amplicon_path, "01_alpha_diversity")
dir.create(amplicon_alpha_path, recursive = TRUE, showWarnings = FALSE)
alpha_xlsx_path <- file.path(amplicon_alpha_path, "alpha_diversity_results.xlsx")
amplicon_alpha_wb <- openxlsx::createWorkbook()

set.seed(seed_value)
tab <- alpha.micro(ps = ps.16s, group = group_col)
metric_alias <- c(
  Simpson = "Inv_Simpson",
  Pielou = "Pielou_evenness",
  Evenness = "Pielou_evenness"
)
all.alpha <- vapply(all.alpha, function(metric) {
  if (metric %in% colnames(tab)) return(metric)
  alias <- if (metric %in% names(metric_alias)) metric_alias[[metric]] else NULL
  if (!is.null(alias) && alias %in% colnames(tab)) return(alias)
  metric
}, character(1))
all.alpha <- intersect(unique(all.alpha), colnames(tab))
if (length(all.alpha) == 0) {
  stop("No requested Alpha diversity index was found in alpha.micro output.")
}

sample_id <- rownames(tab)
if (is.null(sample_id) || length(sample_id) != nrow(tab) || identical(sample_id, as.character(seq_len(nrow(tab))))) {
  sample_id <- phyloseq::sample_names(ps.16s)
}

data <- cbind(
  data.frame(
    ID = sample_id,
    group = if (group_col %in% colnames(tab)) {
      tab[[group_col]]
    } else {
      as.character(group_data[match(sample_id, phyloseq::sample_names(ps.16s))])
    }
  ),
  tab[all.alpha]
)
data$ID <- as.character(data$ID)

target_cols <- 3:(2 + length(all.alpha))
result <- tryCatch(
  MuiKwWlx2(data = data, num = target_cols),
  error = function(e) {
    message("Statistical annotation failed; continuing without significance labels. Reason: ", conditionMessage(e))
    data.frame(
      index = all.alpha,
      status = "statistical annotation skipped",
      reason = conditionMessage(e),
      stringsAsFactors = FALSE
    )
  }
)

# -------------- 缂佹ê娴橀崺铏诡攨鐏炲倹鐎?--------------

# 鐎规矮绠熺紒鐔剁閻ㄥ嫰妲婚柌宥呭綌娑撳顣?
fix_overlap_theme <- ggplot2::theme(
  axis.text.x = ggplot2::element_text(angle = 45, hjust = 1, vjust = 1, color = "black")
)

if (!"status" %in% colnames(result)) {
  result1 <- FacetMuiPlotresultBox2(
    data     = data,
    num      = target_cols,
    result   = result,
    sig_show = sig_method,
    ncol     = plot_ncol
  )

  p1_1_base <- result1[[1]] +
    ggplot2::scale_x_discrete(limits = axis_order) +
    theme_nature() +
    fix_overlap_theme +
    ggplot2::labs(x = x_label) +
    ggplot2::guides(fill = guide_legend(title = NULL))

  res2 <- FacetMuiPlotresultBar(
    data     = data,
    num      = target_cols,
    result   = result,
    sig_show = sig_method,
    ncol     = plot_ncol
  )

  p1_2_base <- res2[[1]] +
    ggplot2::scale_x_discrete(limits = axis_order) +
    theme_nature() +
    fix_overlap_theme +
    ggplot2::labs(x = x_label) +
    ggplot2::guides(fill = guide_legend(title = NULL))
} else {
  plot_data <- tidyr::pivot_longer(data, cols = dplyr::all_of(all.alpha), names_to = "index", values_to = "value")
  plot_data$group <- factor(plot_data$group, levels = axis_order)

  p1_1_base <- ggplot2::ggplot(plot_data, ggplot2::aes(x = group, y = value, fill = group, color = group)) +
    ggplot2::geom_boxplot(width = 0.65, outlier.shape = NA, alpha = 0.75) +
    ggplot2::geom_jitter(width = 0.12, size = 1.8, alpha = 0.8) +
    ggplot2::facet_wrap(~ index, scales = "free_y", ncol = plot_ncol) +
    theme_nature() +
    fix_overlap_theme +
    ggplot2::labs(x = x_label, y = "Alpha diversity") +
    ggplot2::guides(fill = guide_legend(title = NULL), color = guide_legend(title = NULL))

  bar_data <- plot_data %>%
    dplyr::group_by(group, index) %>%
    dplyr::summarise(value = mean(value, na.rm = TRUE), se = stats::sd(value, na.rm = TRUE) / sqrt(dplyr::n()), .groups = "drop")

  p1_2_base <- ggplot2::ggplot(bar_data, ggplot2::aes(x = group, y = value, fill = group)) +
    ggplot2::geom_col(width = 0.68, alpha = 0.85) +
    ggplot2::geom_errorbar(ggplot2::aes(ymin = value - se, ymax = value + se), width = 0.2) +
    ggplot2::facet_wrap(~ index, scales = "free_y", ncol = plot_ncol) +
    theme_nature() +
    fix_overlap_theme +
    ggplot2::labs(x = x_label, y = "Mean alpha diversity") +
    ggplot2::guides(fill = guide_legend(title = NULL))
}


# -------------- color theme --------------

if (color_theme == "npg") {
  p1_1 <- p1_1_base + scale_fill_npg() + scale_color_npg()
  p1_2 <- p1_2_base + scale_fill_npg()
  
} else if (color_theme == "aaas") {
  p1_1 <- p1_1_base + scale_fill_aaas() + scale_color_aaas()
  p1_2 <- p1_2_base + scale_fill_aaas()
  
} else if (color_theme == "lancet") {
  p1_1 <- p1_1_base + scale_fill_lancet() + scale_color_lancet()
  p1_2 <- p1_2_base + scale_fill_lancet()
  
} else {
  p1_1 <- p1_1_base + ggplot2::scale_color_manual(values = col.g) + ggplot2::scale_fill_manual(values = col.g)
  p1_2 <- p1_2_base + ggplot2::scale_fill_manual(values = col.g)
}


# ===================== 4. 缂佹挻鐏夋潏鎾冲毉娑撳酣顣╃憴?=====================

ggplot2::ggsave("preview.png", plot = p1_1, width = save_w, height = save_h, dpi = 150, limitsize = FALSE, bg = "white")
message("Preview saved: preview.png")

save_plot2(p1_1, amplicon_alpha_path, "alpha_diversity_box", width = save_w, height = save_h, dpi = save_dpi)
save_plot2(p1_2, amplicon_alpha_path, "alpha_diversity_bar", width = save_w, height = save_h, dpi = save_dpi)

write_sheet2(amplicon_alpha_wb, "alpha_diversity_data", data)
write_sheet2(amplicon_alpha_wb, "alpha_diversity_stat", result)
openxlsx::saveWorkbook(amplicon_alpha_wb, alpha_xlsx_path, overwrite = TRUE)

message("Alpha diversity analysis completed.")

