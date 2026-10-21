#!/usr/bin/env python3
"""Opt-in live catalog check. Offline unit tests never depend on these servers."""
import concurrent.futures
import json
from pathlib import Path
import sys
import urllib.request

CATALOG = Path(__file__).resolve().parents[1] / "Sources/CalendarCore/Resources/catalog.json"
LIMIT = 5 * 1024 * 1024


def check(feed):
    if not feed.get("feedURL") and feed.get("fanCalendarTeamKey"):
        return feed["name"], None, "resolved on demand; no bulk requests sent to FanCalendar"
    try:
        request = urllib.request.Request(feed["feedURL"], headers={
            "User-Agent": "TeamCalendar/1.0", "Accept": "text/calendar, text/plain;q=0.8"})
        with urllib.request.urlopen(request, timeout=35) as response:
            data = response.read(LIMIT + 1)
            if len(data) > LIMIT:
                return feed["name"], False, "larger than preview limit"
            text = data.decode("utf-8-sig").strip()
            if not text.startswith("BEGIN:VCALENDAR") or not text.endswith("END:VCALENDAR"):
                return feed["name"], False, "not an iCalendar response"
            return feed["name"], True, f'{text.count("BEGIN:VEVENT")} events, {len(data):,} bytes'
    except Exception as error:
        return feed["name"], False, str(error)


if __name__ == "__main__":
    feeds = json.loads(CATALOG.read_text())
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:
        results = list(executor.map(check, feeds))
    for name, passed, detail in results:
        print(f'{"DEFERRED" if passed is None else "PASS" if passed else "FAIL"} {name}: {detail}')
    failures = sum(result[1] is False for result in results)
    deferred = sum(result[1] is None for result in results)
    direct = len(results) - deferred
    print(f"\n{direct - failures}/{direct} direct feeds passed; {deferred} on-demand sources")
    sys.exit(bool(failures))
