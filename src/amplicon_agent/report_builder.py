from __future__ import annotations

import csv
import hashlib
import html
import json
import statistics
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import quote


REPORT_FILES = {"report.html", "report_data.json", "artifact_manifest.json"}
IMAGE_EXTENSIONS = {".png", ".jpg", ".jpeg", ".gif", ".svg", ".webp"}
TABLE_EXTENSIONS = {".csv", ".tsv", ".txt", ".xlsx", ".xls", ".json"}
LOG_EXTENSIONS = {".log"}
SECTION_LABELS = {
    "figures": "基础分析",
    "01_alpha_diversity": "Alpha 多样性",
    "02_beta_diversity": "Beta 多样性",
    "03_composition": "群落组成",
    "04_differential": "差异分析",
    "05_network": "网络分析",
    "06_assembly": "群落构建",
    "07_machine_learning": "机器学习",
    "08_function": "功能分析",
}


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _load_json(path: Path, default: object) -> object:
    if not path.exists():
        return default
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError):
        return default


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _artifact_kind(path: Path) -> str:
    suffix = path.suffix.lower()
    if suffix in IMAGE_EXTENSIONS:
        return "figure"
    if suffix in LOG_EXTENSIONS:
        return "log"
    if suffix in TABLE_EXTENSIONS:
        return "table_or_data"
    if suffix == ".pdf":
        return "document"
    return "other"


def _artifact_context(relative: Path) -> tuple[str, str]:
    parts = relative.parts
    if len(parts) >= 4 and parts[0] == "emo" and parts[1] == "batches":
        context = parts[2]
        section = SECTION_LABELS.get(parts[3], parts[3].replace("_", " "))
        return context, section
    if parts and parts[0] == "figures":
        return "all_samples", SECTION_LABELS["figures"]
    if parts and parts[0] == "tables":
        return "all_samples", "基础结果表"
    if len(parts) >= 2 and parts[0] == "emo" and parts[1] == "logs":
        return "module_logs", "模块日志"
    return "run", "运行与溯源"


def _inventory(run_dir: Path) -> list[dict[str, object]]:
    records: list[dict[str, object]] = []
    for path in sorted(run_dir.rglob("*")):
        if not path.is_file():
            continue
        relative = path.relative_to(run_dir)
        if relative.as_posix() in REPORT_FILES:
            continue
        context, section = _artifact_context(relative)
        records.append(
            {
                "path": relative.as_posix(),
                "kind": _artifact_kind(path),
                "extension": path.suffix.lower(),
                "size_bytes": path.stat().st_size,
                "sha256": _sha256(path),
                "context": context,
                "section": section,
            }
        )
    return records


def _qc_summary(path: Path) -> dict[str, object]:
    if not path.exists():
        return {}
    try:
        with path.open("r", encoding="utf-8-sig", newline="") as handle:
            rows = list(csv.DictReader(handle))
        depths = [float(row["sequencing_depth"]) for row in rows]
        observed = [float(row["observed_features"]) for row in rows]
        sparsity = [float(row["zero_fraction"]) for row in rows]
    except (OSError, KeyError, TypeError, ValueError):
        return {}
    if not rows:
        return {}
    return {
        "sample_count": len(rows),
        "sequencing_depth": {
            "minimum": min(depths),
            "median": statistics.median(depths),
            "maximum": max(depths),
        },
        "observed_features": {
            "minimum": min(observed),
            "median": statistics.median(observed),
            "maximum": max(observed),
        },
        "zero_fraction": {
            "minimum": min(sparsity),
            "median": statistics.median(sparsity),
            "maximum": max(sparsity),
        },
    }


