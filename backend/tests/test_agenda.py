"""The agenda: saving it through the API, and the parser with a fake Claude."""

import json
from datetime import date
from types import SimpleNamespace

import pytest

from app.ai import agenda as ai

AGENDA = {
    "items": [
        {"topic": "Нові тарифи Pro", "owner": "Олена", "minutes": 15},
        {"topic": "Фідбек від клієнтів", "owner": "Taras", "minutes": None},
    ],
    "action_items": [{"task": "Порівняння з конкурентами", "owner": "Taras", "due": "2026-10-23"}],
}


async def test_save_agenda_keeps_the_ai_suggestion(client, meeting_payload, session):
    meeting = (await client.post("/api/v1/meetings", json=meeting_payload)).json()
    suggestion = {**AGENDA, "items": [{**AGENDA["items"][0], "owner": "Olena"}]}

    response = await client.put(
        f"/api/v1/meetings/{meeting['id']}/agenda",
        json={**AGENDA, "ai_suggestion": suggestion, "ai_model": "m", "prompt_version": "v1"},
    )

    assert response.status_code == 200, response.text
    assert response.json()["agenda"]["items"][0]["owner"] == "Олена"
    from sqlalchemy import text

    row = (
        await session.execute(
            text("SELECT ai_suggestion FROM meetings WHERE id = :id"), {"id": meeting["id"]}
        )
    ).scalar_one()
    assert row["prompt_version"] == "v1"
    assert row["agenda"]["items"][0]["owner"] == "Olena"


async def test_save_agenda_by_hand_has_no_suggestion(client, meeting_payload):
    meeting = (await client.post("/api/v1/meetings", json=meeting_payload)).json()
    response = await client.put(f"/api/v1/meetings/{meeting['id']}/agenda", json=AGENDA)
    assert response.status_code == 200
    assert len(response.json()["agenda"]["action_items"]) == 1


async def test_save_agenda_validates(client, meeting_payload):
    meeting = (await client.post("/api/v1/meetings", json=meeting_payload)).json()
    bad = {"items": [{"topic": "", "minutes": 0}]}
    response = await client.put(f"/api/v1/meetings/{meeting['id']}/agenda", json=bad)
    assert response.status_code == 422


async def test_other_users_cannot_save_an_agenda(client, meeting_payload):
    meeting = (await client.post("/api/v1/meetings", json=meeting_payload)).json()
    response = await client.put(
        f"/api/v1/meetings/{meeting['id']}/agenda", json=AGENDA, headers={"X-Test-User": "b"}
    )
    assert response.status_code == 404


# --- the parser, with a fake Bedrock client ------------------------------------


class FakeClient:
    def __init__(self, *tool_inputs):
        self.inputs = list(tool_inputs)
        self.calls = []
        self.messages = self

    def create(self, **kwargs):
        self.calls.append(kwargs)
        tool_input = self.inputs.pop(0)
        content = (
            []
            if tool_input is None
            else [SimpleNamespace(type="tool_use", id="t1", input=tool_input)]
        )
        return SimpleNamespace(
            content=content,
            stop_reason="tool_use" if content else "refusal",
            usage=SimpleNamespace(input_tokens=1000, output_tokens=200),
        )


@pytest.fixture
def fake(monkeypatch):
    def install(*inputs):
        client = FakeClient(*inputs)
        monkeypatch.setattr(ai, "_client", lambda: client)
        return client

    return install


GOOD = {"items": [{"topic": "Pricing"}], "language": "en"}


def test_parse_puts_today_and_tz_in_the_prompt(fake):
    client = fake(GOOD)
    agenda, usage = ai.parse_agenda("Mon: pricing", date(2026, 10, 22), "Europe/Kyiv")
    assert agenda.items[0].topic == "Pricing"
    prompt = client.calls[0]["messages"][0]["content"]
    assert "Thursday 2026-10-22" in prompt and "Europe/Kyiv" in prompt
    assert "<pasted_text>" in prompt
    assert usage == {"input_tokens": 1000, "output_tokens": 200}


def test_parse_retries_once_with_the_validation_error(fake):
    client = fake({"items": [{"topic": ""}], "language": "en"}, GOOD)
    agenda, usage = ai.parse_agenda("x", date(2026, 10, 22), "UTC")
    assert agenda.items[0].topic == "Pricing"
    assert usage["input_tokens"] == 2000
    retry = client.calls[1]["messages"][-1]["content"][0]
    assert retry["type"] == "tool_result" and retry["is_error"]


def test_parse_gives_up_after_two_invalid_answers(fake):
    fake({"language": "en"}, {"language": "en"})
    with pytest.raises(ai.AgendaParseError):
        ai.parse_agenda("x", date(2026, 10, 22), "UTC")


def test_parse_reports_a_refusal(fake):
    fake(None)
    with pytest.raises(ai.AgendaParseError, match="refusal"):
        ai.parse_agenda("x", date(2026, 10, 22), "UTC")


def test_cost():
    usage = {"input_tokens": 5500, "output_tokens": 300}
    assert ai.cost_usd("anthropic.claude-opus-5-5", usage) == pytest.approx(0.028)


# --- the Lambda handler ------------------------------------------------------


def _event(token, body):
    return {"headers": {"Authorization": f"Bearer {token}"}, "body": json.dumps(body)}


def _own_verifier(monkeypatch, private_key):
    # A fresh verifier: its lock must belong to the handler's own event loop.
    from app.ai import agenda_lambda
    from tests.tokens import make_verifier

    verifier = make_verifier(private_key)
    monkeypatch.setattr(agenda_lambda, "get_verifier", lambda: verifier)
    return agenda_lambda


def test_handler_rejects_missing_token(monkeypatch, private_key):
    agenda_lambda = _own_verifier(monkeypatch, private_key)
    response = agenda_lambda.handler({"headers": {}, "body": "{}"}, None)
    assert response["statusCode"] == 401


def test_handler_limits_text_and_logs_cost(monkeypatch, private_key, fake, caplog):
    from tests.tokens import make_token

    agenda_lambda = _own_verifier(monkeypatch, private_key)
    token = make_token(private_key)
    body = {"text": "x" * 10_001, "today": "2026-10-22", "tz": "Europe/Kyiv"}
    assert agenda_lambda.handler(_event(token, body), None)["statusCode"] == 413

    fake(GOOD)
    body["text"] = "Mon: pricing"
    with caplog.at_level("INFO", logger="agenda-parser"):
        response = agenda_lambda.handler(_event(token, body), None)
    assert response["statusCode"] == 200, response
    assert json.loads(response["body"])["agenda"]["items"][0]["topic"] == "Pricing"
    line = json.loads(caplog.records[-1].getMessage())
    assert line["event"] == "agenda_parsed" and line["cost_usd"] > 0
    assert {"model", "prompt_version", "input_tokens", "output_tokens", "latency_ms"} <= set(line)
