from __future__ import annotations

from pathlib import Path

from amplicon_agent.function_registry import list_functions


def main() -> None:
    lines = [
        "# Analysis function catalog",
        "",
        "Generated from the executable registry. `verified` means the function completed a smoke test; "
        "`conditional` means implementation is present but extra inputs or sample size are required.",
        "",
        "| Function | Category | Status | Declared parameters | Requirements |",
        "|---|---|---|---|---|",
    ]
    for function in list_functions():
        parameters = ", ".join(item["name"] for item in function["declared_parameters"]) or "—"
        spec = function["specification"]
        requirements = str(function.get("notes") or spec.get("minimum") or "—").replace("|", "/")
        lines.append(
            f"| `{function['function_id']}` | {function['category']} | {function['status']} | "
            f"{parameters} | {requirements} |"
        )
    output = Path("docs/FUNCTION_CATALOG.md")
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("\n".join(lines) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