def _module_summary(manifest: object) -> dict[str, object]:
    if not isinstance(manifest, dict):
        return {"status": "not_requested", "modules": [], "run_counts": {}}
    modules: list[dict[str, object]] = []
    counts: Counter[str] = Counter()
    raw_modules = manifest.get("modules", {})
    if isinstance(raw_modules, dict):
        for module_id, module in raw_modules.items():
            if not isinstance(module, dict):
                continue
            run_states: dict[str, str] = {}
            raw_runs = module.get("runs", {})
            if isinstance(raw_runs, dict):
                for context, result in raw_runs.items():
                    state = str(result.get("status", "unknown")) if isinstance(result, dict) else "unknown"
                    run_states[str(context)] = state
                    counts[state] += 1
            modules.append(
                {
                    "module_id": str(module_id),
                    "script": module.get("script"),
                    "category": module.get("category"),
                    "runs": run_states,
                }
            )
    return {
        "status": manifest.get("status", "unknown"),
        "contexts": manifest.get("contexts", []),
        "modules": modules,
        "run_counts": dict(sorted(counts.items())),
    }


def _contract_summary(contract: object) -> dict[str, object]:
    if not isinstance(contract, dict):
        return {}
    raw_files = contract.get("files", {})
    files: dict[str, object] = {}
    if isinstance(raw_files, dict):
        hashes = contract.get("file_hashes", {})
        hashes = hashes if isinstance(hashes, dict) else {}
        for role, value in raw_files.items():
            if value:
                files[str(role)] = {
                    "name": Path(str(value)).name,
                    "sha256": hashes.get(role),
                }
    return {
        "schema_version": contract.get("schema_version"),
        "plan_id": contract.get("plan_id"),
        "status": contract.get("status"),
        "created_at": contract.get("created_at"),
        "group_column": contract.get("group_column"),
        "batch_column": contract.get("batch_column"),
        "gradient_column": contract.get("gradient_column"),
        "modules": contract.get("modules", []),
        "parameters": contract.get("parameters", {}),
        "warnings": contract.get("warnings", []),
        "blockers": contract.get("blockers", []),
        "inputs": files,
    }


def _number(value: object, digits: int = 4) -> str:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return html.escape(str(value))
    return f"{number:.{digits}g}"


def _link(path: str, label: str | None = None) -> str:
    return f"<a href='{quote(path, safe='/')}'>{html.escape(label or path)}</a>"


def _validation_html(validation: object) -> str:
    if not isinstance(validation, dict):
        return "<p class='warn'>未找到结构化校验结果。</p>"
    checks = validation.get("checks", {})
    rows = []
    if isinstance(checks, dict):
        for name, passed in checks.items():
            state = "通过" if passed else "失败"
            css = "pass" if passed else "fail"
            rows.append(
                f"<tr><td>{html.escape(str(name))}</td><td class='{css}'>{state}</td></tr>"
            )
    status = html.escape(str(validation.get("status", "unknown")))
    cautions = validation.get("cautions", [])
    caution_html = "".join(f"<li>{html.escape(str(item))}</li>" for item in cautions)
    return (
        f"<p>总体状态：<strong>{status}</strong></p>"
        "<table><thead><tr><th>检查项</th><th>结果</th></tr></thead>"
        f"<tbody>{''.join(rows)}</tbody></table><ul>{caution_html}</ul>"
    )


