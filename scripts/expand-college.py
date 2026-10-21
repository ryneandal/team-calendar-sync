#!/usr/bin/env python3
"""Propose Division I football options with current conference metadata.

Reads public directories only. --emit-json prints a complete catalog proposal.
FCS uses CFB Vibes' published team calendars. FBS uses FanCalendar links
resolved on demand by the app, respecting provider rate limits.
Never creates subscriptions or writes files.
"""
import argparse
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import re
import sys
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "Sources/CalendarCore/Resources/catalog.json"
SEASON = 2026
GROUPS = f"https://sports.core.api.espn.com/v2/sports/football/leagues/college-football/seasons/{SEASON}/types/2/groups/"
TEAMS = "https://www.fancalendar.app/api/teams/cfb"
FCS_SLUGS = {
    "Pennsylvania": "penn", "Central Connecticut": "central-connecticut-state",
    "Long Island University": "liu", "Grambling": "grambling-state",
    "East Tennessee State": "etsu", "SE Louisiana": "southeastern-louisiana",
    "UT Rio Grande Valley": "utrgv",
}


def request_json(url):
    request = urllib.request.Request(url.replace("http://", "https://", 1),
        headers={"Accept": "application/json", "User-Agent": "TeamCalendar/1.0 catalog maintenance"})
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def conference(configuration):
    division, reference = configuration
    info = request_json(reference)
    members = request_json(info["teams"]["$ref"] + "&limit=1000")
    identifiers = [re.search(r"/teams/(\d+)", item["$ref"])[1] for item in members["items"]]
    name = info["shortName"]
    return division, name, identifiers


def roster():
    teams = request_json(TEAMS)["teams"]
    if len(teams) != 265 or len({item["key"] for item in teams}) != 265:
        raise ValueError("College directory changed; review team coverage before rebuilding")
    children = []
    for identifier, division in [(80, "FBS"), (81, "FCS")]:
        children += [(division, item["$ref"]) for item in request_json(GROUPS + str(identifier) + "/children?limit=100")["items"]]
    membership = {}
    with ThreadPoolExecutor(max_workers=4) as pool:
        for division, name, identifiers in pool.map(conference, children):
            for identifier in identifiers:
                if identifier in membership:
                    raise ValueError(f"Conflicting conferences for team {identifier}; review realignment")
                membership[identifier] = (division, name)
    for team in teams:
        team["division"], team["conference"] = membership[team["teamId"]]
    if Counter(team["division"] for team in teams) != {"FBS": 138, "FCS": 127}:
        raise ValueError("Division counts changed; review FBS/FCS membership")
    # UTRGV is absent from FanCalendar's roster. CFB Vibes includes its full
    # schedule alongside the other FCS programs.
    if membership.get("292") != ("FCS", "Southland"):
        raise ValueError("UTRGV conference changed; review its catalog entry")
    return teams


def calendar_entry(team):
    identifier = "ncaaf-" + team["teamId"]
    entry = dict(id=identifier, name=team["fullName"], sport="americanFootball",
        league=f"College {team['division']} · {team['conference']}",
        location=f"NCAA Division I {team['division']} · {team['city']}",
        monogram=team["key"][:4], color=(team.get("primaryColor") or "526EA4").lstrip("#"),
        fanCalendarTeamKey=team["key"], sourceURL="https://www.fancalendar.app/", provider="FanCalendar / ESPN",
        provenance="Independent provider",
        coverage="Upcoming college football games published by FanCalendar using ESPN schedules. "
                 "Kickoff times and postseason opponents can be announced later; the publisher controls updates.")
    return fcs_calendar(entry, team["city"]) if team["division"] == "FCS" else entry


def fcs_calendar(entry, school):
    # Published directory: https://cfbvibes.com/teams/?level=fcs
    # All 128 resulting feeds were checked with the app's User-Agent.
    slug = FCS_SLUGS.get(school)
    if slug is None:
        slug = re.sub(r"[^a-z0-9]+", "-", re.sub(r"[&.()']", "", school.lower())).strip("-")
    entry.pop("fanCalendarTeamKey", None)
    entry.update(feedURL=f"https://cfbvibes.com/teams/{slug}/schedule.ics",
                 sourceURL=f"https://cfbvibes.com/teams/{slug}/schedule/",
                 provider="CFB Vibes", provenance="Independent provider",
                 coverage="College football schedule published by CFB Vibes. Unannounced kickoff times appear as all-day events. "
                          "The publisher controls updates and season rollover.")
    return entry


def build(teams):
    previous = json.loads(CATALOG.read_text())
    college = [calendar_entry(team) for team in teams]
    college.append(fcs_calendar(dict(id="ncaaf-292", name="UT Rio Grande Valley Vaqueros", sport="americanFootball",
        league="College FCS · Southland", location="NCAA Division I FCS · Edinburg, Texas",
        monogram="RGV", color="D86531"), "UT Rio Grande Valley"))
    college.sort(key=lambda item: (item["league"], item["name"]))
    result = [item for item in previous if not item["id"].startswith("ncaaf-")] + college
    urls = [item["feedURL"] for item in result if item.get("feedURL")]
    if len({item["id"] for item in result}) != len(result) or len(set(urls)) != len(urls):
        raise ValueError("Duplicate college IDs or subscription URLs")
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--emit-json", action="store_true", help="Print the proposed catalog without creating subscriptions")
    args = parser.parse_args()
    try:
        teams = roster()
        if args.emit_json:
            print(json.dumps(build(teams), ensure_ascii=False, indent=2))
        else:
            print(json.dumps(dict(sorted(Counter(f"{t['division']} · {t['conference']}" for t in teams).items())), indent=2))
            print("Plus UTRGV (FCS Southland). All 128 FCS teams use CFB Vibes calendars.")
    except Exception as error:
        print(f"College catalog generation stopped: {error}", file=sys.stderr)
        sys.exit(1)
