from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

import httpx

from .security import workspace_root


MODEL_PRESETS: dict[str, dict[str, str]] = {
    "openai_compatible": {
        "label": "OpenAI 兼容接口",
        "protocol": "openai",
        "base_url": "https://api.openai.com/v1",
        "model": "gpt-4.1-mini",
    },
    "deepseek": {
        "label": "DeepSeek",
        "protocol": "openai",
        "base_url": "https://api.deepseek.com",
        "model": "deepseek-chat",
    },
    "qwen": {
        "label": "通义千问兼容接口",
        "protocol": "openai",
        "base_url": "https://dashscope.aliyuncs.com/compatible-mode/v1",
        "model": "qwen-plus",
    },
    "anthropic": {
        "label": "Anthropic Claude",
        "protocol": "anthropic",
        "base_url": "https://api.anthropic.com",
        "model": "claude-sonnet-4-5",
    },
    "custom": {
        "label": "自定义接口",
        "protocol": "openai",
        "base_url": "http://localhost:11434/v1",
        "model": "your-model-name",
    },
}

_runtime_api_key: str | None = None


def _config_path() -> Path:
    path = workspace_root() / ".amplicon-agent" / "model_config.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    return path


def _read_saved_config() -> dict[str, Any]:
    path = _config_path()
    if not path.exists():
        return {}
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise RuntimeError(f"模型配置文件无法读取：{exc}") from exc
    if not isinstance(value, dict):
        raise RuntimeError("模型配置文件必须是 JSON 对象")
    return value


def _validated_base_url(value: str) -> str:
    url = value.strip().rstrip("/")
    parsed = urlparse(url)
    if parsed.scheme not in {"http", "https"} or not parsed.hostname:
        raise ValueError("模型接口地址必须是有效的 http:// 或 https:// 地址")
    if parsed.username or parsed.password or parsed.query or parsed.fragment:
        raise ValueError("模型接口地址不能包含账号、密码、查询参数或片段")
    return url


def model_presets() -> list[dict[str, str]]:
    return [{"id": key, **value} for key, value in MODEL_PRESETS.items()]


def model_config() -> dict[str, Any]:
    saved = _read_saved_config()
    provider = os.getenv("MODEL_PROVIDER", "").strip() or str(
        saved.get("provider", "openai_compatible")
    )
    if provider not in MODEL_PRESETS:
        provider = "custom"
    preset = MODEL_PRESETS[provider]
    protocol = os.getenv("MODEL_PROTOCOL", "").strip() or str(
        saved.get("protocol", preset["protocol"])
    )
    if protocol not in {"openai", "anthropic"}:
        raise ValueError("MODEL_PROTOCOL 只能是 openai 或 anthropic")
    environment_key = os.getenv("MODEL_API_KEY")
    saved_key = str(saved.get("api_key", "")).strip()
    api_key = environment_key or _runtime_api_key or saved_key
    source = "environment" if environment_key else "runtime" if _runtime_api_key else "saved" if saved_key else "none"
    return {
        "provider": provider,
        "protocol": protocol,
        "base_url": _validated_base_url(
            os.getenv("MODEL_BASE_URL", "").strip()
            or str(saved.get("base_url", preset["base_url"]))
        ),
        "model": (
            os.getenv("MODEL_NAME", "").strip()
            or str(saved.get("model", preset["model"])).strip()
        ),
        "api_key": api_key,
        "api_key_configured": bool(api_key),
        "api_key_source": source,
        "timeout_seconds": int(os.getenv("MODEL_TIMEOUT_SECONDS", "180")),
    }


def public_model_config() -> dict[str, Any]:
    config = model_config()
    return {key: value for key, value in config.items() if key not in {"api_key", "timeout_seconds"}}


