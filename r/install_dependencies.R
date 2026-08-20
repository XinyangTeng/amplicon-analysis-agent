cran_mirror <- Sys.getenv(
  "CRAN_MIRROR",
  unset = "https://mirrors.tuna.tsinghua.edu.cn/CRAN/"
)
bioconductor_mirror <- Sys.getenv(
  "BIOCONDUCTOR_MIRROR",
  unset = "https://bioconductor.posit.co"
)
options(
  repos = c(CRAN = cran_mirror),
  timeout = max(600, getOption("timeout", 60))
)
if (nzchar(bioconductor_mirror)) {
  options(BioC_mirror = bioconductor_mirror)
}

install_phase <- tolower(Sys.getenv("AMPLICON_R_INSTALL_PHASE", unset = "all"))
valid_phases <- c("all", "cran", "bioc", "final")
if (!install_phase %in% valid_phases) {
  stop(
    "AMPLICON_R_INSTALL_PHASE must be one of: ",
    paste(valid_phases, collapse = ", ")
  )
}
run_phase <- function(phase) install_phase %in% c("all", phase)

install_cran <- function(packages, attempts = 3L) {
  remaining <- packages[!vapply(packages, requireNamespace, logical(1), quietly = TRUE)]
  for (attempt in seq_len(attempts)) {
    if (!length(remaining)) break
    message(
      "CRAN install attempt ", attempt, "/", attempts,
      " from ", cran_mirror, ": ", paste(remaining, collapse = ", ")
    )
    try(
      install.packages(
        remaining,
        Ncpus = max(1, min(4, parallel::detectCores() - 1))
      ),
      silent = FALSE
    )
    remaining <- remaining[
      !vapply(remaining, requireNamespace, logical(1), quietly = TRUE)
    ]
    if (length(remaining) && attempt < attempts) Sys.sleep(10 * attempt)
  }
  if (length(remaining)) {
    stop("CRAN packages still missing: ", paste(remaining, collapse = ", "))
  }
}

install_cran_version <- function(package, version, attempts = 3L) {
  installed_version <- function() {
    package_matrix <- utils::installed.packages()
    if (!package %in% rownames(package_matrix)) return(NA_character_)
    unname(package_matrix[package, "Version"])
  }
  version_matches <- function() {
    current <- installed_version()
    !is.na(current) && utils::compareVersion(current, version) == 0L
  }
  for (attempt in seq_len(attempts)) {
    if (version_matches()) break
    message(
      "Pinned CRAN install attempt ", attempt, "/", attempts,
      ": ", package, " ", version
    )
    try(
      remotes::install_version(
        package,
        version = version,
        repos = cran_mirror,
        upgrade = "never"
      ),
      silent = FALSE
    )
    if (!version_matches() && attempt < attempts) {
      Sys.sleep(10 * attempt)
    }
  }
  if (!version_matches()) {
    stop(
      "Pinned CRAN package still missing or wrong version: ",
      package, " ", version
    )
  }
}

cran <- c(
  "jsonlite", "ggplot2", "vegan", "tidyverse", "ggsci", "openxlsx", "ape",
  "picante", "minpack.lm", "Hmisc", "fs", "randomForest", "caret", "e1071",
  "glmnet", "rpart", "ipred", "ROCR", "ggpubr", "ggrepel", "patchwork",
  "reshape2", "igraph", "ggraph", "pulsar", "ggalluvial", "corncob",
  "GUniFrac", "zCompositions", "compositions",
  "robCompositions", "MicrobiomeStat", "microeco", "remotes",
  "agricolae", "ggvenn",
  # Install these before Bioconductor. They are compiled dependencies of
  # scater/CVXR and are unreliable when first discovered inside a parallel
  # BiocManager installation.
  "ggrastr", "highs"
)
if (run_phase("cran")) {
  install_cran(cran)
  # clarabel 0.11.2 provides the solver interface required by CVXR 1.8.2.
  # Its Cargo.lock v4 file is compiled with the Dockerfile's pinned Rust 1.85.
  install_cran_version("clarabel", "0.11.2")
  # ANCOMBC 2.12.1 was released against CVXR 1.8.x. CVXR 1.9 changed its
  # solver API again, so keep the validated version used by the host run.
  install_cran_version("CVXR", "1.8.2")
  # mia 1.18 imports rbiom::unifrac, which was removed in rbiom 3.1.
  install_cran_version("rbiom", "2.2.1")
  install_cran("BiocManager")
}
bioc <- c(
  "phyloseq", "Biostrings", "DESeq2", "edgeR", "ALDEx2",
  "Maaslin2", "maaslin3", "metagenomeSeq",
  "MicrobiotaProcess", "mixOmics", "SIAMCAT", "lefser",
  "impute", "preprocessCore", "microbiome", "mia"
)
if (run_phase("bioc")) {
  if (!requireNamespace("BiocManager", quietly = TRUE)) {
    stop("BiocManager is missing; run the cran phase first")
  }
  for (attempt in seq_len(3L)) {
    missing_bioc <- bioc[
      !vapply(bioc, requireNamespace, logical(1), quietly = TRUE)
    ]
    if (!length(missing_bioc)) break
    message(
      "Bioconductor install attempt ", attempt, "/3: ",
      paste(missing_bioc, collapse = ", ")
    )
    try(
      BiocManager::install(
        missing_bioc,
        ask = FALSE,
        update = FALSE,
        Ncpus = max(1, min(4, parallel::detectCores() - 1))
      ),
      silent = FALSE
    )
    if (attempt < 3L) Sys.sleep(10 * attempt)
  }
  missing_bioc <- bioc[
    !vapply(bioc, requireNamespace, logical(1), quietly = TRUE)
  ]
  if (length(missing_bioc)) {
    stop("Bioconductor packages still missing: ", paste(missing_bioc, collapse = ", "))
  }
}

