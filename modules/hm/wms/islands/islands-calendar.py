"""islands-calendar: the work calendar's events from last month to the month
after next, for the bar (shell/Events.qml), written to
$XDG_CACHE_HOME/islands/calendar.json.

The calendar's secret iCal address is a password, so it stays in the
keyring (secret-tool store service islands-calendar) and out of the Nix
store, which anyone on the machine can read, and out of every message.
"""

import base64
import datetime as dt
import json
import os
import re
import subprocess
import sys
import tempfile
import urllib.request
from urllib.parse import quote, urlparse

import icalendar
import recurring_ical_events

SECRET_TOOL = "@secretTool@"
# Where a meeting is joined, ahead of other links in an event
CALL_HOSTS = ("meet.google.com", "zoom.us", "teams.microsoft.com", "gather")
URL = re.compile(r"https?://[^\s\"'<>]+")


def address():
    found = subprocess.run(
        [SECRET_TOOL, "lookup", "service", "islands-calendar"],
        capture_output=True,
        text=True,
    ).stdout.strip()
    if not found:
        sys.exit("no calendar address in the keyring (service islands-calendar)")
    return found


def fetch(url):
    try:
        with urllib.request.urlopen(url, timeout=30) as reply:
            return reply.read()
    except OSError as e:
        # Never the address itself: it's the password
        sys.exit(f"can't fetch the calendar: {type(e).__name__}")


def epoch_ms(when):
    if not isinstance(when, dt.datetime):
        when = dt.datetime.combine(when, dt.time())
    if when.tzinfo is None:
        when = when.astimezone()
    return int(when.timestamp() * 1000)


def declined(event, owner):
    attendees = event.get("ATTENDEE", [])
    if not isinstance(attendees, list):
        attendees = [attendees]
    return any(
        str(a).lower() == f"mailto:{owner}" and a.params.get("PARTSTAT") == "DECLINED"
        for a in attendees
    )


def join_link(event):
    conference = str(event.get("X-GOOGLE-CONFERENCE", ""))
    if conference:
        return conference
    location = URL.findall(str(event.get("LOCATION", "")))
    links = location + URL.findall(str(event.get("DESCRIPTION", "")))
    for link in links:
        if any(host in (urlparse(link).hostname or "") for host in CALL_HOSTS):
            return link
    return location[0] if location else ""


def event_page(event, owner, start):
    """The event in Google Calendar, else the day it's on. Google's page
    for an event is eid=base64("<event id> <calendar>"); an event made in
    Google has its id as the UID's local part, an occurrence of a recurring
    one with "_<original start in UTC>" after it."""
    uid = str(event.get("UID", ""))
    account = quote(owner)
    if uid.endswith("@google.com") and owner:
        event_id = uid.removesuffix("@google.com")
        if "RRULE" in event or "RECURRENCE-ID" in event:
            original = event["RECURRENCE-ID"].dt if "RECURRENCE-ID" in event else start
            if isinstance(original, dt.datetime):
                event_id += "_" + original.astimezone(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
            else:
                event_id += "_" + original.strftime("%Y%m%d")
        eid = base64.b64encode(f"{event_id} {owner}".encode()).decode().rstrip("=")
        return f"https://calendar.google.com/calendar/event?eid={quote(eid)}&authuser={account}"
    day = start.astimezone().date() if isinstance(start, dt.datetime) else start
    return f"https://calendar.google.com/calendar/r/day/{day.year}/{day.month}/{day.day}?authuser={account}"


def main():
    calendar = icalendar.Calendar.from_ical(fetch(address()))
    owner = str(calendar.get("X-WR-CALNAME", "")).lower()
    # Last month to the end of the month after next: the notification
    # centre's calendar puts a dot on each day with an event
    this_month = dt.date.today().replace(day=1)
    first = (this_month - dt.timedelta(days=1)).replace(day=1)
    last = (this_month + dt.timedelta(days=95)).replace(day=1)
    start, end = (dt.datetime.combine(d, dt.time()).astimezone() for d in (first, last))
    events = []
    for event in recurring_ical_events.of(calendar).between(start, end):
        if str(event.get("STATUS", "")).upper() == "CANCELLED" or declined(event, owner):
            continue
        start = event["DTSTART"].dt
        end = event["DTEND"].dt if "DTEND" in event else start
        events.append({
            "title": str(event.get("SUMMARY", "")) or "(No title)",
            "start": epoch_ms(start),
            "end": epoch_ms(end),
            "allDay": not isinstance(start, dt.datetime),
            "join": join_link(event),
            "page": event_page(event, owner, start),
            "location": str(event.get("LOCATION", "")),
        })
    events.sort(key=lambda e: (e["start"], not e["allDay"]))

    cache = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"), "islands")
    os.makedirs(cache, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", dir=cache, delete=False) as out:
        json.dump({"fetched": epoch_ms(dt.datetime.now().astimezone()), "events": events}, out)
    os.chmod(out.name, 0o600)
    os.replace(out.name, os.path.join(cache, "calendar.json"))


main()
