source(file.path(Sys.getenv("SCRIPT_DIR", "/project/yun/scripts"), "amp_common.R"), encoding = "UTF-8")
params <- read_amp_params()
ctx <- init_amp_context(params, "04_differential", "differential_results.xlsx")
ps.16s <- ctx$ps

top_n <- param_int(params, "filter_top_n", 500)
tax_level <- param_chr(params, "tax_level", "OTU")

res <- tryCatch(
  DESep2Super.micro(
    ps = ps.16s %>% ggClusterNet::filter_OTU_ps(top_n),
    group = "Group",
    artGroup = NULL,
    j = tax_level
  ),
  error = function(original_error) {
    message("EasyMultiOmics DESeq2 wrapper failed; using native DESeq2 fallback: ", conditionMessage(original_error))
    suppressPackageStartupMessages(library(DESeq2))
    ps_use <- ps.16s %>% ggClusterNet::filter_OTU_ps(top_n)
    count_matrix <- as(phyloseq::otu_table(ps_use), "matrix")
    if (!phyloseq::taxa_are_rows(ps_use)) count_matrix <- t(count_matrix)
    storage.mode(count_matrix) <- "integer"
    count_matrix <- count_matrix[rowSums(count_matrix) > 0, , drop = FALSE]
    sample_table <- data.frame(phyloseq::sample_data(ps_use), check.names = FALSE)
    sample_table$Group <- factor(sample_table$Group)
    dds <- DESeqDataSetFromMatrix(countData = count_matrix, colData = sample_table, design = ~ Group)
    dds <- estimateSizeFactors(dds)
    dds <- tryCatch(
      estimateDispersions(dds, quiet = TRUE),
      error = function(e) {
        message("DESeq2 dispersion curve fallback: ", conditionMessage(e))
        dds <- estimateDispersionsGeneEst(dds, quiet = TRUE)
        dispersions(dds) <- mcols(dds)$dispGeneEst
        dds
      }
    )
    dds <- nbinomWaldTest(dds, quiet = TRUE)
    groups <- levels(sample_table$Group)
    contrasts <- combn(groups, 2, simplify = FALSE)
    result_tables <- lapply(contrasts, function(pair) {
      result <- as.data.frame(results(dds, contrast = c("Group", pair[2], pair[1])))
      result$ASV_ID <- rownames(result)
      result$contrast <- paste(pair[2], "vs", pair[1])
      result[, c("ASV_ID", "contrast", setdiff(names(result), c("ASV_ID", "contrast"))), drop = FALSE]
    })
    dat <- dplyr::bind_rows(result_tables)
    first_contrast <- dat[dat$contrast == unique(dat$contrast)[1], , drop = FALSE]
    p <- ggplot2::ggplot(first_contrast, ggplot2::aes(log2FoldChange, -log10(pmax(padj, 1e-300)))) +
      ggplot2::geom_point(alpha = 0.55, na.rm = TRUE) + ggplot2::theme_bw() +
      ggplot2::labs(title = paste("DESeq2", unique(first_contrast$contrast)[1]), y = "-log10 adjusted p")
    list(p, dat)
  }
)

p <- res[[1]]
if (is.list(p)) p <- p[[1]]
dat <- res[[2]]

save_plot2(p, ctx$out_dir, "26_DESeq2_plot1", width = 10, height = 8)
save_preview_plot(p, width = 10, height = 8)
write_sheet2(ctx$workbook, "26_DESeq2_results", dat)
save_amp_workbook(ctx)

