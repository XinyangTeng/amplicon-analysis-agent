from __future__ import annotations

import re
import json
from pathlib import Path

from .function_specs import specification


FUNCTION_ROOT = Path(__file__).resolve().parents[2] / "r" / "functions"


def _category(name: str) -> str:
    rules = [
        (("alpha", "rarefaction"), "alpha_diversity"),
        (("ordinate", "pca", "microtest", "distance", "cluster"), "beta_diversity"),
        (("barplot", "heatmap", "sankey", "ternary", "flower", "venn", "Ven", "cir_"), "composition"),
        (("deseq2", "edger", "volcano", "stamp", "manhattan", "function_diff"), "differential_abundance"),
        (("random_forest", "rfcv", "svm", "lasso", "decision_tree", "naive_bayes", "bagging", "nnet", "lda", "roc", "loading_pca"), "biomarker_ml"),
        (("network", "mantal"), "network"),
        (("bnti", "rcbray", "neutral", "nullmodel", "feast"), "community_assembly"),
        (("kegg", "function_bubble"), "functional_prediction"),
    ]
    for needles, category in rules:
        if any(item.lower() in name.lower() for item in needles):
            return category
    return "other"


def _packages(text: str) -> list[str]:
    return sorted(set(re.findall(r"(?:library|require)\s*\(\s*([A-Za-z][A-Za-z0-9._]*)", text)))


def _parameters(text: str) -> list[dict[str, str]]:
    type_map = {"chr": "string", "num": "number", "int": "integer", "bool": "boolean", "vec": "array[string]"}
    found: dict[str, str] = {}
    for kind, name in re.findall(r'param_(chr|num|int|bool|vec)\s*\(\s*params\s*,\s*"([^"]+)"', text):
        found[name] = type_map[kind]
    return [{"name": name, "type": found[name]} for name in sorted(found)]


def function_registry() -> dict[str, dict[str, object]]:
    compatibility_path = FUNCTION_ROOT / "compatibility.json"
    compatibility = json.loads(compatibility_path.read_text(encoding="utf-8")) if compatibility_path.exists() else {}
    registry: dict[str, dict[str, object]] = {}
    for path in sorted(FUNCTION_ROOT.glob("*.R")):
        if path.name == "amp_common.R":
            continue
        text = path.read_text(encoding="utf-8-sig", errors="replace")
        function_id = path.stem.lower().replace(".", "-").replace("_", "-")
        registry[function_id] = {
            "function_id": function_id,
            "script": path.name,
            "category": _category(path.name),
            "packages": _packages(text),
            "declared_parameters": _parameters(text),
            "uses_common_adapter": "amp_common.R" in text,
            "status": "registered_untested",
            "source": "team-authorized R function collection",
            "specification": specification(function_id, _category(path.name)),
        }
        registry[function_id].update(compatibility.get(function_id, {}))
    return registry


def list_functions(category: str | None = None) -> list[dict[str, object]]:
    functions = list(function_registry().values())
    if category:
        functions = [function for function in functions if function["category"] == category]
    return functions


def get_function(function_id: str) -> dict[str, object]:
    try:
        return function_registry()[function_id]
    except KeyError as exc:
        raise ValueError(f"Unknown analysis function: {function_id}") from exc
