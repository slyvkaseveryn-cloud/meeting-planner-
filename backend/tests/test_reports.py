"""Pure parts of the weekly report: week arithmetic, file names, trigger detection."""

import json
from datetime import date

import pytest

from app.reports.lambda_handler import detect_trigger
from app.reports.weekly import last_full_week, previous_week, report_key, week_bounds


def test_week_bounds_start_on_monday_in_app_timezone():
    start, end = week_bounds("2026-W40")
    assert start.date() == date(2026, 9, 28)
    assert (end - start).days == 7
    assert start.tzinfo is not None


def test_previous_week_crosses_the_year():
    assert previous_week("2026-W01") == "2025-W52"


def test_last_full_week_is_the_week_before_today():
    assert last_full_week(date(2026, 10, 5)) == "2026-W40"  # a Monday


def test_same_week_same_key():
    assert report_key("2026-W40") == report_key("2026-W40") == "reports/2026-W40.csv"


@pytest.mark.parametrize("bad", ["2026-40", "2026-W00", "2026-W54", "last week"])
def test_bad_weeks_are_refused(bad):
    with pytest.raises(ValueError):
        report_key(bad)


def _sqs(body: dict) -> dict:
    return {"Records": [{"eventSource": "aws:sqs", "body": json.dumps(body)}]}


def test_detect_trigger():
    assert detect_trigger({"source": "schedule"}) == "schedule"
    assert detect_trigger(_sqs({"week": None, "source": "schedule"})) == "schedule"
    assert detect_trigger(_sqs({"week": "2026-W39", "source": "make"})) == "sqs"
    assert detect_trigger({"week": "2026-W39"}) == "direct"
