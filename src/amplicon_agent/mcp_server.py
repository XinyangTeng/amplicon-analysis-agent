from __future__ import annotations

from mcp.server.fastmcp import FastMCP

from .service import AgentService
from .module_registry import get_module, list_modules


mcp = FastMCP(
    "Amplicon Analysis Agent",
    instructions=(
        "Inspect inputs before preparing a plan. Never run a plan before the user explicitly approves it. "
        "Explain blockers, warnings, statistical limits, and the evidence supporting every conclusion. "
        "After execution, validate first and use get_report_context for interpretation; numerical analysis "
        "and report assembly are deterministic executor responsibilities, not language-model tasks."
    ),
)
service = AgentService()


@mcp.tool()
def list_amplicon_analysis_modules(category: str | None = None) -> dict:
    """List all registered team EMO analysis modules, optionally filtered by category."""
    modules = list_modules(category)
    return {"count": len(modules), "modules": modules}


@mcp.tool()
def inspect_amplicon_module(module_id: str) -> dict:
    """Return provenance and declared package requirements for one EMO module."""
    return get_module(module_id)


@mcp.tool()
def inspect_amplicon_inputs(abundance: str, taxonomy: str, metadata: str, group_column: str,
                            batch_column: str | None = None,
                            gradient_column: str | None = None) -> dict:
    """Inspect three amplicon tables without running analysis."""
    return service.inspect(abundance, taxonomy, metadata, group_column, batch_column, gradient_column)


@mcp.tool()
def prepare_amplicon_analysis(abundance: str, taxonomy: str, metadata: str, group_column: str,
                               modules: list[str] | None = None, permutations: int = 999,
                               top_n: int = 10, batch_column: str | None = None,
                               gradient_column: str | None = None, tree: str | None = None,
                               representative_sequences: str | None = None,
                               module_parameters: dict[str, object] | None = None) -> dict:
    """Create an immutable analysis contract. This does not execute analysis."""
    return service.prepare(abundance, taxonomy, metadata, group_column, modules, permutations, top_n,
                           batch_column, gradient_column, tree, representative_sequences,
                           module_parameters)


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
    """Return validated structured results for LLM interpretation; never use this to run analysis."""
    return service.report_context(plan_id)


def main() -> None:
    mcp.run(transport="stdio")


if __name__ == "__main__":
    main()
