from pathlib import Path

import pandas as pd

from amplicon_agent.inputs import inspect_inputs
from amplicon_agent.module_registry import get_module, list_modules


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
    assert any("negative" in item for item in result.blockers)


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


def test_all_team_modules_are_registered_with_compatibility_status():
    modules = list_modules()
    assert len(modules) == 55
    assert get_module("script-alpha")["status"] == "verified"
    assert get_module("script-barplot")["status"] == "verified"
    assert get_module("script-alpha-pd")["status"] == "conditional"
    assert get_module("script-alpha-pd")["specification"]["requires_tree"] is True
    assert any(item["name"] == "permutations" for item in get_module("script-bnti")["declared_parameters"])
