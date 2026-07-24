from __future__ import annotations

import argparse
import json

from amplicon_agent.report_builder import build_analysis_report


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Deterministically scan an amplicon run directory and rebuild its report."
    )
    parser.add_argument("run_directory")
    args = parser.parse_args()
    print(json.dumps(build_analysis_report(args.run_directory), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