def _stratified_html(results: object) -> str:
    if not isinstance(results, dict):
        return "<p>未找到分层统计结果。</p>"
    if results.get("skipped"):
        return f"<p>{html.escape(str(results.get('reason', '分层分析未运行。')))}</p>"
    batches = results.get("batches", {})
    if not isinstance(batches, dict):
        return "<p>未找到分层统计结果。</p>"
    cards: list[str] = []
    for batch, result in batches.items():
        if not isinstance(result, dict):
            continue
        analysis_type = str(result.get("analysis_type", "unknown"))
        body: list[str] = [
            f"<p>样本数：{html.escape(str(result.get('sample_count', 'NA')))}；"
            f"分析类型：<code>{html.escape(analysis_type)}</code></p>"
        ]
        if analysis_type == "ordered_gradient":
            rows = []
            alpha_trend = result.get("alpha_trend", {})
            if isinstance(alpha_trend, dict):
                for metric, values in alpha_trend.items():
                    if isinstance(values, dict):
                        rows.append(
                            f"<tr><td>{html.escape(str(metric))}</td>"
                            f"<td>{_number(values.get('rho'))}</td>"
                            f"<td>{_number(values.get('p_value'))}</td></tr>"
                        )
            body.append(
                "<h4>Alpha 梯度趋势（Spearman）</h4><table><thead>"
                "<tr><th>指标</th><th>rho</th><th>p</th></tr></thead>"
                f"<tbody>{''.join(rows)}</tbody></table>"
            )
            beta = result.get("beta_trend", {})
            if isinstance(beta, dict):
                body.append(
                    "<p>Beta 连续梯度："
                    f"R²={_number(beta.get('R2'))}，F={_number(beta.get('F'))}，"
                    f"p={_number(beta.get('p_value'))}。</p>"
                )
        else:
            rows = []
            alpha = result.get("alpha_group", {})
            if isinstance(alpha, dict):
                for metric, values in alpha.items():
                    if isinstance(values, dict):
                        rows.append(
                            f"<tr><td>{html.escape(str(metric))}</td>"
                            f"<td>{_number(values.get('statistic'))}</td>"
                            f"<td>{_number(values.get('p_value'))}</td></tr>"
                        )
            body.append(
                "<h4>Alpha 组间检验</h4><table><thead>"
                "<tr><th>指标</th><th>统计量</th><th>p</th></tr></thead>"
                f"<tbody>{''.join(rows)}</tbody></table>"
            )
            permanova = result.get("permanova", {})
            dispersion = result.get("dispersion", {})
            if isinstance(permanova, dict):
                body.append(
                    "<p>PERMANOVA："
                    f"R²={_number(permanova.get('R2'))}，F={_number(permanova.get('F'))}，"
                    f"p={_number(permanova.get('p_value'))}。"
                    "组内离散度："
                    f"F={_number(dispersion.get('F') if isinstance(dispersion, dict) else None)}，"
                    f"p={_number(dispersion.get('p_value') if isinstance(dispersion, dict) else None)}。</p>"
                )
        cards.append(
            f"<article class='batch'><h3>{html.escape(str(batch))}</h3>{''.join(body)}</article>"
        )
    return "".join(cards)


def _module_html(summary: dict[str, object]) -> str:
    modules = summary.get("modules", [])
    if not isinstance(modules, list) or not modules:
        return "<p>本次未请求团队扩展模块。</p>"
    rows: list[str] = []
    for module in modules:
        if not isinstance(module, dict):
            continue
        runs = module.get("runs", {})
        run_text = "；".join(f"{name}: {state}" for name, state in runs.items()) if isinstance(runs, dict) else ""
        rows.append(
            "<tr>"
            f"<td>{html.escape(str(module.get('module_id', '')))}</td>"
            f"<td>{html.escape(str(module.get('category', '')))}</td>"
            f"<td>{html.escape(run_text)}</td>"
            "</tr>"
        )
    return (
        "<table><thead><tr><th>模块</th><th>类别</th><th>各批次状态</th></tr></thead>"
        f"<tbody>{''.join(rows)}</tbody></table>"
    )


def _figures_html(figures: list[dict[str, object]]) -> str:
    if not figures:
        return "<p>未发现可嵌入的图件。</p>"
    grouped: dict[tuple[str, str], list[dict[str, object]]] = defaultdict(list)
    for figure in figures:
        grouped[(str(figure["context"]), str(figure["section"]))].append(figure)
    sections: list[str] = []
    for (context, section), items in sorted(grouped.items()):
        cards = []
        for item in items:
            path = str(item["path"])
            label = Path(path).stem.replace("_", " ")
            cards.append(
                "<figure>"
                f"<a href='{quote(path, safe='/')}'><img loading='lazy' src='{quote(path, safe='/')}' "
                f"alt='{html.escape(label)}'></a>"
                f"<figcaption>{html.escape(label)} · {_link(path, '打开原图')}</figcaption>"
                "</figure>"
            )
        sections.append(
            f"<section class='figure-section'><h3>{html.escape(context)} · "
            f"{html.escape(section)}</h3><div class='gallery'>{''.join(cards)}</div></section>"
        )
    return "".join(sections)


