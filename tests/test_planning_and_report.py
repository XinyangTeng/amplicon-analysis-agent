import base64
import json
from pathlib import Path

from amplicon_agent.report_builder import build_analysis_report
from amplicon_agent.models import AnalysisContract, InputFiles
from amplicon_agent.service import AgentService


DEMO = Path(__file__).parents[1] / "examples" / "demo"
ONE_PIXEL_PNG = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk"
    "YAAAAAYAAjCB0C8AAAAASUVORK5CYII="
)


def test_prepare_blocks_unconfirmed_design(monkeypatch, tmp_path):
    monkeypatch.setenv("AMPLICON_WORKSPACE", str(tmp_path))
    for name in ("abundance.csv", "taxonomy.csv", "metadata.csv"):
        (tmp_path / name).write_bytes((DEMO / name).read_bytes())
    contract = AgentService().prepare("abundance.csv", "taxonomy.csv", "metadata.csv", "Group")
    assert any("Project design must be confirmed" in item for item in contract["blockers"])


def test_report_embeds_only_png_and_interpretation(tmp_path):
    run = tmp_path / "run"
    (run / "figures").mkdir(parents=True)
    (run / "tables").mkdir()
    (run / "figures" / "same.png").write_bytes(ONE_PIXEL_PNG)
    (run / "figures" / "same.pdf").write_bytes(b"%PDF-1.4\n")
    (run / "analysis_contract.json").write_text(json.dumps({
        "plan_id": "p", "status": "succeeded", "files": {}, "file_hashes": {},
        "group_column": "Group", "functions": [], "warnings": [], "blockers": [],
        "project_design": {"research_question": "stress", "controls": ["CK"], "treatments": ["T"]},
    }), encoding="utf-8")
    (run / "validation.json").write_text('{"status":"pass","checks":{},"cautions":[]}', encoding="utf-8")
    (run / "interpretation.json").write_text(json.dumps({
        "project_summary": "针对胁迫效应的解释",
        "key_findings": [], "section_interpretations": {},
        "supported_conclusions": [], "unsupported_conclusions": [],
        "limitations": [], "next_steps": [],
    }, ensure_ascii=False), encoding="utf-8")
    result = build_analysis_report(run)
    assert result["figure_count"] == 1
    text = (run / "report.html").read_text(encoding="utf-8")
    assert "针对胁迫效应的解释" in text
    assert "<img" in text and "same.png" in text
    assert "src='figures/same.pdf'" not in text


def test_result_table_is_read_on_demand_and_stays_inside_run(monkeypatch, tmp_path):
    monkeypatch.setenv("AMPLICON_WORKSPACE", str(tmp_path))
    run = tmp_path / "runs" / "plan"
    table = run / "functions" / "result.csv"
    table.parent.mkdir(parents=True)
    table.write_text("feature,value\nA,1\nB,2\n", encoding="utf-8")
    (run / "validation.json").write_text('{"status":"pass"}', encoding="utf-8")
    contract = AnalysisContract(
        plan_id="plan",
        files=InputFiles(abundance="a", taxonomy="t", metadata="m"),
        file_hashes={},
        group_column="Group",
        orientation="feature_by_sample",
        transpose_abundance=False,
        functions=[],
        parameters={},
        warnings=[],
        blockers=[],
        expected_outputs=[],
        project_design={
            "research_question": "demo", "sample_type": "soil",
            "treatments": ["T"], "controls": ["C"],
        },
        status="succeeded",
        run_directory=str(run),
    )
    service = AgentService()
    service.store.save(contract)
    result = service.result_table("plan", "functions/result.csv", limit=1)
    assert result["row_count"] == 2
    assert result["rows"] == [{"feature": "A", "value": 1}]
    assert result["truncated"] is True
