from __future__ import annotations

from typing import Any

import pandas as pd


CATEGORY_SPECS: dict[str, dict[str, Any]] = {
    "alpha_diversity": {
        "purpose": "Estimate within-sample diversity and sampling coverage.",
        "parameters": {"alpha_metrics": "list[str]", "rarefy_method": "none|min|manual", "rarefy_depth": "int"},
        "minimum": "2 samples per group for inference; descriptive output otherwise",
    },
    "beta_diversity": {
        "purpose": "Measure between-sample dissimilarity, ordination, clustering, and group effects.",
        "parameters": {"distance_method": "str", "permutations": "int", "microtest_method": "adonis|anosim|MRPP"},
        "minimum": "2 groups with at least 2 samples each for categorical inference",
    },
    "composition": {
        "purpose": "Summarize taxonomic composition, overlap, and group-specific patterns.",
        "parameters": {"tax_rank": "str", "top_n": "int"},
        "minimum": "descriptive; plot-specific group requirements apply",
    },
    "differential_abundance": {
        "purpose": "Identify taxa or functions differing between replicated groups.",
        "parameters": {"tax_level": "str", "p_cutoff": "float", "adjust_p": "str", "lfc_cutoff": "float"},
        "minimum": "2 groups with at least 3 samples each",
    },
    "biomarker_ml": {
        "purpose": "Build exploratory classifiers and rank candidate biomarkers.",
        "parameters": {"optimal": "int", "folds": "int", "seed": "int"},
        "minimum": "2 groups with at least 10 samples each; nested validation recommended",
    },
    "network": {
        "purpose": "Construct and compare association networks and robustness properties.",
        "parameters": {"top_n": "int", "cor_cutoff": "float", "p_cutoff": "float", "random_times": "int"},
        "minimum": "at least 10 samples in a batch; 10 per group for group-network comparison",
    },
    "community_assembly": {
        "purpose": "Estimate neutral, null-model, source-tracking, and assembly-process signals.",
        "parameters": {"permutations": "int", "threads": "int", "min_taxa_sum": "float"},
        "minimum": "method-specific; phylogenetic methods require a tree",
    },
    "functional_prediction": {
        "purpose": "Analyze predicted KO functions and enrichment; not measured metagenomic function.",
        "parameters": {"ko_column": "int", "filter_top_n": "int"},
        "minimum": "KO annotation required; enrichment may require network access",
    },
    "other": {
        "purpose": "Specialized visualization or exploratory analysis.",
        "parameters": {},
        "minimum": "module-specific",
    },
}

TREE_MODULES = {"script-alpha-pd", "script-bnti", "script-bnti-rcbray"}
FUNCTION_MODULES = {"script-function-bubble", "script-function-diff", "script-kegg-enrich"}
SOURCE_TRACKING_MODULES = {"script-feast"}
TERNARY_MODULES = {"script-ternary"}
GROUP_NETWORK_MODULES = {"script-network-stability", "script-network-robustness"}


def specification(module_id: str, category: str) -> dict[str, Any]:
    base = dict(CATEGORY_SPECS[category])
    base["requires_tree"] = module_id in TREE_MODULES
    base["requires_ko_annotation"] = module_id in FUNCTION_MODULES
    base["requires_source_sink"] = module_id in SOURCE_TRACKING_MODULES
    base["requires_exactly_or_at_least_three_groups"] = module_id in TERNARY_MODULES
    base["batch_policy"] = "within_batch"
    return base


def assess_context(module: dict[str, Any], metadata: pd.DataFrame,
                   has_tree: bool = False, has_ko: bool = False,
                   source_sink_configured: bool = False) -> dict[str, Any]:
    module_id = str(module["module_id"])
    category = str(module["category"])
    group_col = "Group" if "Group" in metadata.columns else None
    if group_col is None:
        return {"eligible": False, "reason": "normalized Group column is unavailable"}
    counts = metadata[group_col].astype(str).value_counts()
    groups = int(len(counts))
    min_group = int(counts.min()) if groups else 0
    n_samples = int(len(metadata))

    if module_id in TREE_MODULES and not has_tree:
        return {"eligible": False, "reason": "phylogenetic tree is required"}
    if module_id in FUNCTION_MODULES and not has_ko:
        return {"eligible": False, "reason": "KO annotation is required"}
    if module_id in SOURCE_TRACKING_MODULES and not source_sink_configured:
        return {"eligible": False, "reason": "source and sink groups must be configured"}
    if module_id in TERNARY_MODULES and groups < 3:
        return {"eligible": False, "reason": "ternary analysis requires at least three groups"}
    if category == "differential_abundance" and (groups < 2 or min_group < 3):
        return {"eligible": False, "reason": "differential analysis requires two groups with at least three samples each"}
    if category == "biomarker_ml" and (groups < 2 or min_group < 10):
        return {"eligible": False, "reason": "machine learning requires at least ten samples per group"}
    if category == "network" and n_samples < 10:
        return {"eligible": False, "reason": "network analysis requires at least ten samples in the batch"}
    if module_id in GROUP_NETWORK_MODULES and min_group < 10:
        return {"eligible": False, "reason": "group network comparison requires at least ten samples per group"}
    if category == "beta_diversity" and module_id in {"script-microtest", "script-pair-microtest"} and (groups < 2 or min_group < 2):
        return {"eligible": False, "reason": "group test requires replicated groups"}
    return {"eligible": True, "reason": "requirements satisfied", "sample_count": n_samples,
            "group_count": groups, "minimum_group_size": min_group}
