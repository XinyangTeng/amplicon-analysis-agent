from __future__ import annotations

import argparse
import json
from datetime import date
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser(description="Merge an EMO smoke-test manifest into compatibility.json")
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--catalog", type=Path, default=Path("r/emo/compatibility.json"))
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    catalog = json.loads(args.catalog.read_text(encoding="utf-8")) if args.catalog.exists() else {}
    tested_on = date.today().isoformat()

    for module_id, module in manifest.get("modules", {}).items():
        runs = module.get("runs", {})
        statuses = {run.get("status") for run in runs.values()}
        if "failed" in statuses:
            status = "blocked"
            notes = "Compatibility smoke test failed; inspect the module log."
        elif "succeeded" in statuses:
            status = "verified"
            notes = "Completed compatibility smoke testing; input-specific prerequisites still apply."
        else:
            status = "conditional"
            reasons = sorted({str(run.get("reason")) for run in runs.values() if run.get("reason")})
            notes = "; ".join(reasons) or "Not executed because prerequisites were not satisfied."
        catalog[module_id] = {"status": status, "tested_on": tested_on, "notes": notes}

    args.catalog.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
