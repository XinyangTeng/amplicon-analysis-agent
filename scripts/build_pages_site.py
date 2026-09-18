from __future__ import annotations

import os
import shutil
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
STATIC = ROOT / "src" / "amplicon_agent" / "web_static"
OUTPUT = ROOT / "dist" / "github-pages"


def main() -> None:
    app_url = os.getenv("RENDER_APP_URL", "").strip().rstrip("/")
    canonical = os.getenv("PAGES_CANONICAL_URL", "").strip() or "./"

    if OUTPUT.exists():
        shutil.rmtree(OUTPUT)
    assets = OUTPUT / "assets"
    assets.mkdir(parents=True)

    page = (STATIC / "landing.html").read_text(encoding="utf-8")
    page = page.replace("{{CANONICAL_URL}}", canonical)
    page = page.replace('href="/assets/', 'href="./assets/')
    page = page.replace('src="/assets/', 'src="./assets/')
    page = page.replace('href="/"', 'href="./"')

    if app_url:
        for path in ("/login", "/privacy", "/api/health"):
            page = page.replace(f'href="{path}"', f'href="{app_url}{path}"')
    else:
        page = page.replace(
            "已有邀请码？开始你的第一次分析",
            "分析服务正在部署",
        )
        page = page.replace(
            "没有邀请码请联系项目维护者申请名额。",
            "公开介绍页已经上线，分析入口将在 Render 地址配置后开放。",
        )
        for path in ("/login", "/privacy", "/api/health"):
            page = page.replace(f'href="{path}"', 'href="#" aria-disabled="true"')

    (OUTPUT / "index.html").write_text(page, encoding="utf-8")
    shutil.copy2(STATIC / "style.css", assets / "style.css")
    shutil.copy2(STATIC / "icon.svg", assets / "icon.svg")
    (OUTPUT / ".nojekyll").write_text("", encoding="utf-8")


if __name__ == "__main__":
    main()
