import json

from fastapi.testclient import TestClient

from zino_agents.main import app

client = TestClient(app)
AUTH = {"Authorization": "Bearer test-key"}


def test_healthz_needs_no_auth():
    r = client.get("/healthz")
    assert r.status_code == 200
    assert r.json()["status"] == "ok"
    assert "zino-echo" in r.json()["agents"]


def test_models_requires_auth():
    assert client.get("/v1/models").status_code == 401
    assert client.get("/v1/models", headers={"Authorization": "Bearer wrong"}).status_code == 401


def test_models_lists_agents():
    r = client.get("/v1/models", headers=AUTH)
    assert r.status_code == 200
    ids = {m["id"] for m in r.json()["data"]}
    assert {"zino-echo", "zino-assistant"} <= ids


def test_unknown_model_is_404():
    r = client.post(
        "/v1/chat/completions",
        headers=AUTH,
        json={"model": "does-not-exist", "messages": [{"role": "user", "content": "hi"}]},
    )
    assert r.status_code == 404


def test_non_streaming_completion():
    r = client.post(
        "/v1/chat/completions",
        headers=AUTH,
        json={"model": "zino-echo", "messages": [{"role": "user", "content": "hello world"}]},
    )
    assert r.status_code == 200
    body = r.json()
    assert body["object"] == "chat.completion"
    assert "hello world" in body["choices"][0]["message"]["content"]


def test_streaming_completion_emits_valid_sse():
    r = client.post(
        "/v1/chat/completions",
        headers=AUTH,
        json={
            "model": "zino-echo",
            "stream": True,
            "messages": [{"role": "user", "content": "alpha beta"}],
        },
    )
    assert r.status_code == 200
    assert r.headers["content-type"].startswith("text/event-stream")

    lines = [ln for ln in r.text.split("\n\n") if ln.strip()]
    assert lines[-1] == "data: [DONE]"

    bodies = [json.loads(ln[len("data: ") :]) for ln in lines[:-1]]
    assert bodies[0]["choices"][0]["delta"]["role"] == "assistant"
    assert bodies[-1]["choices"][0]["finish_reason"] == "stop"

    text = "".join(b["choices"][0]["delta"].get("content", "") for b in bodies)
    assert "alpha beta" in text


def test_assistant_without_upstream_key_reports_error_in_band():
    # Must not 500 — the user needs an actionable message inside the chat.
    r = client.post(
        "/v1/chat/completions",
        headers=AUTH,
        json={"model": "zino-assistant", "messages": [{"role": "user", "content": "hi"}]},
    )
    assert r.status_code == 200
    assert "ZINO_UPSTREAM_API_KEY" in r.json()["choices"][0]["message"]["content"]


def test_multimodal_content_does_not_break_request_parsing():
    r = client.post(
        "/v1/chat/completions",
        headers=AUTH,
        json={
            "model": "zino-echo",
            "messages": [{"role": "user", "content": [{"type": "text", "text": "look"}]}],
        },
    )
    assert r.status_code == 200
