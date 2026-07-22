`%||%` <- function(x, y) if (is.null(x)) y else x

html_escape <- function(x) {
  x <- gsub("&", "&amp;", as.character(x), fixed = TRUE)
  x <- gsub("<", "&lt;", x, fixed = TRUE)
  gsub(">", "&gt;", x, fixed = TRUE)
}

warnings_html <- if (length(contract$warnings)) {
  paste0("<li>", html_escape(contract$warnings), "</li>", collapse = "")
} else "<li>None</li>"

beta_text <- if (isTRUE(beta_tests$skipped)) {
  html_escape(beta_tests$reason)
} else {
  sprintf("PERMANOVA R2=%.3f, p=%.4g; dispersion p=%.4g",
          beta_tests$permanova$R2, beta_tests$permanova$p_value,
          beta_tests$dispersion$p_value)
}

report_html <- paste0(
  "<!doctype html><html><head><meta charset='utf-8'><title>Amplicon analysis report</title>",
  "<style>body{font-family:Arial,'Microsoft YaHei',sans-serif;max-width:1000px;margin:40px auto;line-height:1.6;color:#18352a}h1,h2{color:#075f35}img{max-width:100%;border:1px solid #ddd}code{background:#eef5f0;padding:2px 5px}</style></head><body>",
  "<h1>Amplicon microbiome analysis report</h1><p><b>Plan ID:</b> <code>", html_escape(contract$plan_id), "</code></p>",
  "<h2>Data overview</h2><p>", nrow(sample_counts), " samples, ", ncol(sample_counts), " features; group column: ", html_escape(contract$group_column), ".</p>",
  "<h2>Input warnings</h2><ul>", warnings_html, "</ul>",
  "<h2>Methods</h2><p>Alpha: Observed, Shannon, Simpson. Beta: Bray-Curtis, PCoA, PERMANOVA and dispersion. Composition rank: ", html_escape(rank_name), ".</p>",
  "<h2>QC and alpha diversity</h2><img src='figures/alpha_diversity.png'><p>Values: <code>tables/alpha_diversity.csv</code>.</p>",
  "<h2>Beta diversity</h2><img src='figures/pcoa.png'><p>", beta_text, "</p>",
  "<h2>Community composition</h2><img src='figures/composition.png'><p>Top ", top_n, " taxa; remaining taxa are merged as Other.</p>",
  "<h2>Sanity checks</h2><p>Status: <b>", validation$status, "</b>. Interpret results with the experimental design, sample size and dispersion test.</p>",
  "<h2>Conclusion boundaries</h2><ul><li>Descriptive patterns and qualified group differences can be reported.</li><li>This analysis does not establish causality or mechanism.</li><li>Significance does not replace effect-size and data-quality assessment.</li></ul>",
  "<h2>File index</h2><p>See <code>run_manifest.json</code> and <code>validation.json</code>.</p></body></html>"
)
writeLines(report_html, file.path(output_dir, "report.html"), useBytes = TRUE)
