from __future__ import annotations

import argparse
import json
import os
from pathlib import Path

from amplicon_agent.function_registry import list_functions
from amplicon_agent.service import AgentService


parser = argparse.ArgumentParser(description="Run all registered functions on the comprehensive example")
parser.add_argument("--workspace", type=Path, default=Path(__file__).parents[1])
parser.add_argument("--output", type=Path, default=Path("function_smoke_summary.json"))
parser.add_argument("--functions", nargs="+", help="Optional function IDs; defaults to all registered functions")
args = parser.parse_args()
root = args.workspace.resolve()
os.environ["AMPLICON_WORKSPACE"] = str(root)

selected = args.functions or [item["function_id"] for item in list_functions()]
functions = ["qc", "alpha", "beta", "composition", *selected]
design = {
    "research_question": "Demonstrate group-associated microbiome changes",
    "sample_type": "synthetic rhizosphere soil",
    "experimental_unit": "independent sample",
    "controls": ["Control"],
    "treatments": ["Drought", "Salt"],
    "contrasts": ["Drought-Control", "Salt-Control"],
    "gradient_direction": "0=control, 2=strongest stress",
}
service = AgentService()
contract = service.prepare(
    "examples/comprehensive/abundance.csv",
    "examples/comprehensive/taxonomy.csv",
    "examples/comprehensive/metadata.csv",
    "Group",
    functions=functions,
    tree="examples/comprehensive/tree.nwk",
    representative_sequences="examples/comprehensive/representative_sequences.fasta",
    function_parameters={
        "sink_group": "Salt", "source_groups": ["Control", "Drought"],
        "case_group": "Drought", "control_group": "Control", "folds": 5,
        "permutations": 99, "threads": 2,
    },
    project_design=design,
    analysis_scope="full",
    allow_blocked_functions=True,
)
if contract["blockers"]:
    raise SystemExit(json.dumps(contract["blockers"], ensure_ascii=False))
approval = service.approve(contract["plan_id"], f"CONFIRM {contract['plan_id']}")
result = service.run(contract["plan_id"], approval.approval_token)
summary = {"plan_id": contract["plan_id"], "run": result.model_dump()}
if result.run_directory:
    manifest = Path(result.run_directory) / "functions" / "function_manifest.json"
    if manifest.exists():
        summary["function_manifest"] = json.loads(manifest.read_text(encoding="utf-8"))
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
print(json.dumps({"plan_id": contract["plan_id"], "status": result.status, "summary": str(args.output)}, ensure_ascii=False))
