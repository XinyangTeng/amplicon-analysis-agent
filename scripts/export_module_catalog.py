from __future__ import annotations

from pathlib import Path

from amplicon_agent.module_registry import list_modules


def main() -> None:
    lines = [
        "# EMO analysis module catalog",
        "",
        "Generated from the executable registry. `verified` means the module completed a smoke test; "
        "`conditional` means implementation is present but extra inputs or sample size are required.",
        "",
        "| Module | Category | Status | Declared parameters | Requirements |",
        "|---|---|---|---|---|",
    ]
    for module in list_modules():
        parameters = ", ".join(item["name"] for item in module["declared_parameters"]) or "—"
        spec = module["specification"]
        requirements = str(module.get("notes") or spec.get("minimum") or "—").replace("|", "/")
        lines.append(
            f"| `{module['module_id']}` | {module['category']} | {module['status']} | "
            f"{parameters} | {requirements} |"
        )
    output = Path("docs/MODULE_CATALOG.md")
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("\n".join(lines) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
