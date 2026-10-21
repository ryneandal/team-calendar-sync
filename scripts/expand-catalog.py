#!/usr/bin/env python3
"""Rebuild the expanded sports catalog from public directories; emit JSON to stdout.

This is an opt-in maintenance tool, never run by the app. Review the resulting
catalog and run verify-feeds.py before shipping. It preserves existing IDs and
metadata for unchanged URLs. Season-specific subscriptions require a new URL.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import html
import json
from pathlib import Path
import re
import sys
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "Sources/CalendarCore/Resources/catalog.json"
MLB_SEASON = 2027
NPB_SEASON = 2026

# Published directories, checked against the current league rosters in October 2026.
# The provider also lists some former Serie A participants and MLS all-star squads.
LEAGUES = [
    ("premier-league", "Premier League", "England", 20, ()),
    ("primera-division", "La Liga", "Spain", 20, ()),
    ("bundesliga", "Bundesliga", "Germany", 18, ()),
    ("serie-a", "Serie A", "Italy", 20, ("pisa", "cremonese", "hellas-verona-fc")),
    ("ligue-1", "Ligue 1", "France", 18, ()),
    ("superliga", "Primeira Liga", "Portugal", 18, ()),
    ("eredivisie", "Eredivisie", "Netherlands", 18, ()),
    ("scottish-premier-league", "Scottish Premiership", "Scotland", 12, ()),
    ("mls-major-league-soccer", "MLS", "United States & Canada", 30,
     ("mls-all-stars", "liga-mx-all-stars")),
    ("liga-mx", "Liga MX", "Mexico", 18, ()),
    ("serie-a-brazil", "Brasileirão Série A", "Brazil", 20, ()),
    ("primera-division-argentina", "Argentina Primera División", "Argentina", 30, ()),
    ("nfl", "NFL", "United States", 32, ()),
]

MLB_TEAMS = [
    ("arizona-diamondbacks", "Arizona Diamondbacks", "ARI"),
    ("athletics", "Athletics", "ATH"),
    ("atlanta-braves", "Atlanta Braves", "ATL"),
    ("baltimore-orioles", "Baltimore Orioles", "BAL"),
    ("boston-red-sox", "Boston Red Sox", "BOS"),
    ("chicago-cubs", "Chicago Cubs", "CHC"),
    ("chicago-white-sox", "Chicago White Sox", "CWS"),
    ("cincinnati-reds", "Cincinnati Reds", "CIN"),
    ("cleveland-guardians", "Cleveland Guardians", "CLE"),
    ("colorado-rockies", "Colorado Rockies", "COL"),
    ("detroit-tigers", "Detroit Tigers", "DET"),
    ("houston-astros", "Houston Astros", "HOU"),
    ("kansas-city-royals", "Kansas City Royals", "KC"),
    ("los-angeles-angels", "Los Angeles Angels", "LAA"),
    ("los-angeles-dodgers", "Los Angeles Dodgers", "LAD"),
    ("miami-marlins", "Miami Marlins", "MIA"),
    ("milwaukee-brewers", "Milwaukee Brewers", "MIL"),
    ("minnesota-twins", "Minnesota Twins", "MIN"),
    ("new-york-mets", "New York Mets", "NYM"),
    ("new-york-yankees", "New York Yankees", "NYY"),
    ("philadelphia-phillies", "Philadelphia Phillies", "PHI"),
    ("pittsburgh-pirates", "Pittsburgh Pirates", "PIT"),
    ("san-diego-padres", "San Diego Padres", "SD"),
    ("san-francisco-giants", "San Francisco Giants", "SF"),
    ("seattle-mariners", "Seattle Mariners", "SEA"),
    ("st-louis-cardinals", "St. Louis Cardinals", "STL"),
    ("tampa-bay-rays", "Tampa Bay Rays", "TB"),
    ("texas-rangers", "Texas Rangers", "TEX"),
    ("toronto-blue-jays", "Toronto Blue Jays", "TOR"),
    ("washington-nationals", "Washington Nationals", "WSH"),
]

# Codes come from the publisher's 2026 NPB subscription directory.
NPB_TEAMS = [
    ("G", "cl", "Yomiuri Giants", "Tokyo", "YG", "F07829"),
    ("S", "cl", "Tokyo Yakult Swallows", "Tokyo", "YS", "418657"),
    ("DB", "cl", "Yokohama DeNA BayStars", "Yokohama", "DB", "3277BB"),
    ("D", "cl", "Chunichi Dragons", "Nagoya", "CD", "386CB3"),
    ("T", "cl", "Hanshin Tigers", "Nishinomiya", "HT", "BA9A29"),
    ("C", "cl", "Hiroshima Toyo Carp", "Hiroshima", "HC", "CB3D48"),
    ("F", "pl", "Hokkaido Nippon-Ham Fighters", "Kitahiroshima", "HF", "448BBD"),
    ("E", "pl", "Tohoku Rakuten Golden Eagles", "Sendai", "RE", "A63F54"),
    ("L", "pl", "Saitama Seibu Lions", "Tokorozawa", "SL", "3C6295"),
    ("M", "pl", "Chiba Lotte Marines", "Chiba", "LM", "596574"),
    ("B", "pl", "Orix Buffaloes", "Osaka", "OB", "8C794C"),
    ("H", "pl", "Fukuoka SoftBank Hawks", "Fukuoka", "SH", "BC9D2E"),
]

KBO_TEAMS = [
    ("OB", "Doosan Bears", "Seoul", "DB", "425677"),
    ("HH", "Hanwha Eagles", "Daejeon", "HE", "D26C33"),
    ("HT", "KIA Tigers", "Gwangju", "KIA", "C54750"),
    ("WO", "Kiwoom Heroes", "Seoul", "KH", "9C4566"),
    ("KT", "KT Wiz", "Suwon", "KT", "61697A"),
    ("LG", "LG Twins", "Seoul", "LG", "B64067"),
    ("LT", "Lotte Giants", "Busan", "LG", "437F9E"),
    ("NC", "NC Dinos", "Changwon", "NC", "49729A"),
    ("SS", "Samsung Lions", "Daegu", "SL", "437BB9"),
    ("SK", "SSG Landers", "Incheon", "SSG", "BD4D54"),
]

GOLF = [
    ("pga-tour", "PGA Tour", "PGA", "r", "PGA Tour"),
    ("pga-tour-champions", "PGA Tour Champions", "CH", "s", "PGA Tour"),
    ("korn-ferry-tour", "Korn Ferry Tour", "KF", "h", "PGA Tour"),
    ("pga-tour-americas", "PGA Tour Americas", "AM", "y", "PGA Tour"),
    ("lpga-tour", "LPGA Tour", "LPGA", "1927/be00c88d/LPGA_Tour_Schedule.ics", "LPGA Tour"),
    ("dp-world-tour", "DP World Tour", "DP", "1925/84bd3230/DP_World_Tour_Schedule.ics", "DP World Tour"),
    ("liv-golf", "LIV Golf", "LIV", "1926/8682b6a1/LIV_Golf_Schedule.ics", "LIV Golf"),
]


def fetch(url):
    request = urllib.request.Request(url, headers={"User-Agent": "TeamCalendar/1.0 catalog maintenance"})
    with urllib.request.urlopen(request, timeout=30) as response:
        data = response.read(5 * 1024 * 1024 + 1)
        if len(data) > 5 * 1024 * 1024:
            raise ValueError(f"Directory too large: {url}")
        return data.decode("utf-8-sig")


def feed(identifier, name, sport, league, location, monogram, color, url, source, provider, coverage):
    return dict(id=identifier, name=name, sport=sport, league=league, location=location,
                monogram=monogram, color=color, feedURL=url, sourceURL=source,
                provider=provider, coverage=coverage, provenance="Community-maintained")


def league_feeds(configuration):
    slug, league, country, expected, excluded = configuration
    source = "https://fixtur.es/en/" + slug
    document = fetch(source)
    anchors = re.findall(
        r'''<a[^>]*href=["']([^"']+)["'][^>]*class=["']teamPick-tile["'][^>]*>(.*?)</a>''',
        document, re.S)
    teams = {}
    for url, body in anchors:
        team_slug = url.rsplit("/", 1)[-1]
        if team_slug in excluded:
            continue
        name = html.unescape(re.sub("<[^>]+>", "", body)).strip()
        if "/team/" not in url or not name:
            continue
        teams[team_slug] = (url, name)
    if len(teams) != expected:
        raise ValueError(f"{league}: expected {expected} teams, found {len(teams)}; review the roster")
    result = []
    for team_slug, (url, name) in sorted(teams.items(), key=lambda item: item[1][1].casefold()):
        monogram = "".join(word[0] for word in name.split() if word[0].isalnum())[:3].upper()
        item = feed(team_slug, name, "americanFootball" if slug == "nfl" else "football",
                    league, country, monogram, "468D84" if slug != "nfl" else "526EA4",
                    f"https://ics.fixtur.es/v2/{team_slug}.ics", url, "Fixtur.es",
                    "Published team fixtures, including other competitions when supplied by the provider.")
        item["provenance"] = "Independent provider"
        result.append(item)
    return result


def build():
    previous = json.loads(CATALOG.read_text())
    by_url = {item["feedURL"]: item for item in previous if item.get("feedURL")}
    with ThreadPoolExecutor(max_workers=4) as pool:
        expanded = [item for group in pool.map(league_feeds, LEAGUES) for item in group]

    for slug, name, monogram in MLB_TEAMS:
        expanded.append(feed(f"mlb-{slug}-{MLB_SEASON}", name, "baseball", "MLB",
            f"{MLB_SEASON} season · United States & Canada", monogram, "426A9A",
            f"https://raw.githubusercontent.com/vinnyab28/open-sports-cal/main/baseball/mlb/{MLB_SEASON}/{slug}.ics",
            f"https://github.com/vinnyab28/open-sports-cal/tree/main/baseball/mlb/{MLB_SEASON}",
            "Open Sports Cal / MLB Stats",
            f"{MLB_SEASON} regular-season games. Games without announced start times appear as all-day events. "
            f"This feed covers {MLB_SEASON} only; a later season needs a new subscription."))

    for code, division, name, city, monogram, color in NPB_TEAMS:
        slug = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")
        expanded.append(feed(f"npb-{slug}-{NPB_SEASON}", name, "baseball", "NPB",
            f"{NPB_SEASON} season · {city}, Japan", monogram, color,
            f"https://sub.freefielder.jp/cal/{division}/{code}{NPB_SEASON}.ics",
            f"https://freefielder.jp/blog/{NPB_SEASON}/02/{NPB_SEASON}-npb-schedule-ical.html", "freefielder.jp",
            f"{NPB_SEASON} Japanese baseball schedule with Japanese event titles. "
            f"This feed covers {NPB_SEASON} only; a later season needs a new subscription. "
            "No upcoming games may be listed after the team's season ends."))

    for code, name, city, monogram, color in KBO_TEAMS:
        slug = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")
        expanded.append(feed(f"kbo-{slug}", name, "baseball", "KBO",
            f"{city}, South Korea", monogram, color, f"https://kbo.elezy.com/schedule/{code}",
            "https://kbo.elezy.com", "Elezy KBO Calendar",
            "Published Korean baseball games for this team, with Korean event titles and results. "
            "The publisher controls season updates and postseason coverage."))

    for slug, name, monogram, path, league in GOLF:
        official = len(path) == 1
        if official:
            url = f"https://calendars.pgatourhq.com/tournamentbusiness/{path}_tb_calendar.ics"
            source = "https://calendars.pgatourhq.com/"
            provider = "PGA Tour"
            coverage = "Official tournament-week calendar. Date ranges can include practice and pro-am days; individual tee times are not included."
        else:
            url = "https://ics.calendarlabs.com/" + path
            source = "https://www.calendarlabs.com/ical-calendar/sports-golf/"
            provider = "CalendarLabs"
            coverage = "Published tournament dates, including majors when listed by the provider. Individual tee times are not included."
        item = feed("golf-" + slug, name, "golf", league, "Worldwide · tournament dates",
                    monogram, "488B68", url, source, provider, coverage)
        item["provenance"] = "Official tour calendar" if official else "Independent provider"
        expanded.append(item)

    # Preserve saved selections/subscription identities, city search, and existing badges.
    for item in expanded:
        if item["feedURL"] in by_url:
            old = by_url[item["feedURL"]]
            for field in ["id", "name", "location", "monogram", "color"]:
                item[field] = old[field]
    replaced_sports = {"football", "americanFootball", "baseball", "golf"}
    result = expanded + [item for item in previous
                         if item["sport"] not in replaced_sports or item["id"].startswith("ncaaf-")]
    # A source removed from the current league roster still remains usable by existing users.
    urls = {item["feedURL"] for item in result if item.get("feedURL")}
    for old in previous:
        if old["sport"] in {"football", "americanFootball"} and old.get("feedURL") and old["feedURL"] not in urls:
            result.append(old)
            urls.add(old["feedURL"])
    if len({item["id"] for item in result}) != len(result) or len(urls) != sum(bool(item.get("feedURL")) for item in result):
        raise ValueError("Duplicate catalog ID or subscription URL")
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--emit-json", action="store_true", help="Print the complete proposed catalog")
    args = parser.parse_args()
    try:
        result = build()
        if args.emit_json:
            print(json.dumps(result, ensure_ascii=False, indent=2))
        else:
            from collections import Counter
            print(json.dumps(dict(Counter(item["league"] for item in result)), indent=2, ensure_ascii=False))
            print(f"Total: {len(result)} calendars. Use --emit-json to inspect the proposed catalog.")
    except Exception as error:
        print(f"Catalog generation stopped: {error}", file=sys.stderr)
        sys.exit(1)
