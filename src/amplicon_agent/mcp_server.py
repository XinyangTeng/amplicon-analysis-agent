from __future__ import annotations

from mcp.server.fastmcp import FastMCP

from .service import AgentService
from .function_registry import get_function, list_functions


mcp = FastMCP(
    "Amplicon Analysis Agent",
    instructions=(
        "Start every project with intake questions, even when files are already present. "
        "Inspect inputs, then explicitly confirm treatments, controls, contrasts, and scope before preparing. "
        "Never run a plan before the user explicitly approves it. "
        "Explain blockers, warnings, statistical limits, and the evidence supporting every conclusion. "
        "After execution, validate first, use compact get_report_context, and read only selected evidence "
        "tables with get_result_table; numerical analysis "
        "and report assembly are deterministic executor responsibilities, not language-model tasks."
    ),
)
service = AgentService()


@mcp.tool()
def list_amplicon_analysis_functions(category: str | None = None) -> dict:
    """List a compact function catalog, optionally filtered by category."""
    functions = list_functions(category)
    compact = [
        {
            "function_id": item["function_id"],
            "category": item["category"],
            "status": item["status"],
            "minimum": item["specification"].get("minimum"),
        }
        for item in functions
    ]
    return {"count": len(compact), "functions": compact}


@mcp.tool()
def inspect_amplicon_function(function_id: str) -> dict:
    """Return requirements, parameters, status, and provenance for one analysis function."""
    return get_function(function_id)


@mcp.tool()
def inspect_amplicon_inputs(abundance: str, taxonomy: str, metadata: str, group_column: str,
                            batch_column: str | None = None,
                            gradient_column: str | None = None) -> dict:
    """Inspect three amplicon tables without running analysis."""
    return service.inspect(abundance, taxonomy, metadata, group_column, batch_column, gradient_column)


@mcp.tool()
def prepare_amplicon_analysis(abundance: str, taxonomy: str, metadata: str, group_column: str,
                               functions: list[str] | None = None, permutations: int = 999,
                               top_n: int = 10, batch_column: str | None = None,
                               gradient_column: str | None = None, tree: str | None = None,
                               representative_sequences: str | None = None,
                               function_parameters: dict[str, object] | None = None,
                               project_design: dict[str, object] | None = None,
                               analysis_scope: str = "targeted") -> dict:
    """Create an immutable analysis contract. This does not execute analysis."""
    return service.prepare(abundance, taxonomy, metadata, group_column, functions, permutations, top_n,
                           batch_column, gradient_column, tree, representative_sequences,
                           function_parameters, project_design, analysis_scope)


@mcp.tool()
def approve_analysis(plan_id: str, confirmation: str) -> dict:
    """Approve a prepared plan. confirmation must exactly be 'CONFIRM <plan_id>'."""
    return service.approve(plan_id, confirmation).model_dump()


@mcp.tool()
def run_amplicon_analysis(plan_id: str, approval_token: str) -> dict:
    """Run an approved plan once. The approval token is consumed before execution."""
    return service.run(plan_id, approval_token).model_dump()


@mcp.tool()
def get_run_status(plan_id: str) -> dict:
    """Return the current contract and run status."""
    return service.status(plan_id)


@mcp.tool()
def validate_amplicon_results(plan_id: str) -> dict:
    """Check required artifacts and domain validation results."""
    return service.validate(plan_id)


@mcp.tool()
def get_analysis_report(plan_id: str) -> dict:
    """Return the local HTML report path for a completed plan."""
    return service.report(plan_id)


@mcp.tool()
def get_report_context(plan_id: str) -> dict:
    """Return a compact validated context for LLM interpretation."""
    return service.report_context(plan_id)


@mcp.tool()
def get_result_table(plan_id: str, relative_path: str, limit: int = 50) -> dict:
    """Read one validated CSV/TSV result table on demand; use paths from get_report_context."""
    return service.result_table(plan_id, relative_path, limit)


@mcp.tool()
def save_analysis_interpretation(plan_id: str, interpretation: dict[str, object]) -> dict:
    """Save project-specific interpretation after validation and rebuild the fixed HTML report."""
    return service.save_interpretation(plan_id, interpretation)


def main() -> None:
    mcp.run(transport="stdio")


if __name__ == "__main__":
    main()