def _downloads_html(artifacts: list[dict[str, object]]) -> str:
    grouped: dict[str, list[dict[str, object]]] = defaultdict(list)
    for item in artifacts:
        if item["kind"] == "figure":
            continue
        grouped[str(item["kind"])].append(item)
    labels = {
        "table_or_data": "结果表与结构化数据",
        "document": "PDF 与文档",
        "log": "运行日志",
        "other": "其他溯源文件",
    }
    blocks: list[str] = []
    for kind in ("table_or_data", "document", "log", "other"):
        items = grouped.get(kind, [])
        if not items:
            continue
        links = "".join(
            f"<li>{_link(str(item['path']))} "
            f"<small>({int(item['size_bytes']):,} bytes)</small></li>"
            for item in items
        )
        blocks.append(f"<details><summary>{labels[kind]}（{len(items)}）</summary><ul>{links}</ul></details>")
    return "".join(blocks)


def _render_html(data: dict[str, object]) -> str:
    contract = data["contract"]
    validation = data["validation"]
    qc = data["qc_summary"]
    module_execution = data["module_execution"]
    artifacts = data["artifacts"]
    figures = artifacts["figures"]
    all_artifacts = artifacts["files"]
    warnings = contract.get("warnings", []) if isinstance(contract, dict) else []
    warning_html = "".join(f"<li>{html.escape(str(item))}</li>" for item in warnings) or "<li>无</li>"
    plan_id = html.escape(str(contract.get("plan_id", "unknown"))) if isinstance(contract, dict) else "unknown"
    modules = contract.get("modules", []) if isinstance(contract, dict) else []
    qc_cards = ""
    if isinstance(qc, dict) and qc:
        depth = qc.get("sequencing_depth", {})
        observed = qc.get("observed_features", {})
        sparsity = qc.get("zero_fraction", {})
        qc_cards = (
            "<div class='cards'>"
            f"<div><b>{html.escape(str(qc.get('sample_count')))}</b><span>样本</span></div>"
            f"<div><b>{_number(depth.get('median') if isinstance(depth, dict) else None)}</b><span>中位测序深度</span></div>"
            f"<div><b>{_number(observed.get('median') if isinstance(observed, dict) else None)}</b><span>中位观测特征数</span></div>"
            f"<div><b>{_number(sparsity.get('median') if isinstance(sparsity, dict) else None)}</b><span>中位稀疏度</span></div>"
            "</div>"
        )
    generated = html.escape(str(data.get("generated_at")))
    return f"""<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>扩增子分析报告 · {plan_id}</title>
<style>
:root{{--green:#0d6845;--ink:#18352a;--muted:#61736b;--line:#d9e4de;--soft:#f3f8f5;}}
*{{box-sizing:border-box}} body{{font-family:Arial,"Microsoft YaHei",sans-serif;color:var(--ink);
margin:0;background:#eef4f0;line-height:1.62}} main{{max-width:1180px;margin:0 auto;padding:34px 26px 70px}}
header{{background:linear-gradient(135deg,#075f35,#178257);color:white;padding:34px;border-radius:18px;
box-shadow:0 10px 30px #0a50331f}} header h1{{margin:0 0 8px;font-size:30px}} header p{{margin:5px 0}}
.tag{{display:inline-block;background:#ffffff22;border:1px solid #ffffff44;border-radius:999px;padding:4px 10px}}
section.panel{{background:white;margin-top:20px;padding:25px 28px;border-radius:14px;border:1px solid var(--line)}}
h2{{color:var(--green);margin:0 0 15px}} h3{{margin-top:18px}} h4{{margin-bottom:6px}}
.cards{{display:grid;grid-template-columns:repeat(auto-fit,minmax(160px,1fr));gap:12px;margin:16px 0}}
.cards div{{background:var(--soft);padding:16px;border-radius:10px;border:1px solid var(--line)}}
.cards b{{display:block;color:var(--green);font-size:22px}} .cards span,small{{color:var(--muted)}}
table{{width:100%;border-collapse:collapse;margin:10px 0 18px}} th,td{{border:1px solid var(--line);
padding:8px 10px;text-align:left;vertical-align:top}} th{{background:var(--soft)}} code{{background:var(--soft);
padding:2px 6px;border-radius:4px}} .pass{{color:#087443;font-weight:700}} .fail{{color:#b12626;font-weight:700}}
.batch{{border-left:4px solid #68a98c;padding:2px 18px;margin:18px 0;background:#f8fbf9}}
.gallery{{display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:16px}}
figure{{margin:0;border:1px solid var(--line);border-radius:10px;padding:10px;background:#fff}}
figure img{{width:100%;height:auto;display:block;background:#fafafa}} figcaption{{padding:8px 2px 0;color:var(--muted)}}
a{{color:#087443}} details{{border-top:1px solid var(--line);padding:10px 0}} summary{{cursor:pointer;font-weight:700}}
.boundary{{display:grid;grid-template-columns:1fr 1fr;gap:15px}} .boundary div{{padding:16px;border-radius:10px}}
.can{{background:#edf8f1}} .cannot{{background:#fff3ef}} @media(max-width:700px){{.boundary{{grid-template-columns:1fr}}}}
</style>
</head>
<body><main>
<header>
  <span class="tag">确定性脚本自动生成 · 未使用大模型撰写结果</span>
  <h1>扩增子微生物组分析报告</h1>
  <p>Plan ID：<code>{plan_id}</code></p>
  <p>生成时间：{generated}</p>
</header>
<section class="panel"><h2>1. 分析合同与数据概况</h2>
  {qc_cards}
  <p>分组列：<code>{html.escape(str(contract.get("group_column")))}</code>；
  批次列：<code>{html.escape(str(contract.get("batch_column")))}</code>；
  梯度列：<code>{html.escape(str(contract.get("gradient_column")))}</code>。</p>
  <p>执行模块：{html.escape("、".join(map(str, modules)))}</p>
  <h3>输入警告</h3><ul>{warning_html}</ul>
</section>
<section class="panel"><h2>2. 自动合理性校验</h2>{_validation_html(validation)}</section>
<section class="panel"><h2>3. 分层统计结果</h2>
  <p>下列数值由统计脚本直接读取并排版，未经过语言模型改写。</p>
  {_stratified_html(data.get("statistical_results", {}).get("stratified_tests", {}))}
</section>
<section class="panel"><h2>4. 团队 EMO 模块执行状态</h2>{_module_html(module_execution)}</section>
<section class="panel"><h2>5. 全部分析图件</h2>
  <p>报告生成器递归扫描运行目录并按批次和结果目录自动分组；新增模块图件无需手工修改报告模板。</p>
  {_figures_html(figures)}
</section>
<section class="panel"><h2>6. 结论边界</h2>
  <div class="boundary"><div class="can"><h3>可以支持</h3><ul>
  <li>经过校验的数据概况、描述性模式和相应设计范围内的统计差异。</li>
  <li>同时结合效应量、p 值、样本量与离散度检验的谨慎结论。</li>
  </ul></div><div class="cannot"><h3>不能直接推断</h3><ul>
  <li>不能仅凭相关、排序分离或显著性推断因果关系和分子机制。</li>
  <li>不能把不同实验批次直接合并为同一个处理效应。</li>
  </ul></div></div>
</section>
<section class="panel"><h2>7. 文件索引</h2>
  <p>共扫描 {len(all_artifacts)} 个产物；完整哈希清单见 {_link("artifact_manifest.json")}，
  供 Agent 解读的结构化摘要见 {_link("report_data.json")}。</p>
  {_downloads_html(all_artifacts)}
</section>
</main></body></html>"""


