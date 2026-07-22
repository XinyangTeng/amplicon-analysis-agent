from __future__ import annotations

import json
import os
import argparse
from pathlib import Path

from amplicon_agent.service import AgentService


parser = argparse.ArgumentParser(description="Run an approved local end-to-end analysis demo")
parser.add_argument("--workspace", type=Path)
parser.add_argument("--abundance", default="examples/demo/abundance.csv")
parser.add_argument("--taxonomy", default="examples/demo/taxonomy.csv")
parser.add_argument("--metadata", default="examples/demo/metadata.csv")
parser.add_argument("--group-column", default="Group")
parser.add_argument("--batch-column")
parser.add_argument("--gradient-column")
args = parser.parse_args()

root = Path(__file__).parents[1].resolve()
os.environ["AMPLICON_WORKSPACE"] = str((args.workspace or root).resolve())
service = AgentService()
contract = service.prepare(
    args.abundance, args.taxonomy, args.metadata, args.group_column,
    batch_column=args.batch_column, gradient_column=args.gradient_column
)
print(json.dumps(contract, ensure_ascii=False, indent=2))
if contract["blockers"]:
    raise SystemExit("Demo contract is blocked")
approval = service.approve(contract["plan_id"], f"CONFIRM {contract['plan_id']}")
result = service.run(contract["plan_id"], approval.approval_token)
print(result.model_dump_json(indent=2))
print(json.dumps(service.validate(contract["plan_id"]), ensure_ascii=False, indent=2))
