from pathlib import Path

import pandas as pd

from amplicon_agent.inputs import inspect_inputs


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

