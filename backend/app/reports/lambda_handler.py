"""report-builder: the Lambda that turns a report request into reports/<week>.csv.

Runs from the backend image with ImageConfig.Command set to
app.reports.lambda_handler.handler. It accepts both shapes it can be started
with:

- a direct invocation: {"source": "schedule", "week": null}
- an SQS event: {"Records": [{"eventSource": "aws:sqs", "body": "{...}"}]}

It only ever writes the report to S3. Sending it is someone else's job: the
mailer reacts to the ObjectCreated event and this function does not know it
exists.
"""

import asyncio
import json
import logging
import os

from app.reports.weekly import build_weekly_report, last_full_week, parse_week, report_key

log = logging.getLogger("report-builder")
log.setLevel(logging.INFO)

# One loop for the life of the execution environment: the pooled asyncpg
# connections belong to the loop that opened them.
_loop = asyncio.new_event_loop()
_s3 = None


def _s3_client():
    # boto3 ships with the Lambda Python runtime; imported lazily so the
    # trigger logic can be tested without it.
    global _s3
    if _s3 is None:
        import boto3

        _s3 = boto3.client("s3")
    return _s3


def detect_trigger(event: dict) -> str:
    """Which event started this run: schedule, sqs (an on-demand request) or direct."""
    records = event.get("Records") or []
    if records and records[0].get("eventSource") == "aws:sqs":
        body = _sqs_body(records[0])
        # The schedule sends its message through the queue; say so.
        return "schedule" if body.get("source") == "schedule" else "sqs"
    if event.get("source") == "schedule":
        return "schedule"
    return "direct"


def _sqs_body(record: dict) -> dict:
    try:
        body = json.loads(record.get("body") or "{}")
    except json.JSONDecodeError:
        return {}
    return body if isinstance(body, dict) else {}


def _payload(event: dict) -> dict:
    records = event.get("Records") or []
    if records and records[0].get("eventSource") == "aws:sqs":
        return _sqs_body(records[0])
    return event


def handler(event, context):
    payload = _payload(event)
    trigger = detect_trigger(event)
    week = payload.get("week") or last_full_week()
    parse_week(week)
    # The line submitted for the lab: which event started the function.
    log.info(
        "report-builder triggered trigger=%s week=%s",
        trigger,
        week,
        extra={"trigger": trigger, "week": week, "source": payload.get("source")},
    )

    # Lets you watch a message go to the DLQ after three failed attempts.
    if week == os.environ.get("REPORT_FAIL_WEEK"):
        raise RuntimeError(f"REPORT_FAIL_WEEK is set to {week}: failing on purpose")

    body = _loop.run_until_complete(build_weekly_report(week))
    key = report_key(week)
    bucket = os.environ["REPORTS_BUCKET"]
    _s3_client().put_object(Bucket=bucket, Key=key, Body=body, ContentType="text/csv")
    log.info("report written key=%s bytes=%d", key, len(body))
    return {"week": week, "key": key, "trigger": trigger}
