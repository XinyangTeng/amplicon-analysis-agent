from __future__ import annotations

import argparse
import json
import os
from pathlib import Path

from amplicon_agent.auth import AuthStore


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description="管理 BioAgent 内测访问")
    value.add_argument(
        "--workspace",
        help="服务工作目录；默认读取 AMPLICON_WORKSPACE",
    )
    commands = value.add_subparsers(dest="command", required=True)
    invite = commands.add_parser("create-invite", help="生成邀请码")
    invite.add_argument("--label", default="internal-test")
    invite.add_argument("--uses", type=int, default=1)
    invite.add_argument("--days", type=int, default=30)
    commands.add_parser("list-invites", help="列出邀请码记录（不显示原始邀请码）")
    revoke = commands.add_parser("revoke-invite", help="撤销邀请码")
    revoke.add_argument("invite_id")
    return value


def main() -> None:
    args = parser().parse_args()
    if args.workspace:
        workspace = Path(args.workspace).resolve()
        workspace.mkdir(parents=True, exist_ok=True)
        os.environ["AMPLICON_WORKSPACE"] = str(workspace)
    store = AuthStore()
    if args.command == "create-invite":
        code = store.create_invite(
            label=args.label,
            max_uses=args.uses,
            valid_days=args.days,
        )
        print(code)
    elif args.command == "list-invites":
        print(json.dumps(store.list_invites(), ensure_ascii=False, indent=2))
    elif args.command == "revoke-invite":
        store.revoke_invite(args.invite_id)
        print("revoked")


if __name__ == "__main__":
    main()
