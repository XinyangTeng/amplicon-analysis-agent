from __future__ import annotations

from mcp.server.fastmcp import FastMCP

from .service import AgentService


mcp = FastMCP(
    "Amplicon Analysis Agent",
    instructions=(
        "Inspect inputs before preparing a plan. Never run a plan before the user explicitly approves it. "
        "Explain blockers, warnings, statistical limits, and the evidence supporting every conclusion."
    ),
)
service = AgentService()


@mcp.tool()
def inspect_amplicon_inputs(abundance: str, taxonomy: str, metadata: str, group_column: str) -> dict:
    """Inspect three amplicon tables without running analysis."""
    return service.inspect(abundance, taxonomy, metadata, group_column)


@mcp.tool()
def prepare_amplicon_analysis(abundance: str, taxonomy: str, metadata: str, group_column: str,
                               modules: list[str] | None = None, permutations: int = 999,
                               top_n: int = 10) -> dict:
    """Create an immutable analysis contract. This does not execute analysis."""
    return service.prepare(abundance, taxonomy, metadata, group_column, modules, permutations, top_n)


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


def main() -> None:
    mcp.run(transport="stdio")


if __name__ == "__main__":
    main()

