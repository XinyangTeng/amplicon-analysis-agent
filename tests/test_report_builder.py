import base64
import json
from pathlib import Path

from amplicon_agent.report_builder import build_analysis_report


ONE_PIXEL_PNG = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk"
    "YAAAAAYAAjCB0C8AAAAASUVORK5CYII="
)


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False), encoding="utf-8")


def test_report_builder_scans_new_module_outputs(tmp_path):
    run_dir = tmp_path / "run"
    (run_dir / "tables").mkdir(parents=True)
    figure_dir = run_dir / "emo" / "batches" / "drought" / "05_network"
    figure_dir.mkdir(parents=True)
    (figure_dir / "network_plot.png").write_bytes(ONE_PIXEL_PNG)
    (figure_dir / "network_nodes.csv").write_text("id,degree\nA,2\n", encoding="utf-8")
    (run_dir / "tables" / "qc_summary.csv").write_text(
        "sample_id,group,sequencing_depth,observed_features,zero_fraction\n"
        "S1,A,1000,20,0.8\nS2,B,2000,30,0.7\n",
        encoding="utf-8",
    )
    write_json(
        run_dir / "analysis_contract.json",
        {
            "schema_version": "1.2",
            "plan_id": "demo-plan",
            "status": "succeeded",
            "files": {"abundance": "input/abundance.csv"},
            "file_hashes": {"abundance": "abc"},
            "group_column": "Group",
            "batch_column": "Batch",
            "gradient_column": None,
            "modules": ["qc", "emo:script-network"],
            "parameters": {"seed": 1},
            "warnings": [],
            "blockers": [],
        },
    )
    write_json(
        run_dir / "validation.json",
        {"status": "pass", "checks": {"finite_alpha": True}, "cautions": []},
    )
    write_json(
        run_dir / "tables" / "stratified_tests.json",
        {"skipped": True, "reason": "demo"},
    )
    write_json(
        run_dir / "emo" / "emo_manifest.json",
        {
            "status": "succeeded",
            "contexts": ["drought"],
            "modules": {
                "script-network": {
                    "script": "script_network.R",
                    "category": "network",
                    "runs": {"drought": {"status": "succeeded"}},
                }
            },
        },
    )

    result = build_analysis_report(run_dir)

    assert result["figure_count"] == 1
    html = (run_dir / "report.html").read_text(encoding="utf-8")
    assert "emo/batches/drought/05_network/network_plot.png" in html
    assert "drought · 网络分析" in html
    data = json.loads((run_dir / "report_data.json").read_text(encoding="utf-8"))
    assert data["generator"]["llm_generated"] is False
    assert data["validation"]["status"] == "pass"
    assert data["artifacts"]["figures"][0]["path"].endswith("network_plot.png")
    manifest = json.loads((run_dir / "artifact_manifest.json").read_text(encoding="utf-8"))
    indexed = {item["path"] for item in manifest["files"]}
    assert "report.html" in indexed
    assert "report_data.json" in indexed
    assert "artifact_manifest.json" not in indexed