def save_model_config(
    provider: str,
    protocol: str,
    base_url: str,
    model: str,
    *,
    api_key: str | None = None,
    persist_api_key: bool = False,
    clear_api_key: bool = False,
) -> dict[str, Any]:
    global _runtime_api_key
    if provider not in MODEL_PRESETS:
        raise ValueError(f"不支持的模型提供商：{provider}")
    if protocol not in {"openai", "anthropic"}:
        raise ValueError("协议只能是 openai 或 anthropic")
    clean_model = model.strip()
    if not clean_model:
        raise ValueError("模型名称不能为空")
    saved = _read_saved_config()
    new_value: dict[str, Any] = {
        "provider": provider,
        "protocol": protocol,
        "base_url": _validated_base_url(base_url),
        "model": clean_model,
    }
    if clear_api_key:
        _runtime_api_key = None
    elif api_key and api_key.strip():
        if persist_api_key:
            new_value["api_key"] = api_key.strip()
            _runtime_api_key = None
        else:
            _runtime_api_key = api_key.strip()
    elif saved.get("api_key") and not clear_api_key:
        new_value["api_key"] = saved["api_key"]
    path = _config_path()
    path.write_text(json.dumps(new_value, ensure_ascii=False, indent=2), encoding="utf-8")
    try:
        path.chmod(0o600)
    except OSError:
        pass
    return public_model_config()


def _openai_completion(
    config: dict[str, Any],
    messages: list[dict[str, str]],
    response_format: dict[str, Any] | None,
) -> str:
    payload: dict[str, Any] = {
        "model": config["model"],
        "messages": messages,
        "temperature": 0.2,
    }
    if response_format:
        payload["response_format"] = response_format
    with httpx.Client(timeout=config["timeout_seconds"]) as client:
        response = client.post(
            f"{config['base_url']}/chat/completions",
            headers={"Authorization": f"Bearer {config['api_key']}"},
            json=payload,
        )
        response.raise_for_status()
        data = response.json()
    try:
        return str(data["choices"][0]["message"]["content"])
    except (KeyError, IndexError, TypeError) as exc:
        raise RuntimeError("模型返回格式不符合 OpenAI Chat Completions 规范") from exc


def _anthropic_completion(config: dict[str, Any], messages: list[dict[str, str]]) -> str:
    system_parts = [item["content"] for item in messages if item.get("role") == "system"]
    conversation = [
        {"role": item["role"], "content": item["content"]}
        for item in messages
        if item.get("role") in {"user", "assistant"}
    ]
    payload: dict[str, Any] = {
        "model": config["model"],
        "max_tokens": 4096,
        "temperature": 0.2,
        "messages": conversation,
    }
    if system_parts:
        payload["system"] = "\n\n".join(system_parts)
    suffix = "/messages" if config["base_url"].endswith("/v1") else "/v1/messages"
    with httpx.Client(timeout=config["timeout_seconds"]) as client:
        response = client.post(
            f"{config['base_url']}{suffix}",
            headers={
                "x-api-key": config["api_key"],
                "anthropic-version": "2023-06-01",
                "content-type": "application/json",
            },
            json=payload,
        )
        response.raise_for_status()
        data = response.json()
    try:
        return "".join(
            str(item.get("text", ""))
            for item in data["content"]
            if item.get("type") == "text"
        )
    except (KeyError, TypeError) as exc:
        raise RuntimeError("模型返回格式不符合 Anthropic Messages 规范") from exc


def chat_completion(
    messages: list[dict[str, str]],
    *,
    response_format: dict[str, Any] | None = None,
) -> str:
    config = model_config()
    if not config["api_key"]:
        raise RuntimeError("尚未设置模型 API Key；请在模型设置中填写，或设置 MODEL_API_KEY")
    if not config["model"]:
        raise RuntimeError("尚未设置模型名称")
    try:
        if config["protocol"] == "anthropic":
            return _anthropic_completion(config, messages)
        return _openai_completion(config, messages, response_format)
    except httpx.HTTPStatusError as exc:
        detail = exc.response.text[:500]
        raise RuntimeError(f"模型接口返回 HTTP {exc.response.status_code}：{detail}") from exc
    except httpx.HTTPError as exc:
        raise RuntimeError(f"无法连接模型接口：{exc}") from exc
