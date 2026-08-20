from __future__ import annotations

from pathlib import Path

from amplicon_agent.function_registry import list_functions


def main() -> None:
    lines = [
        "# 分析方法目录",
        "",
        "此目录由可执行方法注册表自动生成。`verified` 表示方法已通过冒烟测试；"
        "`conditional` 表示方法可用，但需要额外输入或满足样本量条件。",
        "",
        "| 分析方法 | 用途 | 类别 | 状态 | 内部调用 ID | 参数 | 使用条件 |",
        "|---|---|---|---|---|---|---|",
    ]
    for function in list_functions():
        parameters = ", ".join(item["name"] for item in function["declared_parameters"]) or "—"
        spec = function["specification"]
        requirements = str(function.get("notes") or spec.get("minimum") or "—").replace("|", "/")
        lines.append(
            f"| {function['display_name']} | {function['description']} | {function['category_name']} | "
            f"{function['status']} | `{function['function_id']}` | {parameters} | {requirements} |"
        )
    output = Path("docs/FUNCTION_CATALOG.md")
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("\n".join(lines) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
