"""agenda-parser: the Lambda behind its own function URL, outside the VPC.

It receives text and returns JSON. It needs no database and never writes
anything: saving goes through the normal API.
"""

import asyncio
import json
import logging
import time
from datetime import date

from app.ai.agenda import (
    MAX_TEXT_CHARS,
    PROMPT_VERSION,
    AgendaParseError,
    cost_usd,
    parse_agenda,
)
from app.auth import AuthError, get_verifier
from app.config import settings

log = logging.getLogger("agenda-parser")
log.setLevel(logging.INFO)
_loop = asyncio.new_event_loop()


def _response(status: int, body: dict) -> dict:
    return {
        "statusCode": status,
        "headers": {"content-type": "application/json"},
        "body": json.dumps(body, ensure_ascii=False),
    }


def _bearer(event: dict) -> str:
    headers = {k.lower(): v for k, v in (event.get("headers") or {}).items()}
    value = headers.get("authorization", "")
    return value[7:] if value.lower().startswith("bearer ") else ""


def handler(event, context):
    # Every call costs money: no valid Cognito access token, no parse.
    try:
        user = _loop.run_until_complete(get_verifier().verify(_bearer(event)))
    except AuthError as e:
        return _response(401, {"error": str(e)})

    try:
        body = json.loads(event.get("body") or "{}")
        text = str(body["text"])
        today = date.fromisoformat(body["today"])
        tz = str(body.get("tz") or settings.app_timezone)
    except (ValueError, KeyError, TypeError):
        return _response(400, {"error": "send JSON with text, today (YYYY-MM-DD) and tz"})
    if not text.strip():
        return _response(400, {"error": "the text is empty"})
    if len(text) > MAX_TEXT_CHARS:
        return _response(413, {"error": f"the text is longer than {MAX_TEXT_CHARS} characters"})

    started = time.monotonic()
    try:
        agenda, usage = parse_agenda(text, today, tz)
    except AgendaParseError as e:
        return _response(422, {"error": str(e)})
    except Exception as e:  # Bedrock throttling, outage, ...
        name = type(e).__name__
        status = 429 if "RateLimit" in name or "Throttl" in name else 503
        log.warning("agenda parse failed: %s: %s", name, e)
        return _response(status, {"error": "the AI service is busy, try again or type it in"})

    log.info(
        json.dumps(
            {
                "event": "agenda_parsed",
                "user": user.sub,
                "model": settings.parser_model,
                "prompt_version": PROMPT_VERSION,
                **usage,
                "latency_ms": int((time.monotonic() - started) * 1000),
                "cost_usd": cost_usd(settings.parser_model, usage),
                "chars": len(text),
            }
        )
    )
    return _response(
        200,
        {
            "agenda": agenda.model_dump(mode="json"),
            "model": settings.parser_model,
            "prompt_version": PROMPT_VERSION,
        },
    )
