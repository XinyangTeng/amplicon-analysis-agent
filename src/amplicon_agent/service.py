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
from .models import AnalysisContract, AnalysisInterpretation, ApprovalResult, RunResult
from .security import secure_path, sha256_file, token_hash, workspace_root
from .store import PlanStore
from .function_registry import get_function, function_registry, FUNCTION_ROOT
from .function_specs import assess_context
from .report_builder import build_analysis_report
from .resource_limits import subprocess_limit_kwargs, subprocess_timeout_seconds
from .runtime_paths import R_ROOT


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
                functions: list[str] | None = None, permutations: int = 999, top_n: int = 10,
                batch_column: str | None = None, gradient_column: str | None = None,
                tree: str | None = None, representative_sequences: str | None = None,
                function_parameters: dict[str, object] | None = None,
                project_design: dict[str, object] | None = None,
                analysis_scope: str = "targeted",
                allow_blocked_functions: bool = False) -> dict:
        inspection = inspect_inputs(abundance, taxonomy, metadata, group_column, batch_column, gradient_column)
        if tree:
            tree_path = secure_path(tree)
            inspection.files.tree = str(tree_path)
            inspection.file_hashes["tree"] = sha256_file(tree_path)
        if representative_sequences:
            sequence_path = secure_path(representative_sequences)
            inspection.files.representative_sequences = str(sequence_path)
            inspection.file_hashes["representative_sequences"] = sha256_file(sequence_path)
        selected_functions = functions or ["qc", "alpha", "beta", "composition"]
        baseline_functions = {"qc", "alpha", "beta", "composition"}
        registered_functions = set(function_registry())
        invalid = sorted(set(selected_functions) - baseline_functions - registered_functions)
        blockers = list(inspection.blockers)
        design = project_design or {}
        required_design = ("research_question", "sample_type", "treatments", "controls")
        missing_design = [name for name in required_design if not design.get(name)]
        if missing_design:
            design_names = {
                "research_question": "研究问题",
                "sample_type": "样本类型",
                "treatments": "处理组",
                "controls": "对照或参照组",
            }
            blockers.append(
                "生成计划前必须确认实验设计；缺少："
                + "、".join(design_names.get(name, name) for name in missing_design)
            )
        if analysis_scope not in {"full", "targeted"}:
            blockers.append("分析范围 analysis_scope 只能选择 full 或 targeted")
        if invalid:
            blockers.append(f"不支持的分析函数：{invalid}")
        for selected in selected_functions:
            if selected in baseline_functions:
                continue
            function = get_function(selected)
            method_label = str(function["display_name"])
            if function["status"] == "blocked" and not allow_blocked_functions:
                blockers.append(f"分析方法“{method_label}”已被阻断：{function.get('notes', '兼容性检查失败')}")
            elif function["status"] == "blocked":
                inspection.warnings.append(
                    f"已为阻断方法“{method_label}”启用开发复测；不能用于正式分析"
                )
            elif function["status"] == "registered_untested":
                inspection.warnings.append(f"分析方法“{method_label}”尚未通过兼容性测试")
            elif function["status"] == "conditional":
                inspection.warnings.append(f"分析方法“{method_label}”需要满足附加条件：{function.get('notes', '')}")
            spec = function.get("specification", {})
            if spec.get("requires_tree") and not tree:
                inspection.warnings.append(f"分析方法“{method_label}”需要系统发育树；仅有三表时将跳过")
            if spec.get("requires_ko_annotation") and not any(
                str(column).lower() in {"ko", "koid", "kegg_orthology"}
                for column in inspection.taxonomy_columns
            ):
                inspection.warnings.append(f"分析方法“{method_label}”需要 KO 注释，将自动跳过")
            if spec.get("requires_pathway_annotation") and not any(
                str(column).lower() in {"pathway", "kegg_pathway", "pathway_id"}
                for column in inspection.taxonomy_columns
            ):
                inspection.warnings.append(
                    f"分析方法“{method_label}”需要 Pathway 注释，将自动跳过"
                )
            if spec.get("requires_source_sink") and not (
                (function_parameters or {}).get("sink_group") and (function_parameters or {}).get("source_groups")
            ):
                inspection.warnings.append(f"分析方法“{method_label}”需要明确的 source/sink 配置，将自动跳过")
        if not 9 <= permutations <= 9999:
            blockers.append("置换次数 permutations 必须在 9 到 9999 之间")
        if not 1 <= top_n <= 50:
            blockers.append("组成图 Top N 必须在 1 到 50 之间")
        contract = AnalysisContract(
            plan_id=str(uuid.uuid4()),
            files=inspection.files,
            file_hashes=inspection.file_hashes,
            group_column=group_column,
            batch_column=batch_column,
            gradient_column=gradient_column,
            project_design=design,
            analysis_scope=analysis_scope if analysis_scope in {"full", "targeted"} else "targeted",
            orientation=inspection.orientation,
            transpose_abundance=inspection.transpose_abundance,
            functions=selected_functions,
            parameters={
                "permutations": permutations,
                "top_n": top_n,
                "taxonomy_rank": inspection.selected_taxonomy_rank,
                "distance": "bray",
                "seed": 20260722,
                **(function_parameters or {}),
            },
            warnings=inspection.warnings,
            blockers=blockers,
            expected_outputs=EXPECTED_OUTPUTS + (
                ["functions/function_manifest.json"]
                if any(x not in baseline_functions for x in selected_functions)
                else []
            ),
        )
        self.store.save(contract)
        return contract.model_dump()

    def approve(self, plan_id: str, confirmation: str) -> ApprovalResult:
        contract = self.store.load(plan_id)
        if contract.blockers:
            raise ValueError(f"分析计划存在阻断项：{contract.blockers}")
        if contract.approval_status != "pending":
            raise ValueError("分析计划当前不处于等待审批状态")
        expected = f"CONFIRM {plan_id}"
        if confirmation.strip() != expected:
            raise ValueError(f"确认文本必须完全一致：{expected}")
        self._verify_hashes(contract)
        token = secrets.token_urlsafe(24)
        contract.approval_token_hash = token_hash(token)
        contract.approval_status = "approved"
        self.store.save(contract)
        return ApprovalResult(plan_id=plan_id, approval_token=token)

    def run(self, plan_id: str, approval_token: str) -> RunResult:
        contract = self.store.load(plan_id)
        if contract.approval_status != "approved" or not contract.approval_token_hash:
            raise ValueError("分析计划尚未审批，或审批码已经使用")
        if not secrets.compare_digest(contract.approval_token_hash, token_hash(approval_token)):
            raise ValueError("审批码无效")
        self._verify_hashes(contract)
        run_dir = secure_path(Path("runs") / plan_id, must_exist=False)
        run_dir.mkdir(parents=True, exist_ok=False)
        contract.approval_status = "consumed"
        contract.approval_token_hash = None
        contract.status = "running"
        contract.run_directory = str(run_dir)
        self.store.save(contract)
        (run_dir / "analysis_contract.json").write_text(contract.model_dump_json(indent=2), encoding="utf-8")

        script = R_ROOT / "run_analysis.R"
        rscript = os.environ.get("RSCRIPT_BIN", "Rscript")
        log_dir = run_dir / "logs"
        log_dir.mkdir(parents=True, exist_ok=True)
        log_path = log_dir / "r-analysis.log"
        command = [rscript, str(script), str(run_dir / "analysis_contract.json"), str(run_dir)]
        try:
            completed = subprocess.run(
                command, capture_output=True, text=True, encoding="utf-8",
                errors="replace", timeout=subprocess_timeout_seconds(), check=False,
                env=r_subprocess_environment(),
                **subprocess_limit_kwargs(),
            )
            log_path.write_text(completed.stdout + "\n--- STDERR ---\n" + completed.stderr, encoding="utf-8")
            if completed.returncode != 0:
                raise RuntimeError(f"R 分析失败，退出码：{completed.returncode}")
            function_ids = [
                item for item in contract.functions
                if item not in {"qc", "alpha", "beta", "composition"}
            ]
            if function_ids:
                self._run_analysis_functions(contract, run_dir, function_ids, rscript)
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
            raise ValueError("分析计划尚未运行")
        run_dir = secure_path(contract.run_directory)
        missing = [item for item in contract.expected_outputs if not (run_dir / item).exists()]
        pdf_without_png = [
            str(path.relative_to(run_dir))
            for path in run_dir.rglob("*.pdf")
            if not path.with_suffix(".png").exists()
        ]
        validation_path = run_dir / "validation.json"
        domain = json.loads(validation_path.read_text(encoding="utf-8")) if validation_path.exists() else {}
        return {
            "status": "pass" if not missing and not pdf_without_png and domain.get("status") == "pass" else "fail",
            "missing_outputs": missing,
            "pdf_without_png": pdf_without_png,
            "domain_validation": domain,
        }

    def report(self, plan_id: str) -> dict:
        contract = self.store.load(plan_id)
        if not contract.run_directory:
            raise ValueError("分析计划尚未运行")
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
            raise ValueError("结果必须通过自动校验后才能解读")
        contract = self.store.load(plan_id)
        if not contract.run_directory:
            raise ValueError("分析计划尚未运行")
        report_data_path = secure_path(Path(contract.run_directory) / "report_data.json")
        data = json.loads(report_data_path.read_text(encoding="utf-8"))
        artifacts = data.get("artifacts", {})
        compact_artifacts = {
            "counts": artifacts.get("counts", {}),
            "png_figures": [
                {"path": item.get("path"), "section": item.get("section"), "context": item.get("context")}
                for item in artifacts.get("figures", [])
            ],
            "result_tables": [
                item.get("path")
                for item in artifacts.get("files", [])
                if item.get("extension") in {".csv", ".tsv"}
            ],
        }
        return {
            "schema_version": data.get("schema_version"),
            "contract": data.get("contract"),
            "validation": data.get("validation"),
            "qc_summary": data.get("qc_summary"),
            "statistical_results": data.get("statistical_results"),
            "function_execution": data.get("function_execution"),
            "artifacts": compact_artifacts,
            "interpretation": data.get("interpretation"),
            "interpretation_policy": data.get("interpretation_policy"),
        }

    def result_table(self, plan_id: str, relative_path: str, limit: int = 50) -> dict:
        """Read one selected result table on demand instead of expanding every table into context."""
        if not 1 <= limit <= 200:
            raise ValueError("读取行数 limit 必须在 1 到 200 之间")
        validation = self.validate(plan_id)
        if validation["status"] != "pass":
            raise ValueError("结果必须通过自动校验后才能读取结果表")
        contract = self.store.load(plan_id)
        if not contract.run_directory:
            raise ValueError("分析计划尚未运行")
        run_dir = secure_path(contract.run_directory).resolve()
        path = secure_path(run_dir / relative_path).resolve()
        if run_dir not in path.parents:
            raise ValueError("结果表必须位于本次运行目录内")
        if path.suffix.lower() not in {".csv", ".tsv"}:
            raise ValueError("只能读取 CSV 或 TSV 结果表")
        separator = "\t" if path.suffix.lower() == ".tsv" else ","
        frame = pd.read_csv(path, sep=separator, encoding="utf-8-sig")
        preview = frame.head(limit).astype(object)
        preview = preview.where(pd.notna(preview), None)
        return {
            "path": relative_path.replace("\\", "/"),
            "row_count": int(len(frame)),
            "column_count": int(len(frame.columns)),
            "columns": list(map(str, frame.columns)),
            "rows": preview.to_dict(orient="records"),
            "truncated": len(frame) > limit,
        }

    def save_interpretation(self, plan_id: str, interpretation: dict[str, object]) -> dict:
        """Persist a validated, project-specific LLM interpretation and rebuild the fixed report."""
        validation = self.validate(plan_id)
        if validation["status"] != "pass":
            raise ValueError("结果必须通过自动校验后才能解读")
        contract = self.store.load(plan_id)
        if not contract.run_directory:
            raise ValueError("分析计划尚未运行")
        parsed = AnalysisInterpretation.model_validate(interpretation)
        run_dir = secure_path(contract.run_directory)
        path = run_dir / "interpretation.json"
        path.write_text(parsed.model_dump_json(indent=2), encoding="utf-8")
        report = build_analysis_report(run_dir)
        return {
            "plan_id": plan_id,
            "interpretation_path": str(path),
            "report_path": report["report_path"],
        }

    @staticmethod
    def _verify_hashes(contract: AnalysisContract) -> None:
        for name, path_value in contract.files.model_dump().items():
            if path_value is None:
                continue
            path = secure_path(path_value)
            if sha256_file(path) != contract.file_hashes[name]:
                raise ValueError(f"生成计划后输入文件已发生变化：{name}")

    @staticmethod
    def _run_analysis_functions(contract: AnalysisContract, run_dir: Path,
                                function_ids: list[str], rscript: str) -> None:
        function_root = run_dir / "functions"
        logs = function_root / "logs"
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
            workspace = function_root / "batches" / safe_context
            workspace.mkdir(parents=True, exist_ok=True)
            source_sample_ids = context_meta.iloc[:, 0].astype(str).tolist()
            if "sample_name" in context_meta.columns:
                output_sample_ids = context_meta["sample_name"].astype(str).tolist()
            else:
                output_sample_ids = source_sample_ids
            missing = sorted(set(source_sample_ids) - set(map(str, abundance.columns[1:])))
            if missing:
                raise RuntimeError(f"无法创建函数工作区；缺少样本：{missing}")
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

        manifest: dict[str, object] = {"functions": {}, "contexts": [x[0] for x in workspaces], "status": "running"}
        failures: list[str] = []
        env = r_subprocess_environment()
        env["SCRIPT_DIR"] = str(FUNCTION_ROOT)
        for function_id in function_ids:
            function = get_function(function_id)
            script = FUNCTION_ROOT / str(function["script"])
            function_runs: dict[str, object] = {}
            for context_name, workspace, context_meta in workspaces:
                eligibility = assess_context(
                    function, context_meta,
                    has_tree=(workspace / "otus.tree").exists(),
                    has_ko=any(str(column).lower() in {"ko", "koid", "kegg_orthology"} for column in taxonomy.columns),
                    has_pathway=any(
                        str(column).lower() in {"pathway", "kegg_pathway", "pathway_id"}
                        for column in taxonomy.columns
                    ),
                    source_sink_configured=bool(params.get("sink_group") and params.get("source_groups")),
                )
                if not eligibility["eligible"]:
                    function_runs[context_name] = {
                        "status": "skipped", "reason": eligibility["reason"]
                    }
                    continue
                completed = subprocess.run(
                    [rscript, str(script)], cwd=workspace, env=env,
                    capture_output=True, text=True, encoding="utf-8", errors="replace",
                    timeout=subprocess_timeout_seconds(), check=False,
                    **subprocess_limit_kwargs(),
                )
                log_name = f"{function_id}--{context_name}.log"
                (logs / log_name).write_text(
                    completed.stdout + "\n--- STDERR ---\n" + completed.stderr, encoding="utf-8"
                )
                function_runs[context_name] = {
                    "return_code": completed.returncode,
                    "status": "succeeded" if completed.returncode == 0 else "failed",
                    "log": f"logs/{log_name}",
                }
                if completed.returncode != 0:
                    failures.append(f"{function['display_name']}（{context_name}）")
            manifest["functions"][function_id] = {
                "display_name": function["display_name"],
                "description": function["description"],
                "script": function["script"],
                "category": function["category"],
                "category_name": function["category_name"],
                "runs": function_runs,
            }
        manifest["status"] = "failed" if failures else "succeeded"
        manifest["files"] = [
            str(path.relative_to(function_root))
            for path in function_root.rglob("*")
            if path.is_file()
        ]
        (function_root / "function_manifest.json").write_text(
            json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        if failures:
            raise RuntimeError("以下分析方法运行失败：" + "、".join(failures))
