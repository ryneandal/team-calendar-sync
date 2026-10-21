# Calendar sources

| Collection | Coverage | Source |
| --- | --- | --- |
| Soccer | 242 clubs across 12 top divisions; complete league rosters listed below | [Fixtur.es](https://fixtur.es/en) |
| NFL | All 32 teams | [Fixtur.es NFL](https://fixtur.es/en/nfl) |
| College football · FBS | All 138 programs, grouped by conference | [FanCalendar](https://www.fancalendar.app/) / ESPN |
| College football · FCS | All 128 programs, grouped by conference | [CFB Vibes](https://cfbvibes.com/teams/?level=fcs) |
| Basketball | 8 NBA teams | [Fixtur.es NBA](https://fixtur.es/en/nba) |
| MLB | All 30 teams; **2027 regular season** | [Open Sports Cal](https://github.com/vinnyab28/open-sports-cal/tree/main/baseball/mlb/2027), from MLB Stats |
| NPB | All 12 teams; **2026 season**, Japanese event titles | [freefielder.jp](https://freefielder.jp/blog/2026/02/2026-npb-schedule-ical.html) |
| KBO | All 10 teams; Korean event titles and results | [Elezy KBO Calendar](https://kbo.elezy.com), using its `/schedule/{team-code}` feeds |
| Golf | PGA Tour, PGA Tour Champions, Korn Ferry Tour, PGA Tour Americas | [Official PGA Tour calendars](https://calendars.pgatourhq.com/) |
| More golf | LPGA Tour, DP World Tour, LIV Golf | [CalendarLabs](https://www.calendarlabs.com/ical-calendar/sports-golf/) |
| Motorsport | Formula 1, MotoGP | [Fixtur.es](https://fixtur.es/en/formula-1) |
| Tennis | ATP Masters / WTA 1000 and Grand Slam tournament dates, not individual matches | [Fixtur.es Tennis](https://fixtur.es/en/tennis) |
| Esports games | LoL, VALORANT, CS2, Dota 2, Rocket League, Overwatch 2; available tournament tiers | [Esports Calendar](https://www.esport-calendar.com/) |
| Esports teams | T1, G2, Karmine Corp (LoL); Vitality, NAVI (CS2) | [Esport ICS](https://github.com/snutij/esport_ics) / PandaScore |
| Critical Role | Channel-published broadcasts and recurring slots | [Critical Role on Twitch](https://www.twitch.tv/criticalrole/schedule), via [Twitch’s public iCalendar API](https://dev.twitch.tv/docs/api/reference#get-channel-icalendar) |
| Dimension 20 & Dropout | Dimension 20, Adventuring Party, **and other Dropout shows** | [Unofficial Dropout Calendar](https://www.reddit.com/r/dropout/comments/1x5kylp/the_unofficial_dropout_calendar/) |
| UFC | Fight Nights, numbered events, announced cards | [UFC Calendar](https://github.com/clarencechaan/ufc-cal) |
| Space launches | Published launch manifest | [Next Spaceflight](https://nextspaceflight.com/calendar/) |

Soccer includes Premier League (20), La Liga (20), Bundesliga (18), Serie A (20), Ligue 1 (18), Primeira Liga (18), Eredivisie (18), Scottish Premiership (12), MLS (30), Liga MX (18), Brasileirão Série A (20), and Argentina Primera División (30). Rosters were checked in October 2026. Team feeds can also contain cup and international competitions.

College football covers NCAA Division I (FBS and FCS), including independent programs, across 25 conference groups. Division II, Division III, and NAIA are not included. FBS subscription links from FanCalendar are requested when a team is previewed or approved, then saved locally for reuse. The request contains only the public team key and football category, with reminders disabled; it does not create an account or add anything to a personal calendar. The app coalesces duplicate requests and observes the provider's rate-limit cooldown. FCS teams use direct CFB Vibes subscription URLs, including UTRGV's full schedule. Unannounced kickoff times may appear as all-day events; publishers control updates and season rollover.

**MLB and NPB URLs are season-specific.** MLB uses the already-published 2027 regular-season schedules; unannounced game times appear as all-day events. NPB uses 2026 schedules and may show no upcoming games once a team's season ends. These sources do not automatically roll into another season: a new season needs a new subscription. The year and limitation appear in each team's details and approval sheet. KBO's stable URLs follow the publisher's schedule updates.

Golf feeds cover tournament dates, not individual tee times. PGA Tour's official calendars cover full tournament weeks and can include practice/pro-am days. Multi-day previews show the inclusive date range while preserving iCalendar's exclusive end date.

Dimension 20 uses a **community calendar for the whole Dropout service**, not an official or show-only feed. This scope is displayed before approval. Critical Role’s recurring slots depend on the channel keeping its schedule current. Esports feeds may have no matches between tournaments. Launch windows and fight cards can change at short notice.

Sources are attributed and community feeds are labeled. Feeds may include provider messages. Team Calendar is not affiliated with any provider, team, league, or show.