def build_analysis_report(run_directory: str | Path) -> dict[str, object]:
    """Scan a completed run and deterministically rebuild its HTML and JSON reports."""
    run_dir = Path(run_directory).resolve()
    if not run_dir.is_dir():
        raise ValueError(f"Run directory does not exist: {run_dir}")

    contract = _load_json(run_dir / "analysis_contract.json", {})
    validation = _load_json(run_dir / "validation.json", {})
    run_manifest = _load_json(run_dir / "run_manifest.json", {})
    alpha_tests = _load_json(run_dir / "tables" / "alpha_tests.json", {})
    beta_tests = _load_json(run_dir / "tables" / "beta_tests.json", {})
    stratified_tests = _load_json(run_dir / "tables" / "stratified_tests.json", {})
    emo_manifest = _load_json(run_dir / "emo" / "emo_manifest.json", {})
    artifacts = _inventory(run_dir)
    kinds = Counter(str(item["kind"]) for item in artifacts)
    figures = [item for item in artifacts if item["kind"] == "figure"]

    report_data: dict[str, object] = {
        "schema_version": "1.0",
        "generated_at": _utc_now(),
        "generator": {
            "name": "amplicon_agent.report_builder",
            "mode": "deterministic",
            "llm_generated": False,
        },
        "contract": _contract_summary(contract),
        "execution": run_manifest,
        "validation": validation,
        "qc_summary": _qc_summary(run_dir / "tables" / "qc_summary.csv"),
        "statistical_results": {
            "alpha_tests": alpha_tests,
            "beta_tests": beta_tests,
            "stratified_tests": stratified_tests,
        },
        "module_execution": _module_summary(emo_manifest),
        "artifacts": {
            "counts": dict(sorted(kinds.items())),
            "figures": figures,
            "files": artifacts,
        },
        "interpretation_policy": {
            "read_after_validation": True,
            "separate_facts_statistics_interpretations_hypotheses": True,
            "permanova_requires_dispersion": True,
            "association_is_not_causation": True,
            "do_not_pool_batches": True,
        },
    }
    (run_dir / "report_data.json").write_text(
        json.dumps(report_data, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    (run_dir / "report.html").write_text(_render_html(report_data), encoding="utf-8")

    final_artifacts = _inventory(run_dir)
    for report_name in ("report.html", "report_data.json"):
        path = run_dir / report_name
        context, section = _artifact_context(Path(report_name))
        final_artifacts.append(
            {
                "path": report_name,
                "kind": "document" if report_name.endswith(".html") else "table_or_data",
                "extension": path.suffix.lower(),
                "size_bytes": path.stat().st_size,
                "sha256": _sha256(path),
                "context": context,
                "section": section,
            }
        )
    artifact_manifest = {
        "schema_version": "1.0",
        "generated_at": _utc_now(),
        "plan_id": report_data["contract"].get("plan_id"),
        "self_hash_excluded": True,
        "file_count": len(final_artifacts),
        "files": sorted(final_artifacts, key=lambda item: str(item["path"])),
    }
    (run_dir / "artifact_manifest.json").write_text(
        json.dumps(artifact_manifest, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    return {
        "report_path": str(run_dir / "report.html"),
        "report_data_path": str(run_dir / "report_data.json"),
        "artifact_manifest_path": str(run_dir / "artifact_manifest.json"),
        "artifact_count": len(final_artifacts),
        "figure_count": len(figures),
    }
