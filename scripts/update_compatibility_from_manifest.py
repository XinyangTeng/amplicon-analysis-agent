from __future__ import annotations

import argparse
import json
from datetime import date
from pathlib import Path


METHOD_NOTES = {
    "script-feast": (
        "Verified constrained nonnegative source-contribution estimator. "
        "This is a transparent local approximation and not the original FEAST algorithm."
    ),
    "script-neutral-model": "Verified self-contained Sloan neutral-community model.",
    "script-nullmodel": "Verified group-label permutation null model for between-minus-within Bray distance.",
    "script-bnti": "Verified abundance-weighted betaNTI with phylogenetic tip-label randomization.",
    "script-bnti-rcbray": "Verified betaNTI plus modified Raup-Crick Bray-Curtis workflow.",
    "script-rcbray": "Verified modified Raup-Crick Bray-Curtis null model.",
    "script-stamp": "Verified rank-based abundance-difference view with Wilcoxon tests and BH correction.",
    "script-volcano-specific": "Verified rank-based volcano analysis with Wilcoxon tests and BH correction.",
    "script-function-bubble": "Verified predicted-KO rank-based differential bubble plot.",
    "script-function-diff": "Verified predicted-KO rank-based differential analysis.",
    "script-kegg-enrich": "Verified offline KO-to-Pathway Fisher over-representation analysis.",
}


def main() -> None:
    parser = argparse.ArgumentParser(description="Merge a function smoke-test manifest into compatibility.json")
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--catalog", type=Path, default=Path("r/functions/compatibility.json"))
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    if "function_manifest" in manifest:
        manifest = manifest["function_manifest"]
    catalog = json.loads(args.catalog.read_text(encoding="utf-8")) if args.catalog.exists() else {}
    tested_on = date.today().isoformat()

    for function_id, function in manifest.get("functions", {}).items():
        runs = function.get("runs", {})
        statuses = {run.get("status") for run in runs.values()}
        if "failed" in statuses:
            status = "blocked"
            failed = sorted(
                f"{function_id}/{context}"
                for context, run in runs.items()
                if run.get("status") == "failed"
            )
            notes = "Compatibility smoke test failed: " + ", ".join(failed)
        elif "succeeded" in statuses:
            status = "verified"
            notes = METHOD_NOTES.get(
                function_id,
                "Completed compatibility smoke testing; input-specific prerequisites still apply.",
            )
        else:
            status = "conditional"
            reasons = sorted({str(run.get("reason")) for run in runs.values() if run.get("reason")})
            notes = "; ".join(reasons) or "Not executed because prerequisites were not satisfied."
        catalog[function_id] = {"status": status, "tested_on": tested_on, "notes": notes}

    args.catalog.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
