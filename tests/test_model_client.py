from __future__ import annotations

from typing import Any

from amplicon_agent import model_client


class FakeResponse:
    def __init__(self, value: dict[str, Any]) -> None:
        self.value = value
        self.status_code = 200
        self.text = ""

    def raise_for_status(self) -> None:
        return None

    def json(self) -> dict[str, Any]:
        return self.value


class FakeClient:
    response: dict[str, Any] = {}
    last_url = ""
    last_headers: dict[str, str] = {}
    last_payload: dict[str, Any] = {}

    def __init__(self, timeout: int) -> None:
        self.timeout = timeout

    def __enter__(self) -> "FakeClient":
        return self

    def __exit__(self, *args: object) -> None:
        return None

    def post(
        self, url: str, *, headers: dict[str, str], json: dict[str, Any]
    ) -> FakeResponse:
        type(self).last_url = url
        type(self).last_headers = headers
        type(self).last_payload = json
        return FakeResponse(type(self).response)


def test_openai_compatible_adapter(monkeypatch) -> None:
    FakeClient.response = {"choices": [{"message": {"content": "OK"}}]}
    monkeypatch.setattr(model_client.httpx, "Client", FakeClient)
    result = model_client._openai_completion(
        {
            "base_url": "https://example.test/v1",
            "model": "example-model",
            "api_key": "secret",
            "timeout_seconds": 10,
        },
        [{"role": "user", "content": "hello"}],
        {"type": "json_object"},
    )
    assert result == "OK"
    assert FakeClient.last_url == "https://example.test/v1/chat/completions"
    assert FakeClient.last_headers["Authorization"] == "Bearer secret"
    assert FakeClient.last_payload["response_format"] == {"type": "json_object"}


def test_anthropic_adapter_separates_system_prompt(monkeypatch) -> None:
    FakeClient.response = {
        "content": [
            {"type": "text", "text": "part one"},
            {"type": "text", "text": " part two"},
        ]
    }
    monkeypatch.setattr(model_client.httpx, "Client", FakeClient)
    result = model_client._anthropic_completion(
        {
            "base_url": "https://api.example.test",
            "model": "example-claude",
            "api_key": "secret",
            "timeout_seconds": 10,
        },
        [
            {"role": "system", "content": "scientific only"},
            {"role": "user", "content": "interpret"},
        ],
    )
    assert result == "part one part two"
    assert FakeClient.last_url == "https://api.example.test/v1/messages"
    assert FakeClient.last_headers["x-api-key"] == "secret"
    assert FakeClient.last_payload["system"] == "scientific only"
    assert FakeClient.last_payload["messages"] == [
        {"role": "user", "content": "interpret"}
    ]


def test_blank_environment_values_do_not_override_web_config(
    tmp_path, monkeypatch
) -> None:
    monkeypatch.setenv("AMPLICON_WORKSPACE", str(tmp_path))
    for name in (
        "MODEL_PROVIDER",
        "MODEL_PROTOCOL",
        "MODEL_BASE_URL",
        "MODEL_NAME",
    ):
        monkeypatch.setenv(name, "")
    model_client.save_model_config(
        "custom",
        "openai",
        "http://localhost:11434/v1",
        "local-model",
        clear_api_key=True,
    )
    config = model_client.model_config()
    assert config["provider"] == "custom"
    assert config["base_url"] == "http://localhost:11434/v1"
    assert config["model"] == "local-model"
