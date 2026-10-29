"""islands-calendar: the work calendar's events from today to a week on,
for the bar (shell/Events.qml), written to
$XDG_CACHE_HOME/islands/calendar.json.

The calendar's secret iCal address is a password, so it stays in the
keyring (secret-tool store service islands-calendar) and out of the Nix
store, which anyone on the machine can read, and out of every message.
"""

import datetime as dt
import json
import os
import re
import subprocess
import sys
import tempfile
import urllib.request
from urllib.parse import urlparse

import icalendar
import recurring_ical_events

SECRET_TOOL = "@secretTool@"
DAYS = 7
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


def main():
    calendar = icalendar.Calendar.from_ical(fetch(address()))
    owner = str(calendar.get("X-WR-CALNAME", "")).lower()
    today = dt.datetime.combine(dt.date.today(), dt.time()).astimezone()
    events = []
    for event in recurring_ical_events.of(calendar).between(today, today + dt.timedelta(days=DAYS)):
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