# These CRAN packages depend on Bioconductor packages installed above.
# Keeping them in the first CRAN batch makes a clean Docker build fail before
# it ever reaches Bioconductor (breakaway -> phyloseq; WGCNA ->
# impute/preprocessCore).
if (run_phase("final")) {
  install_cran(c("breakaway", "WGCNA"), attempts = 3L)
  # Keep the version used by the validated host environment. The package is
  # available from the official CRAN archive and depends on packages from the
  # CRAN and Bioconductor phases above.
  install_cran_version("ggpicrust2", "2.5.12")
}

source_archives <- list(
  # Several authorized legacy plotting scripts import ggClusterNet directly.
  # Pin the exact version already validated in the host environment.
  ggClusterNet = list(
    version = "2.00",
    url = paste0(
      "https://github.com/taowenmicro/ggClusterNet/archive/",
      "a70510f9f1d7f896dddfce57f8217bb8de59cf72.tar.gz"
    )
  ),
  # Bioconductor 3.22 still serves ANCOMBC 2.12.0 as a Linux source tarball,
  # while the compatibility fixes are in the official 2.12.1 release commit.
  ANCOMBC = list(
    version = "2.12.1",
    url = paste0(
      "https://github.com/FrederickHuangLin/ANCOMBC/archive/",
      "6eabb1b0fff0271d3dc27e463a87546cba03a82f.tar.gz"
    )
  ),
  # These exact commits match the host environment used for method-contract
  # validation. Direct codeload URLs avoid GitHub's anonymous API rate limit.
  SpiecEasi = list(
    version = "2.0.1",
    url = paste0(
      "https://github.com/zdk123/SpiecEasi/archive/",
      "81fc814b62676c1e371aa91a2202fe9da1834e80.tar.gz"
    ),
    # The 2.0.1 source still requests C++11, while current RcppArmadillo
    # requires C++14. This changes only the compiler standard.
    cxx_std = "CXX14"
  ),
  microbiomeMarker = list(
    version = "1.13.2",
    url = paste0(
      "https://github.com/yiluheihei/microbiomeMarker/archive/",
      "66fc685c97bea7303009582dbffbd2138556e1bf.tar.gz"
    )
  ),
  Tax4Fun2 = list(
    version = "1.1.5",
    url = paste0(
      "https://zenodo.org/records/10035668/files/",
      "Tax4Fun2_1.1.5.tar.gz"
    )
  )
)

install_source_archive <- function(package, spec, attempts = 3L) {
  package_matrix <- utils::installed.packages()
  current <- if (package %in% rownames(package_matrix)) {
    unname(package_matrix[package, "Version"])
  } else {
    NA_character_
  }
  if (!is.na(current) && utils::compareVersion(current, spec$version) == 0L) {
    return(invisible(TRUE))
  }
  for (attempt in seq_len(attempts)) {
    message(
      "Source archive install attempt ", attempt, "/", attempts,
      ": ", package, " ", spec$version
    )
    try({
      if (is.null(spec$cxx_std)) {
        remotes::install_url(spec$url, upgrade = "never", dependencies = NA)
      } else {
        source_dir <- tempfile(paste0(package, "-source-"))
        dir.create(source_dir, recursive = TRUE)
        archive <- file.path(source_dir, paste0(package, ".tar.gz"))
        utils::download.file(spec$url, archive, mode = "wb", quiet = FALSE)
        extract_dir <- file.path(source_dir, "unpacked")
        dir.create(extract_dir)
        utils::untar(archive, exdir = extract_dir)
        descriptions <- list.files(
          extract_dir,
          pattern = "^DESCRIPTION$",
          recursive = TRUE,
          full.names = TRUE
        )
        matching_descriptions <- descriptions[vapply(
          descriptions,
          function(path) {
            value <- tryCatch(
              read.dcf(path, fields = "Package")[[1]],
              error = function(...) ""
            )
            identical(value, package)
          },
          logical(1)
        )]
        if (length(matching_descriptions) != 1L) {
          stop("Could not identify a unique source root for ", package)
        }
        package_root <- dirname(matching_descriptions[[1]])
        makevars_files <- file.path(
          package_root,
          "src",
          c("Makevars", "Makevars.in", "Makevars.win")
        )
        makevars_files <- makevars_files[file.exists(makevars_files)]
        if (!length(makevars_files)) {
          stop("No Makevars file found for the requested compiler patch")
        }
        for (makevars in makevars_files) {
          lines <- readLines(makevars, warn = FALSE)
          patched <- sub(
            "^([[:space:]]*CXX_STD[[:space:]]*=[[:space:]]*)CXX11([[:space:]]*)$",
            paste0("\\1", spec$cxx_std, "\\2"),
            lines
          )
          writeLines(patched, makevars, useBytes = TRUE)
        }
        remotes::install_local(
          package_root,
          upgrade = "never",
          dependencies = NA
        )
        unlink(source_dir, recursive = TRUE, force = TRUE)
      }
    }, silent = FALSE)
    package_matrix <- utils::installed.packages()
    current <- if (package %in% rownames(package_matrix)) {
      unname(package_matrix[package, "Version"])
    } else {
      NA_character_
    }
    if (!is.na(current) && utils::compareVersion(current, spec$version) == 0L) {
      return(invisible(TRUE))
    }
    if (attempt < attempts) Sys.sleep(10 * attempt)
  }
  stop("Source archive package still missing or wrong version: ", package)
}

if (run_phase("final")) {
  if (!requireNamespace("remotes", quietly = TRUE)) {
    stop("remotes is missing; run the cran phase first")
  }
  for (package_name in names(source_archives)) {
    install_source_archive(package_name, source_archives[[package_name]])
  }
}
