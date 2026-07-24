from __future__ import annotations

import json
import os
import re
import secrets
import shutil
import subprocess
import uuid
from pathlib import Path

import pandas as pd

from .inputs import inspect_inputs
from .models import AnalysisContract, ApprovalResult, RunResult
from .security import secure_path, sha256_file, token_hash, workspace_root
from .store import PlanStore
from .module_registry import get_module, module_registry, SCRIPT_ROOT
from .module_specs import assess_context
from .report_builder import build_analysis_report


EXPECTED_OUTPUTS = [
    "analysis_contract.json", "run_manifest.json", "validation.json", "report.html",
    "report_data.json", "artifact_manifest.json",
    "tables/qc_summary.csv", "tables/alpha_diversity.csv", "tables/pcoa_coordinates.csv",
    "tables/composition_relative_abundance.csv", "figures/alpha_diversity.png",
    "tables/stratified_tests.json", "figures/pcoa.png", "figures/composition.png", "logs/r-analysis.log",
]


def r_subprocess_environment() -> dict[str, str]:
    """Return an R environment that does not pass POSIX-only locales on Windows."""
    env = os.environ.copy()
    if os.name == "nt":
        for name in list(env):
            if name == "LANG" or name.startswith("LC_"):
                env.pop(name, None)
    return env


