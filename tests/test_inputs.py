from pathlib import Path

import pandas as pd

from amplicon_agent.inputs import inspect_inputs
from amplicon_agent.function_registry import get_function, list_functions
from amplicon_agent.function_specs import assess_context


DEMO = Path(__file__).parents[1] / "examples" / "demo"


def test_valid_demo(monkeypatch, tmp_path):
    monkeypatch.setenv("AMPLICON_WORKSPACE", str(DEMO.parent.parent))
    result = inspect_inputs(str(DEMO / "abundance.csv"), str(DEMO / "taxonomy.csv"), str(DEMO / "metadata.csv"), "Group")
    assert result.status == "ready"
    assert result.sample_count == 6
    assert result.feature_count == 12
    assert result.selected_taxonomy_rank == "Genus"


def test_transposed_abundance_is_detected(monkeypatch, tmp_path):
    root = tmp_path
    monkeypatch.setenv("AMPLICON_WORKSPACE", str(root))
    abundance = pd.read_csv(DEMO / "abundance.csv", index_col=0).T
    abundance.index.name = "SampleID"
    abundance.to_csv(root / "abundance.csv")
    (root / "taxonomy.csv").write_bytes((DEMO / "taxonomy.csv").read_bytes())
    (root / "metadata.csv").write_bytes((DEMO / "metadata.csv").read_bytes())
    result = inspect_inputs("abundance.csv", "taxonomy.csv", "metadata.csv", "Group")
    assert result.status == "warning"
    assert result.transpose_abundance is True


def test_negative_counts_are_blocked(monkeypatch, tmp_path):
    monkeypatch.setenv("AMPLICON_WORKSPACE", str(tmp_path))
    abundance = pd.read_csv(DEMO / "abundance.csv")
    abundance.iloc[0, 1] = -1
    abundance.to_csv(tmp_path / "abundance.csv", index=False)
    (tmp_path / "taxonomy.csv").write_bytes((DEMO / "taxonomy.csv").read_bytes())
    (tmp_path / "metadata.csv").write_bytes((DEMO / "metadata.csv").read_bytes())
    result = inspect_inputs("abundance.csv", "taxonomy.csv", "metadata.csv", "Group")
    assert result.status == "blocked"
    assert any("负数" in item for item in result.blockers)


def test_batch_and_ordered_gradient_design_is_summarized(monkeypatch, tmp_path):
    monkeypatch.setenv("AMPLICON_WORKSPACE", str(tmp_path))
    (tmp_path / "abundance.csv").write_bytes((DEMO / "abundance.csv").read_bytes())
    (tmp_path / "taxonomy.csv").write_bytes((DEMO / "taxonomy.csv").read_bytes())
    metadata = pd.read_csv(DEMO / "metadata.csv")
    metadata["Batch"] = ["categorical"] * 3 + ["gradient"] * 3
    metadata["Intensity"] = [None, None, None, 1, 2, 3]
    metadata.to_csv(tmp_path / "metadata.csv", index=False)
    result = inspect_inputs(
        "abundance.csv", "taxonomy.csv", "metadata.csv", "Group", "Batch", "Intensity"
    )
    assert result.status == "warning"
    assert set(result.design_summary["batches"]) == {"categorical", "gradient"}
    assert result.design_summary["batches"]["gradient"]["gradient_levels"] == [1.0, 2.0, 3.0]


def test_all_analysis_functions_are_registered_with_compatibility_status():
    functions = list_functions()
    assert len(functions) == 72
    assert all("function_id" in function for function in functions)
    assert all(function["display_name"] != function["function_id"] for function in functions)
    assert all(function["display_name"] != "待命名分析方法" for function in functions)
    assert all(function["description"] for function in functions)
    assert all(function["category_name"] for function in functions)
    assert get_function("script-alpha")["status"] == "verified"
    assert get_function("script-barplot")["status"] == "verified"
    assert get_function("script-alpha-pd")["status"] == "verified"
    assert get_function("script-alpha-pd")["specification"]["requires_tree"] is True
    assert any(item["name"] == "permutations" for item in get_function("script-bnti")["declared_parameters"])
    assert get_function("mantal-micro")["category"] == "beta_diversity"
    assert get_function("script-function-diff")["category"] == "functional_prediction"
    assert get_function("script-kegg-enrich")["specification"]["requires_pathway_annotation"] is True
    assert get_function("script-network-compositional")["category"] == "network"
    assert get_function("script-network-compare")["category"] == "network"
    assert get_function("script-network-compositional")["status"] == "verified"
    assert get_function("script-network-compare")["status"] == "conditional"
    assert get_function("script-ancombc2")["status"] == "verified"
    assert get_function("script-coda-pca")["category"] == "beta_diversity"
    assert get_function("script-gunifrac")["specification"]["requires_tree"] is True
    assert get_function("script-siamcat")["status"] == "conditional"
    assert get_function("script-spieceasi")["category"] == "network"
    assert any(
        item["name"] == "network_group1"
        for item in get_function("script-network-compare")["declared_parameters"]
    )


def test_network_comparison_requires_ten_samples_per_group():
    function = get_function("script-network-compare")
    insufficient = pd.DataFrame({"Group": ["A"] * 9 + ["B"] * 12})
    eligible = pd.DataFrame({"Group": ["A"] * 10 + ["B"] * 10})
    assert assess_context(function, insufficient)["eligible"] is False
    assert assess_context(function, eligible)["eligible"] is True


def test_package_backed_ml_and_network_methods_enforce_replication():
    insufficient = pd.DataFrame({"Group": ["A"] * 8 + ["B"] * 12})
    eligible = pd.DataFrame({"Group": ["A"] * 10 + ["B"] * 10})
    for function_id in ("script-siamcat", "script-splsda", "script-spieceasi", "script-wgcna"):
        function = get_function(function_id)
        assert assess_context(function, insufficient)["eligible"] is False
        assert assess_context(function, eligible)["eligible"] is True
