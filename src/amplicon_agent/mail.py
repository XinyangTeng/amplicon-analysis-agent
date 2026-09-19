from __future__ import annotations

import os
import smtplib
from email.message import EmailMessage


def _require(name: str) -> str:
    value = os.getenv(name, "").strip()
    if not value:
        raise RuntimeError(f"邮件服务尚未配置：缺少 {name}")
    return value


def _truthy(name: str, default: bool = True) -> bool:
    value = os.getenv(name, "").strip().lower()
    if not value:
        return default
    return value not in {"0", "false", "no", "off"}


def send_verification_code(to_email: str, code: str) -> None:
    """通过 SMTP 发送邮箱验证码。QQ 邮箱默认 465 SSL。"""
    host = _require("SMTP_HOST")
    port = int(os.getenv("SMTP_PORT", "465"))
    username = _require("SMTP_USERNAME")
    password = _require("SMTP_PASSWORD")
    sender = os.getenv("SMTP_FROM", "").strip() or username
    use_ssl = _truthy("SMTP_USE_SSL", default=True)

    subject = os.getenv("SMTP_SUBJECT", "").strip() or "BioAgent 邮箱验证码"
    body = (
        f"您的验证码是：{code}\n\n"
        "验证码 10 分钟内有效，请勿泄露给他人。\n"
        "如果这不是您本人的操作，请忽略本邮件。\n"
    )

    message = EmailMessage()
    message["Subject"] = subject
    message["From"] = sender
    message["To"] = to_email
    message.set_content(body)

    if use_ssl:
        server = smtplib.SMTP_SSL(host, port, timeout=30)
    else:
        server = smtplib.SMTP(host, port, timeout=30)
    try:
        if not use_ssl:
            server.starttls()
        server.login(username, password)
        server.sendmail(sender, [to_email], message.as_string())
    finally:
        server.quit()