class AgentService:
    def __init__(self, store: PlanStore | None = None) -> None:
        self.store = store or PlanStore()

    def inspect(self, abundance: str, taxonomy: str, metadata: str, group_column: str,
                batch_column: str | None = None, gradient_column: str | None = None) -> dict:
        return inspect_inputs(abundance, taxonomy, metadata, group_column, batch_column, gradient_column).model_dump()

    def prepare(self, abundance: str, taxonomy: str, metadata: str, group_column: str,
                modules: list[str] | None = None, permutations: int = 999, top_n: int = 10,
                batch_column: str | None = None, gradient_column: str | None = None,
                tree: str | None = None, representative_sequences: str | None = None,
                module_parameters: dict[str, object] | None = None) -> dict:
        inspection = inspect_inputs(abundance, taxonomy, metadata, group_column, batch_column, gradient_column)
        if tree:
            tree_path = secure_path(tree)
            inspection.files.tree = str(tree_path)
            inspection.file_hashes["tree"] = sha256_file(tree_path)
        if representative_sequences:
            sequence_path = secure_path(representative_sequences)
            inspection.files.representative_sequences = str(sequence_path)
            inspection.file_hashes["representative_sequences"] = sha256_file(sequence_path)
        selected_modules = modules or ["qc", "alpha", "beta", "composition"]
        baseline_modules = {"qc", "alpha", "beta", "composition"}
        registered_emo = {f"emo:{name}" for name in module_registry()}
        invalid = sorted(set(selected_modules) - baseline_modules - registered_emo)
        blockers = list(inspection.blockers)
        if invalid:
            blockers.append(f"Unsupported modules: {invalid}")
        for selected in selected_modules:
            if not selected.startswith("emo:"):
                continue
            module = get_module(selected.removeprefix("emo:"))
            if module["status"] == "blocked":
                blockers.append(f"EMO module {selected} is blocked: {module.get('notes', 'compatibility failure')}")
            elif module["status"] == "registered_untested":
                inspection.warnings.append(f"EMO module {selected} is registered but has not passed compatibility testing")
            elif module["status"] == "conditional":
                inspection.warnings.append(f"EMO module {selected} is conditionally available: {module.get('notes', '')}")
            spec = module.get("specification", {})
            if spec.get("requires_tree") and not tree:
                inspection.warnings.append(f"EMO module {selected} requires a phylogenetic tree and will be skipped with three-table input")
            if spec.get("requires_ko_annotation") and not any(
                str(column).lower() in {"ko", "koid", "kegg_orthology"}
                for column in inspection.taxonomy_columns
            ):
                inspection.warnings.append(f"EMO module {selected} requires KO annotation and will be skipped")
            if spec.get("requires_source_sink") and not (
                (module_parameters or {}).get("sink_group") and (module_parameters or {}).get("source_groups")
            ):
                inspection.warnings.append(f"EMO module {selected} requires explicit source/sink configuration and will be skipped")
        if not 9 <= permutations <= 9999:
            blockers.append("permutations must be between 9 and 9999")
        if not 1 <= top_n <= 50:
            blockers.append("top_n must be between 1 and 50")
        contract = AnalysisContract(
            plan_id=str(uuid.uuid4()),
            files=inspection.files,
            file_hashes=inspection.file_hashes,
            group_column=group_column,
            batch_column=batch_column,
            gradient_column=gradient_column,
            orientation=inspection.orientation,
            transpose_abundance=inspection.transpose_abundance,
            modules=selected_modules,
            parameters={
                "permutations": permutations,
                "top_n": top_n,
                "taxonomy_rank": inspection.selected_taxonomy_rank,
                "distance": "bray",
                "seed": 20260722,
                **(module_parameters or {}),
            },
            warnings=inspection.warnings,
            blockers=blockers,
            expected_outputs=EXPECTED_OUTPUTS + (["emo/emo_manifest.json"] if any(x.startswith("emo:") for x in selected_modules) else []),
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
            completed = subprocess.run(
                command, capture_output=True, text=True, encoding="utf-8",
                errors="replace", timeout=1800, check=False,
                env=r_subprocess_environment(),
            )
            log_path.write_text(completed.stdout + "\n--- STDERR ---\n" + completed.stderr, encoding="utf-8")
            if completed.returncode != 0:
                raise RuntimeError(f"R analysis failed with exit code {completed.returncode}")
            emo_modules = [item.removeprefix("emo:") for item in contract.modules if item.startswith("emo:")]
            if emo_modules:
                self._run_emo_modules(contract, run_dir, emo_modules, rscript)
            contract.status = "succeeded"
            (run_dir / "analysis_contract.json").write_text(
                contract.model_dump_json(indent=2), encoding="utf-8"
            )
            build_analysis_report(run_dir)
            self.store.save(contract)
            return RunResult(
                plan_id=plan_id, status="succeeded", run_directory=str(run_dir),
                report_path=str(run_dir / "report.html"), validation_path=str(run_dir / "validation.json"),
            )
        except Exception as exc:
            contract.status = "failed"
            contract.error = str(exc)
            (run_dir / "analysis_contract.json").write_text(
                contract.model_dump_json(indent=2), encoding="utf-8"
            )
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
        report_data = secure_path(Path(contract.run_directory) / "report_data.json")
        artifact_manifest = secure_path(Path(contract.run_directory) / "artifact_manifest.json")
        return {
            "plan_id": plan_id,
            "report_path": str(report),
            "report_uri": report.as_uri(),
            "report_data_path": str(report_data),
            "artifact_manifest_path": str(artifact_manifest),
        }

    def report_context(self, plan_id: str) -> dict:
        """Return validated, structured results for language-model interpretation."""
        validation = self.validate(plan_id)
        if validation["status"] != "pass":
            raise ValueError("Results must pass validation before interpretation")
        contract = self.store.load(plan_id)
        if not contract.run_directory:
            raise ValueError("Plan has not been run")
        report_data_path = secure_path(Path(contract.run_directory) / "report_data.json")
        return json.loads(report_data_path.read_text(encoding="utf-8"))

    @staticmethod
    def _verify_hashes(contract: AnalysisContract) -> None:
        for name, path_value in contract.files.model_dump().items():
            if path_value is None:
                continue
            path = secure_path(path_value)
            if sha256_file(path) != contract.file_hashes[name]:
                raise ValueError(f"Input changed after plan creation: {name}")

    @staticmethod
    def _run_emo_modules(contract: AnalysisContract, run_dir: Path,
                         module_ids: list[str], rscript: str) -> None:
        emo_root = run_dir / "emo"
        logs = emo_root / "logs"
        logs.mkdir(parents=True, exist_ok=True)
        params = dict(contract.parameters)
        params.update({
            "group_col": contract.group_column,
            "group_column": contract.group_column,
            "batch_column": contract.batch_column,
            "gradient_column": contract.gradient_column,
            "plot_dpi": 160,
        })
        metadata = pd.read_csv(contract.files.metadata, sep=None, engine="python", encoding="utf-8-sig")
        metadata[metadata.columns[0]] = metadata.iloc[:, 0].astype(str)
        if contract.batch_column:
            contexts = [(str(batch), frame.copy()) for batch, frame in metadata.groupby(contract.batch_column)]
        else:
            contexts = [("all_samples", metadata)]
        abundance = pd.read_csv(contract.files.abundance, sep=None, engine="python", encoding="utf-8-sig")
        abundance.iloc[:, 0] = abundance.iloc[:, 0].astype(str)
        if contract.transpose_abundance:
            abundance = abundance.set_index(abundance.columns[0]).T.reset_index()
            abundance.columns = ["FeatureID", *abundance.columns[1:]]
        taxonomy = pd.read_csv(contract.files.taxonomy, sep=None, engine="python", encoding="utf-8-sig")

        workspaces: list[tuple[str, Path, pd.DataFrame]] = []
        for context_name, context_meta in contexts:
            safe_context = re.sub(r"[^A-Za-z0-9._-]+", "_", context_name)
            workspace = emo_root / "batches" / safe_context
            workspace.mkdir(parents=True, exist_ok=True)
            source_sample_ids = context_meta.iloc[:, 0].astype(str).tolist()
            if "sample_name" in context_meta.columns:
                output_sample_ids = context_meta["sample_name"].astype(str).tolist()
            else:
                output_sample_ids = source_sample_ids
            missing = sorted(set(source_sample_ids) - set(map(str, abundance.columns[1:])))
            if missing:
                raise RuntimeError(f"Cannot create EMO batch workspace; missing samples: {missing}")
            context_abundance = abundance.loc[:, [abundance.columns[0], *source_sample_ids]].copy()
            context_abundance.columns = [context_abundance.columns[0], *output_sample_ids]
            context_abundance.to_csv(workspace / "otutab.txt", sep="\t", index=False)
            taxonomy.to_csv(workspace / "taxonomy.txt", sep="\t", index=False)
            if contract.files.tree:
                shutil.copy2(contract.files.tree, workspace / "otus.tree")
            if contract.files.representative_sequences:
                shutil.copy2(contract.files.representative_sequences, workspace / "otus.fa")
            context_meta = context_meta.copy()
            context_meta.insert(1, "source_sample_id", source_sample_ids)
            context_meta[context_meta.columns[0]] = output_sample_ids
            if "sample_name" in context_meta.columns:
                context_meta = context_meta.drop(columns=["sample_name"])
            context_meta.to_csv(workspace / "metadata.tsv", sep="\t", index=False)
            (workspace / "params.json").write_text(
                json.dumps(params, ensure_ascii=False, indent=2), encoding="utf-8"
            )
            normalized_meta = context_meta.copy()
            normalized_meta["Group"] = normalized_meta[contract.group_column].astype(str)
            workspaces.append((safe_context, workspace, normalized_meta))

        manifest: dict[str, object] = {"modules": {}, "contexts": [x[0] for x in workspaces], "status": "running"}
        failures: list[str] = []
        env = r_subprocess_environment()
        env["SCRIPT_DIR"] = str(SCRIPT_ROOT)
        for module_id in module_ids:
            module = get_module(module_id)
            script = SCRIPT_ROOT / str(module["script"])
            module_runs: dict[str, object] = {}
            for context_name, workspace, context_meta in workspaces:
                eligibility = assess_context(
                    module, context_meta,
                    has_tree=(workspace / "otus.tree").exists(),
                    has_ko=any(str(column).lower() in {"ko", "koid", "kegg_orthology"} for column in taxonomy.columns),
                    source_sink_configured=bool(params.get("sink_group") and params.get("source_groups")),
                )
                if not eligibility["eligible"]:
                    module_runs[context_name] = {
                        "status": "skipped", "reason": eligibility["reason"]
                    }
                    continue
                completed = subprocess.run(
                    [rscript, str(script)], cwd=workspace, env=env,
                    capture_output=True, text=True, encoding="utf-8", errors="replace",
                    timeout=1800, check=False,
                )
                log_name = f"{module_id}--{context_name}.log"
                (logs / log_name).write_text(
                    completed.stdout + "\n--- STDERR ---\n" + completed.stderr, encoding="utf-8"
                )
                module_runs[context_name] = {
                    "return_code": completed.returncode,
                    "status": "succeeded" if completed.returncode == 0 else "failed",
                    "log": f"logs/{log_name}",
                }
                if completed.returncode != 0:
                    failures.append(f"{module_id} ({context_name})")
            manifest["modules"][module_id] = {
                "script": module["script"], "category": module["category"], "runs": module_runs
            }
        manifest["status"] = "failed" if failures else "succeeded"
        manifest["files"] = [str(path.relative_to(emo_root)) for path in emo_root.rglob("*") if path.is_file()]
        (emo_root / "emo_manifest.json").write_text(
            json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        if failures:
            raise RuntimeError("EMO modules failed: " + ", ".join(failures))
