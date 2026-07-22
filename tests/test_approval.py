from pathlib import Path

import pytest

from amplicon_agent.service import AgentService


DEMO = Path(__file__).parents[1] / "examples" / "demo"


def prepare(monkeypatch, tmp_path):
    monkeypatch.setenv("AMPLICON_WORKSPACE", str(tmp_path))
    input_dir = tmp_path / "input"
    input_dir.mkdir()
    for name in ("abundance.csv", "taxonomy.csv", "metadata.csv"):
        (input_dir / name).write_bytes((DEMO / name).read_bytes())
    service = AgentService()
    contract = service.prepare("input/abundance.csv", "input/taxonomy.csv", "input/metadata.csv", "Group")
    return service, contract


def test_exact_confirmation_and_single_approval(monkeypatch, tmp_path):
    service, contract = prepare(monkeypatch, tmp_path)
    with pytest.raises(ValueError):
        service.approve(contract["plan_id"], "yes")
    approved = service.approve(contract["plan_id"], f"CONFIRM {contract['plan_id']}")
    assert approved.approval_token
    with pytest.raises(ValueError):
        service.approve(contract["plan_id"], f"CONFIRM {contract['plan_id']}")


def test_input_change_invalidates_approval(monkeypatch, tmp_path):
    service, contract = prepare(monkeypatch, tmp_path)
    path = tmp_path / "input" / "metadata.csv"
    path.write_text(path.read_text(encoding="utf-8") + "\n", encoding="utf-8")
    with pytest.raises(ValueError, match="Input changed"):
        service.approve(contract["plan_id"], f"CONFIRM {contract['plan_id']}")

