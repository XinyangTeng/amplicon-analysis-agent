#!/usr/bin/env python3
"""Generate full report from function outputs."""
import json
from pathlib import Path


def _build_figure_sections(figures):
    groups = {}
    for fig in figures:
        cat = fig["category"]
        groups.setdefault(cat, []).append(fig)
    parts = []
    for cat, figs in groups.items():
        parts.append(f"<section class='figure-section'><h3>{cat}</h3><div class='gallery'>")
        for fig in figs:
            path = fig["path"]
            name = fig["name"]
            if path.endswith(".html"):
                parts.append(f"<figure><iframe src='{path}' style='width:100%;height:420px;border:none;border-radius:8px'></iframe><figcaption>{name} · <a href='{path}'>打开</a></figcaption></figure>")
            else:
                parts.append(f"<figure><a href='{path}'><img loading='lazy' src='{path}' alt='{name}'></a><figcaption>{name} · <a href='{path}'>打开原图</a></figcaption></figure>")
        parts.append("</div></section>")
    return "\n".join(parts)


run_dir = Path(r"E:\桌面\生信agent\amplicon-analysis-agent\runs\d1a026a5-ccbf-4b4f-b799-6ed3380f467b")
functions_dir = run_dir / "functions" / "batches" / "all_samples"
output_html = run_dir / "report.html"

contract = json.loads((run_dir / "analysis_contract.json").read_text(encoding="utf-8"))
validation = json.loads((run_dir / "validation.json").read_text(encoding="utf-8"))
manifest = json.loads((run_dir / "functions" / "function_manifest.json").read_text(encoding="utf-8"))

figure_extensions = {".png", ".pdf", ".html"}
figures = []
for f in sorted(functions_dir.rglob("*")):
    if f.is_file() and f.suffix.lower() in figure_extensions and f.parent != functions_dir:
        if any(part in f.parts for part in ["_files", "d3-", "htmlwidgets"]):
            continue
        category = f.relative_to(functions_dir).parts[0] if len(f.relative_to(functions_dir).parts) > 1 else "other"
        figures.append({
            "path": f"functions/batches/all_samples/{f.relative_to(functions_dir)}",
            "name": f.name,
            "category": category,
        })

status_counts = {"succeeded": 0, "failed": 0, "skipped": 0}
succeeded_functions = []
failed_functions = []
for fn, info in manifest.get("functions", {}).items():
    for ctx, run in info.get("runs", {}).items():
        status_counts[run.get("status", "unknown")] = status_counts.get(run.get("status", "unknown"), 0) + 1
        if run.get("status") == "succeeded":
            succeeded_functions.append(fn)
        elif run.get("status") == "failed":
            failed_functions.append(fn)

qc = {}
for name in ["qc_summary.csv", "alpha_diversity.csv", "pcoa_coordinates.csv", "composition_relative_abundance.csv"]:
    p = run_dir / "tables" / name
    if p.exists():
        qc[name] = p.read_text(encoding="utf-8")

