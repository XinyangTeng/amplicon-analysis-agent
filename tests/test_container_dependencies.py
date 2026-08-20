from __future__ import annotations

from pathlib import Path

from amplicon_agent.function_registry import list_functions


ROOT = Path(__file__).resolve().parents[1]


def test_native_build_dependencies_cover_advanced_r_packages() -> None:
    dockerfile = (ROOT / "Dockerfile").read_text(encoding="utf-8")
    for package in ("cmake", "curl", "libcairo2-dev", "fonts-noto-cjk"):
        assert package in dockerfile
    assert "ARG RUST_VERSION=1.85.1" in dockerfile
    assert "rustup-init" in dockerfile
    assert 'installed_rust="$(rustc --version' in dockerfile
    assert "AMPLICON_R_ROOT=/app/r" in dockerfile
    assert 'AMPLICON_PLOT_FONT="Noto Sans CJK SC"' in dockerfile


def test_bioc_dependent_cran_packages_are_installed_after_bioc() -> None:
    installer = (ROOT / "r" / "install_dependencies.R").read_text(encoding="utf-8")
    cran_batch = installer[
        installer.index("cran <- c(") : installer.index("install_cran(cran)")
    ]
    assert '"breakaway"' not in cran_batch
    assert '"WGCNA"' not in cran_batch

    final_cran_install = 'install_cran(c("breakaway", "WGCNA"), attempts = 3L)'
    assert final_cran_install in installer
    assert 'install_cran_version("ggpicrust2", "2.5.12")' in installer
    assert installer.index(final_cran_install) > installer.index(
        'stop("Bioconductor packages still missing:'
    )


def test_source_archive_fallbacks_are_not_required_from_bioconductor() -> None:
    installer = (ROOT / "r" / "install_dependencies.R").read_text(encoding="utf-8")
    bioc_batch = installer[installer.index("bioc <- c(") : installer.index("for (attempt")]
    assert '"microbiomeMarker"' not in bioc_batch
    assert '"SpiecEasi"' not in bioc_batch
    assert '"ANCOMBC"' not in bioc_batch
    for revision in (
        "a70510f9f1d7f896dddfce57f8217bb8de59cf72",
        "6eabb1b0fff0271d3dc27e463a87546cba03a82f",
        "81fc814b62676c1e371aa91a2202fe9da1834e80",
        "66fc685c97bea7303009582dbffbd2138556e1bf",
    ):
        assert revision in installer
    assert "Tax4Fun2_1.1.5.tar.gz" in installer
    assert "remotes::install_url" in installer
    assert "remotes::install_github" not in installer


def test_r_dependencies_use_cacheable_install_phases() -> None:
    dockerfile = (ROOT / "Dockerfile").read_text(encoding="utf-8")
    assert "AMPLICON_R_INSTALL_PHASE=cran" in dockerfile
    assert "AMPLICON_R_INSTALL_PHASE=bioc" in dockerfile
    assert "AMPLICON_R_INSTALL_PHASE=final" in dockerfile


def test_clarabel_is_pinned_for_ubuntu_rust_compatibility() -> None:
    installer = (ROOT / "r" / "install_dependencies.R").read_text(encoding="utf-8")
    assert 'install_cran_version("clarabel", "0.11.2")' in installer
    assert 'install_cran_version("CVXR", "1.8.2")' in installer
    assert 'install_cran_version("rbiom", "2.2.1")' in installer
    assert installer.index('install_cran_version("clarabel"') < installer.index(
        'install_cran_version("CVXR"'
    )
    assert "utils::compareVersion(current, version) == 0L" in installer


def test_spieceasi_uses_cxx14_source_compatibility_patch() -> None:
    installer = (ROOT / "r" / "install_dependencies.R").read_text(encoding="utf-8")
    assert 'cxx_std = "CXX14"' in installer
    assert "remotes::install_local" in installer
    assert "CXX_STD" in installer
    assert "CXX11" in installer


def test_every_declared_function_package_is_checked_in_the_image() -> None:
    checker = (ROOT / "r" / "check_dependencies.R").read_text(encoding="utf-8")
    declared = {
        package
        for function in list_functions()
        for package in function.get("packages", [])
    }
    missing = sorted(package for package in declared if f'"{package}"' not in checker)
    assert missing == []


def test_runtime_scripts_do_not_call_removed_legacy_helpers() -> None:
    scripts = {
        "script_alpha.R": "MuiKwWlx2",
        "script_alpha_PD.R": "MuiKwWlx2",
        "script_barplot.R": "barMainplot.micro",
        "script_deseq2.R": "DESep2Super.micro",
        "script_rarefaction.R": "alpha.rare.line.micro",
    }
    for filename, removed_helper in scripts.items():
        content = (ROOT / "r" / "functions" / filename).read_text(encoding="utf-8")
        assert removed_helper not in content

    common = (ROOT / "r" / "functions" / "amp_common.R").read_text(encoding="utf-8")
    assert "amp_alpha_tests <- function" in common
    assert "device = grDevices::cairo_pdf" in common
    assert "device = grDevices::png" in common


def test_shared_result_workbooks_are_loaded_instead_of_overwritten() -> None:
    for filename in (
        "script_alpha.R",
        "script_alpha_PD.R",
        "script_rarefaction.R",
        "script_barplot.R",
        "script_heatmap.R",
        "ggflower.micro.R",
    ):
        content = (ROOT / "r" / "functions" / filename).read_text(encoding="utf-8")
        assert "open_amp_workbook(" in content
        assert "openxlsx::createWorkbook()" not in content


def test_bnti_plot_filters_non_estimable_pairs_but_keeps_audit_counts() -> None:
    common = (ROOT / "r" / "functions" / "amp_common.R").read_text(encoding="utf-8")
    assert "Estimable = is.finite(bnti)" in common
    assert "plot_result <- result[result$Estimable" in common
    assert '"betaNTI_summary.csv"' in common
