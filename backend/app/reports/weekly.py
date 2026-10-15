"""Build the weekly meetings report as CSV.

The week is always a parameter ("2026-W40"): this module never decides which
week to report on, so an old report can be rebuilt by asking for its week. The
same week always maps to the same file name, which makes a rebuild overwrite
one file instead of adding another (the task is idempotent).

Run it locally against the compose database:

    docker compose exec backend python -m app.reports.weekly 2026-W40
"""

import asyncio
import csv
import io
import re
import sys
from dataclasses import dataclass
from datetime import date, datetime, timedelta

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.db import SessionFactory
from app.models import Meeting, User

WEEK_RE = re.compile(r"^(\d{4})-W(\d{2})$")


def parse_week(week: str) -> tuple[int, int]:
    """'2026-W40' -> (2026, 40); raises ValueError for anything else."""
    match = WEEK_RE.match(week)
    if not match:
        raise ValueError(f"week must look like 2026-W40, got {week!r}")
    year, number = int(match[1]), int(match[2])
    date.fromisocalendar(year, number, 1)  # raises for W00 or W54
    return year, number


def week_bounds(week: str) -> tuple[datetime, datetime]:
    """Monday 00:00 to the next Monday 00:00 in the app's timezone."""
    year, number = parse_week(week)
    monday = date.fromisocalendar(year, number, 1)
    start = datetime.combine(monday, datetime.min.time(), tzinfo=settings.tz)
    return start, start + timedelta(days=7)


def previous_week(week: str) -> str:
    start, _ = week_bounds(week)
    year, number, _ = (start - timedelta(days=7)).isocalendar()
    return f"{year}-W{number:02d}"


def last_full_week(today: date | None = None) -> str:
    """The ISO week before the one containing `today` (in the app's timezone)."""
    today = today or datetime.now(settings.tz).date()
    year, number, _ = (today - timedelta(days=7)).isocalendar()
    return f"{year}-W{number:02d}"


def report_key(week: str) -> str:
    """Where the report for `week` lives in S3. Same week, same key."""
    parse_week(week)
    return f"reports/{week}.csv"


@dataclass
class WeekRows:
    meetings: list[Meeting]
    owners: dict[str, str]  # owner id -> email (or the id when there is none)

    @property
    def count(self) -> int:
        return len(self.meetings)

    @property
    def hours(self) -> float:
        return sum(_hours(m) for m in self.meetings)


def _hours(meeting: Meeting) -> float:
    return (meeting.ends_at - meeting.starts_at).total_seconds() / 3600


async def _load_week(session: AsyncSession, week: str) -> WeekRows:
    start, end = week_bounds(week)
    meetings = list(
        (
            await session.scalars(
                select(Meeting)
                .where(Meeting.starts_at >= start, Meeting.starts_at < end)
                .order_by(Meeting.starts_at)
            )
        ).all()
    )
    owner_ids = {m.owner_id for m in meetings if m.owner_id}
    owners: dict[str, str] = {}
    if owner_ids:
        for user in (await session.scalars(select(User).where(User.id.in_(owner_ids)))).all():
            owners[user.id] = user.email or user.id
    return WeekRows(meetings, owners)


def _fmt(value: float) -> str:
    return f"{value:.2f}"


def _change(now: float, before: float) -> str:
    if before == 0:
        return "n/a" if now == 0 else "new"
    return f"{(now - before) / before * 100:+.0f}%"


async def build_weekly_report(week: str, session: AsyncSession | None = None) -> bytes:
    """Query the meetings of one ISO week (e.g. "2026-W40") and return the CSV."""
    if session is None:
        async with SessionFactory() as own:
            return await build_weekly_report(week, own)

    before_week = previous_week(week)
    this, before = await _load_week(session, week), await _load_week(session, before_week)

    out = io.StringIO()
    w = csv.writer(out)
    w.writerow(["Weekly meetings report", week])
    start, end = week_bounds(week)
    w.writerow(["Period", start.date().isoformat(), (end - timedelta(days=1)).date().isoformat()])
    w.writerow(["Timezone", settings.app_timezone])
    w.writerow([])

    w.writerow(["Metric", week, before_week, "Change"])
    w.writerow(["Meetings", this.count, before.count, _change(this.count, before.count)])
    hours_change = _change(this.hours, before.hours)
    w.writerow(["Hours in meetings", _fmt(this.hours), _fmt(before.hours), hours_change])
    w.writerow([])

    w.writerow(["Top 5 longest meetings"])
    w.writerow(["Title", "Starts at", "Duration (h)", "Participants"])
    longest = sorted(this.meetings, key=_hours, reverse=True)[:5]
    for m in longest:
        starts = m.starts_at.astimezone(settings.tz).isoformat()
        w.writerow([m.name, starts, _fmt(_hours(m)), len(m.participants)])
    if not longest:
        w.writerow(["(no meetings this week)"])
    w.writerow([])

    w.writerow(["Per organiser"])
    w.writerow(["Organiser", "Meetings", "Hours"])
    per_owner: dict[str, list[Meeting]] = {}
    for m in this.meetings:
        per_owner.setdefault(this.owners.get(m.owner_id or "", "(no owner)"), []).append(m)
    for owner, items in sorted(per_owner.items(), key=lambda kv: -len(kv[1])):
        w.writerow([owner, len(items), _fmt(sum(_hours(m) for m in items))])

    return out.getvalue().encode("utf-8")


if __name__ == "__main__":
    target = sys.argv[1] if len(sys.argv) > 1 else last_full_week()
    sys.stdout.write(asyncio.run(build_weekly_report(target)).decode())