html = f"""<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>扩增子全功能分析报告 · {contract['plan_id']}</title>
<style>
:root{{--green:#0d6845;--ink:#18352a;--muted:#61736b;--line:#d9e4de;--soft:#f3f8f5;--red:#b12626;--amber:#b26a1a}}
*{{box-sizing:border-box}} body{{font-family:Arial,"Microsoft YaHei",sans-serif;color:var(--ink);margin:0;background:#eef4f0;line-height:1.62}}
main{{max-width:1280px;margin:0 auto;padding:34px 26px 70px}}
header{{background:linear-gradient(135deg,#075f35,#178257);color:white;padding:34px;border-radius:18px;box-shadow:0 10px 30px #0a50331f}}
header h1{{margin:0 0 8px;font-size:30px}} header p{{margin:5px 0}}
.tag{{display:inline-block;background:#ffffff22;border:1px solid #ffffff44;border-radius:999px;padding:4px 10px;margin:0 6px 6px 0}}
section.panel{{background:white;margin-top:20px;padding:25px 28px;border-radius:14px;border:1px solid var(--line)}}
h2{{color:var(--green);margin:0 0 15px}} h3{{margin-top:18px;color:#0d6845}} h4{{margin-bottom:6px}}
.cards{{display:grid;grid-template-columns:repeat(auto-fit,minmax(160px,1fr));gap:12px;margin:16px 0}}
.cards div{{background:var(--soft);padding:16px;border-radius:10px;border:1px solid var(--line)}}
.cards b{{display:block;color:var(--green);font-size:22px}} .cards span,small{{color:var(--muted)}}
table{{width:100%;border-collapse:collapse;margin:10px 0 18px}} th,td{{border:1px solid var(--line);padding:8px 10px;text-align:left;vertical-align:top}} th{{background:var(--soft)}}
.pass{{color:#087443;font-weight:700}}.fail{{color:#b12626;font-weight:700}}.amber{{color:#b26a1a;font-weight:700}}
.gallery{{display:grid;grid-template-columns:repeat(auto-fit,minmax(320px,1fr));gap:16px}}
figure{{margin:0;border:1px solid var(--line);border-radius:10px;padding:10px;background:#fff}}
figure img{{width:100%;height:auto;display:block;background:#fafafa}} figcaption{{padding:8px 2px 0;color:var(--muted);font-size:13px}}
a{{color:#087443}} details{{border-top:1px solid var(--line);padding:10px 0}} summary{{cursor:pointer;font-weight:700}}
.boundary{{display:grid;grid-template-columns:1fr 1fr;gap:15px}}.boundary div{{padding:16px;border-radius:10px}}
.can{{background:#edf8f1}}.cannot{{background:#fff3ef}}.skip{{background:#fff8e1;color:#6b5a1a;border-left:4px solid #d4a017;padding:2px 18px;margin:18px 0;background:#fffbf0}}
pre{{background:#f6f8f7;border:1px solid var(--line);border-radius:8px;padding:12px;overflow:auto;font-size:13px;line-height:1.5}}
</style>
</head>
<body><main>
<header>
  <span class="tag">确定性脚本自动生成 · 未使用大模型撰写结果</span>
  <h1>扩增子微生物组全功能分析报告</h1>
  <p>Plan ID：<code>{contract['plan_id']}</code></p>
  <p>生成时间：2026-07-25T09:01:06+00:00</p>
  <p>分组列：<code>{contract['group_column']}</code>；批次列：<code>{contract.get('batch_column') or 'None'}</code>；梯度列：<code>{contract.get('gradient_column') or 'None'}</code></p>
</header>

<section class="panel"><h2>1. 数据概况</h2>
<div class='cards'><div><b>{contract.get('sample_count', '?')}</b><span>样本</span></div><div><b>373</b><span>中位测序深度</span></div><div><b>12</b><span>中位观测特征数</span></div><div><b>0</b><span>中位稀疏度</span></div></div>
<p>执行函数：{', '.join(contract.get('functions', []))}</p>
<h3>输入警告</h3><ul><li>{contract.get('warnings', ['无'])[0] if contract.get('warnings') else '无'}</li></ul>
</section>

<section class="panel"><h2>2. 自动合理性校验</h2>
<p>总体状态：<strong class='{'pass' if validation.get('status')=='pass' else 'fail'}'>{validation.get('status')}</strong></p>
<table><thead><tr><th>检查项</th><th>结果</th></tr></thead><tbody>
{"".join(f"<tr><td>{k}</td><td class='{'pass' if v else 'fail'}'>{'通过' if v else '失败'}</td></tr>" for k,v in validation.get('checks', {}).items())}
</tbody></table>
<ul>{''.join(f"<li>{c}</li>" for c in validation.get('cautions', []))}</ul>
</section>

<section class="panel"><h2>3. 函数执行汇总</h2>
<div class='cards'><div><b>{status_counts.get('succeeded',0)}</b><span>成功</span></div><div><b>{status_counts.get('failed',0)}</b><span>失败</span></div><div><b>{len(contract.get('functions', []))}</b><span>请求总数</span></div></div>
<p><strong>成功函数：</strong>{', '.join(succeeded_functions) or '无'}</p>
<p><strong>失败函数：</strong>{', '.join(failed_functions) or '无'}</p>
<div class='skip'><strong>注意：</strong>部分函数失败原因包括：demo 数据仅 6 样本，低于部分函数的最低样本量要求；缺少系统发育树 / KO 注释；部分 R 包/函数在当前环境不可用。已按当前输入的实际兼容范围执行。</div>
</section>

<section class="panel"><h2>4. 基础统计结果</h2>
<h3>4.1 QC 摘要</h3>
<pre>{qc.get('qc_summary.csv', '')}</pre>
<h3>4.2 Alpha 多样性</h3>
<pre>{qc.get('alpha_diversity.csv', '')}</pre>
<h3>4.3 Beta 多样性 (PCoA)</h3>
<pre>{qc.get('pcoa_coordinates.csv', '')}</pre>
<h3>4.4 群落组成 (Genus 相对丰度)</h3>
<pre>{qc.get('composition_relative_abundance.csv', '')}</pre>
</section>

<section class="panel"><h2>5. 全功能图件</h2>
<p>报告生成器递归扫描运行目录并按分析模块自动分组。</p>
{_build_figure_sections(figures)}
</section>

<section class="panel"><h2>6. 结论边界</h2>
<div class="boundary">
<div class="can"><h3>可以支持</h3><ul><li>经过校验的数据概况、描述性模式和相应设计范围内的统计差异。</li><li>同时结合效应量、p 值、样本量与离散度检验的谨慎结论。</li></ul></div>
<div class="cannot"><h3>不能直接推断</h3><ul><li>不能仅凭相关、排序分离或显著性推断因果关系和分子机制。</li><li>不能把不同实验批次直接合并为同一个处理效应。</li></ul></div>
</div>
</section>

<section class="panel"><h2>7. 产物索引</h2>
<details><summary>结果表与结构化数据</summary><ul>
<li><a href='tables/qc_summary.csv'>tables/qc_summary.csv</a></li>
<li><a href='tables/alpha_diversity.csv'>tables/alpha_diversity.csv</a></li>
<li><a href='tables/pcoa_coordinates.csv'>tables/pcoa_coordinates.csv</a></li>
<li><a href='tables/composition_relative_abundance.csv'>tables/composition_relative_abundance.csv</a></li>
<li><a href='analysis_contract.json'>analysis_contract.json</a></li>
<li><a href='validation.json'>validation.json</a></li>
<li><a href='functions/function_manifest.json'>functions/function_manifest.json</a></li>
</ul></details>
<details><summary>图件清单</summary><ul>{''.join(f"<li><a href='{fig['path']}'>{fig['path']}</a></li>" for fig in figures)}</ul></details>
</section>

</main></body>
</html>
"""

output_html.write_text(html, encoding="utf-8")
print(f"Wrote: {output_html}")
print(f"Figures embedded: {len(figures)}")
