from __future__ import annotations

import json
from pathlib import Path

from .models import AnalysisContract
from .security import workspace_root


class PlanStore:
    def __init__(self) -> None:
        self.root = workspace_root() / ".amplicon-agent" / "plans"
        self.root.mkdir(parents=True, exist_ok=True)

    def path(self, plan_id: str) -> Path:
        if not plan_id.replace("-", "").isalnum():
            raise ValueError("Invalid plan ID")
        return self.root / f"{plan_id}.json"

    def save(self, contract: AnalysisContract) -> None:
        path = self.path(contract.plan_id)
        temp = path.with_suffix(".tmp")
        temp.write_text(contract.model_dump_json(indent=2), encoding="utf-8")
        temp.replace(path)

    def load(self, plan_id: str) -> AnalysisContract:
        data = json.loads(self.path(plan_id).read_text(encoding="utf-8"))
        return AnalysisContract.model_validate(data)

