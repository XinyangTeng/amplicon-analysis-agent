from __future__ import annotations

import json
import os
import secrets
import subprocess
import uuid
from pathlib import Path

from .inputs import inspect_inputs
from .models import AnalysisContract, ApprovalResult, RunResult
from .security import secure_path, sha256_file, token_hash, workspace_root
from .store import PlanStore


EXPECTED_OUTPUTS = [
    "analysis_contract.json", "run_manifest.json", "validation.json", "report.html",
    "tables/qc_summary.csv", "tables/alpha_diversity.csv", "tables/pcoa_coordinates.csv",
    "tables/composition_relative_abundance.csv", "figures/alpha_diversity.png",
    "figures/pcoa.png", "figures/composition.png", "logs/r-analysis.log",
]


class AgentService:
    def __init__(self, store: PlanStore | None = None) -> None:
        self.store = store or PlanStore()

    def inspect(self, abundance: str, taxonomy: str, metadata: str, group_column: str) -> dict:
        return inspect_inputs(abundance, taxonomy, metadata, group_column).model_dump()

    def prepare(self, abundance: str, taxonomy: str, metadata: str, group_column: str,
                modules: list[str] | None = None, permutations: int = 999, top_n: int = 10) -> dict:
        inspection = inspect_inputs(abundance, taxonomy, metadata, group_column)
        selected_modules = modules or ["qc", "alpha", "beta", "composition"]
        allowed = {"qc", "alpha", "beta", "composition"}
        invalid = sorted(set(selected_modules) - allowed)
        blockers = list(inspection.blockers)
        if invalid:
            blockers.append(f"Unsupported modules: {invalid}")
        if not 9 <= permutations <= 9999:
            blockers.append("permutations must be between 9 and 9999")
        if not 1 <= top_n <= 50:
            blockers.append("top_n must be between 1 and 50")
        contract = AnalysisContract(
            plan_id=str(uuid.uuid4()),
            files=inspection.files,
            file_hashes=inspection.file_hashes,
            group_column=group_column,
            orientation=inspection.orientation,
            transpose_abundance=inspection.transpose_abundance,
            modules=selected_modules,
            parameters={
                "permutations": permutations,
                "top_n": top_n,
                "taxonomy_rank": inspection.selected_taxonomy_rank,
                "distance": "bray",
                "seed": 20260722,
            },
            warnings=inspection.warnings,
            blockers=blockers,
            expected_outputs=EXPECTED_OUTPUTS,
        )
        self.store.save(contract)
        return contract.model_dump()

    def approve(self, plan_id: str, confirmation: str) -> ApprovalResult:
        contract = self.store.load(plan_id)
        if contract.blockers:
            raise ValueError(f"Plan is blocked: {contract.blockers}")
        if contract.approval_status != "pending":
            raise ValueError("Plan is not pending approval")
        expected = f"CONFIRM {plan_id}"
        if confirmation.strip() != expected:
            raise ValueError(f"Confirmation must exactly equal: {expected}")
        self._verify_hashes(contract)
        token = secrets.token_urlsafe(24)
        contract.approval_token_hash = token_hash(token)
        contract.approval_status = "approved"
        self.store.save(contract)
        return ApprovalResult(plan_id=plan_id, approval_token=token)

    def run(self, plan_id: str, approval_token: str) -> RunResult:
        contract = self.store.load(plan_id)
        if contract.approval_status != "approved" or not contract.approval_token_hash:
            raise ValueError("Plan has not been approved or token was already consumed")
        if not secrets.compare_digest(contract.approval_token_hash, token_hash(approval_token)):
            raise ValueError("Invalid approval token")
        self._verify_hashes(contract)
        run_dir = secure_path(Path("runs") / plan_id, must_exist=False)
        run_dir.mkdir(parents=True, exist_ok=False)
        contract.approval_status = "consumed"
        contract.approval_token_hash = None
        contract.status = "running"
        contract.run_directory = str(run_dir)
        self.store.save(contract)
        (run_dir / "analysis_contract.json").write_text(contract.model_dump_json(indent=2), encoding="utf-8")

        script = Path(__file__).resolve().parents[2] / "r" / "run_analysis.R"
        rscript = os.environ.get("RSCRIPT_BIN", "Rscript")
        log_dir = run_dir / "logs"
        log_dir.mkdir(parents=True, exist_ok=True)
        log_path = log_dir / "r-analysis.log"
        command = [rscript, str(script), str(run_dir / "analysis_contract.json"), str(run_dir)]
        try:
            completed = subprocess.run(command, capture_output=True, text=True, timeout=1800, check=False)
            log_path.write_text(completed.stdout + "\n--- STDERR ---\n" + completed.stderr, encoding="utf-8")
            if completed.returncode != 0:
                raise RuntimeError(f"R analysis failed with exit code {completed.returncode}")
            contract.status = "succeeded"
            self.store.save(contract)
            return RunResult(
                plan_id=plan_id, status="succeeded", run_directory=str(run_dir),
                report_path=str(run_dir / "report.html"), validation_path=str(run_dir / "validation.json"),
            )
        except Exception as exc:
            contract.status = "failed"
            contract.error = str(exc)
            self.store.save(contract)
            return RunResult(plan_id=plan_id, status="failed", run_directory=str(run_dir), error=str(exc))

    def status(self, plan_id: str) -> dict:
        return self.store.load(plan_id).model_dump()

    def validate(self, plan_id: str) -> dict:
        contract = self.store.load(plan_id)
        if not contract.run_directory:
            raise ValueError("Plan has not been run")
        run_dir = secure_path(contract.run_directory)
        missing = [item for item in contract.expected_outputs if not (run_dir / item).exists()]
        validation_path = run_dir / "validation.json"
        domain = json.loads(validation_path.read_text(encoding="utf-8")) if validation_path.exists() else {}
        return {"status": "pass" if not missing and domain.get("status") == "pass" else "fail",
                "missing_outputs": missing, "domain_validation": domain}

    def report(self, plan_id: str) -> dict:
        contract = self.store.load(plan_id)
        if not contract.run_directory:
            raise ValueError("Plan has not been run")
        report = secure_path(Path(contract.run_directory) / "report.html")
        return {"plan_id": plan_id, "report_path": str(report), "report_uri": report.as_uri()}

    @staticmethod
    def _verify_hashes(contract: AnalysisContract) -> None:
        for name, path_value in contract.files.model_dump().items():
            path = secure_path(path_value)
            if sha256_file(path) != contract.file_hashes[name]:
                raise ValueError(f"Input changed after plan creation: {name}")

