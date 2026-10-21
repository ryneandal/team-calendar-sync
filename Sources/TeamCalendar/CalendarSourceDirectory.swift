import Foundation

/// Provider links shared by Settings and the Help menu.
enum CalendarSourceDirectory {
    struct Source: Identifiable, Sendable {
        let name: String
        let scope: String
        let url: URL
        var id: String { name }
    }

    static let sources: [Source] = [
        Source(
            name: "Fixtur.es", scope: "Soccer, NFL, NBA, motorsport, and tennis",
            url: URL(string: "https://fixtur.es/en")!),
        Source(
            name: "FanCalendar / ESPN", scope: "College football · FBS",
            url: URL(string: "https://www.fancalendar.app/")!),
        Source(
            name: "CFB Vibes", scope: "College football · FCS",
            url: URL(string: "https://cfbvibes.com/teams/?level=fcs")!),
        Source(
            name: "Open Sports Cal / MLB Stats", scope: "MLB · 2027 regular season",
            url: URL(string: "https://github.com/vinnyab28/open-sports-cal/tree/main/baseball/mlb/2027")!),
        Source(
            name: "freefielder.jp", scope: "NPB · 2026 season, Japanese event titles",
            url: URL(string: "https://freefielder.jp/blog/2026/02/2026-npb-schedule-ical.html")!),
        Source(
            name: "Elezy KBO Calendar", scope: "KBO · Korean event titles and results",
            url: URL(string: "https://kbo.elezy.com")!),
        Source(
            name: "PGA Tour", scope: "Official PGA Tour, Champions, Korn Ferry, and Americas calendars",
            url: URL(string: "https://calendars.pgatourhq.com/")!),
        Source(
            name: "CalendarLabs", scope: "LPGA, DP World Tour, and LIV Golf",
            url: URL(string: "https://www.calendarlabs.com/ical-calendar/sports-golf/")!),
        Source(
            name: "Esports Calendar", scope: "Esports games and tournaments",
            url: URL(string: "https://www.esport-calendar.com/")!),
        Source(
            name: "Esport ICS", scope: "Esports team schedules",
            url: URL(string: "https://esport-ics.pages.dev")!),
        Source(
            name: "Critical Role on Twitch", scope: "Channel-published broadcasts and recurring slots",
            url: URL(string: "https://www.twitch.tv/criticalrole/schedule")!),
        Source(
            name: "Unofficial Dropout Calendar", scope: "Community feed for Dimension 20 and other Dropout shows",
            url: URL(string: "https://www.reddit.com/r/dropout/comments/1x5kylp/the_unofficial_dropout_calendar/")!),
        Source(
            name: "UFC Calendar", scope: "Fight Nights, numbered events, and announced cards",
            url: URL(string: "https://clarencechaan.github.io/ufc-cal/")!),
        Source(
            name: "Next Spaceflight", scope: "Published space launch manifest",
            url: URL(string: "https://nextspaceflight.com/calendar/")!),
    ]
}
