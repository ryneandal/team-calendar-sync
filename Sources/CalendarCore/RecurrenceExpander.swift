import Foundation

/// Expands the daily/weekly rules used by broadcast calendars for a 180-day preview.
/// Unsupported rule parts return nil; the destination calendar receives the full feed.
enum RecurrenceExpander {
    /// Shared by all series in one feed, including series that cannot finish expanding.
    static let maximumCandidateDays = 20_000

    static func dates(
        rule: String, start: Date, timeZone: TimeZone, now: Date, until: Date?,
        eventLength: TimeInterval, remainingCandidateDays: inout Int
    ) -> [Date]? {
        var parts: [String: String] = [:]
        for component in rule.uppercased().split(separator: ";") {
            let pair = component.split(separator: "=", maxSplits: 1)
            guard pair.count == 2, parts[String(pair[0])] == nil else { return nil }
            parts[String(pair[0])] = String(pair[1])
        }
        let supported: Set<String> = ["FREQ", "INTERVAL", "COUNT", "UNTIL", "BYDAY", "WKST"]
        guard Set(parts.keys).isSubset(of: supported),
            let frequency = parts["FREQ"], ["DAILY", "WEEKLY"].contains(frequency),
            let interval = Int(parts["INTERVAL"] ?? "1"), interval > 0, interval <= 1_000
        else { return nil }
        let count = parts["COUNT"].flatMap(Int.init)
        if parts["COUNT"] != nil && (count == nil || count! < 1) { return nil }
        if parts["UNTIL"] != nil && until == nil { return nil }
        if count != nil && until != nil { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let weekdays = ["SU": 1, "MO": 2, "TU": 3, "WE": 4, "TH": 5, "FR": 6, "SA": 7]
        guard let weekStart = weekdays[parts["WKST"] ?? "MO"] else { return nil }
        let startWeekday = calendar.component(.weekday, from: start)
        var selectedDays: Set<Int> = []
        if let byDay = parts["BYDAY"] {
            for day in byDay.split(separator: ",") {
                guard let weekday = weekdays[String(day)] else { return nil }
                selectedDays.insert(weekday)
            }
            guard !selectedDays.isEmpty else { return nil }
        } else if frequency == "WEEKLY" {
            selectedDays = [startWeekday]
        }

        let anchor = calendar.startOfDay(for: start)
        // Include instances that began earlier but still overlap the preview.
        // The margin also covers nominal durations whose elapsed length changes at DST.
        let windowStart = calendar.date(byAdding: .day, value: -2, to: now.addingTimeInterval(-eventLength))!
        let windowEnd = calendar.date(byAdding: .day, value: 180, to: now)!
        let time = calendar.dateComponents([.hour, .minute, .second], from: start)
        var cursor = anchor
        // COUNT needs the complete series count; unlimited rules can jump near today.
        if count == nil, windowStart > start { cursor = calendar.startOfDay(for: windowStart) }
        var seen = 1  // DTSTART is the first occurrence, including when it is excluded.
        var result: [Date] = []
        while true {
            if cursor > windowEnd || (until != nil && cursor > until!) || (count != nil && seen >= count!) {
                return result
            }
            guard remainingCandidateDays > 0 else { return nil }
            remainingCandidateDays -= 1
            let days = calendar.dateComponents([.day], from: anchor, to: cursor).day ?? 0
            let weekday = calendar.component(.weekday, from: cursor)
            let week = (days + (startWeekday - weekStart + 7) % 7) / 7
            let matchesInterval = frequency == "DAILY" ? days % interval == 0 : week % interval == 0
            if matchesInterval, selectedDays.isEmpty || selectedDays.contains(weekday),
                let occurrence = calendar.date(
                    bySettingHour: time.hour ?? 0, minute: time.minute ?? 0,
                    second: time.second ?? 0, of: cursor,
                    matchingPolicy: .strict, repeatedTimePolicy: .first, direction: .forward),
                calendar.isDate(occurrence, inSameDayAs: cursor), occurrence > start
            {
                if let until, occurrence > until { return result }
                seen += 1
                if occurrence >= windowStart && occurrence <= windowEnd { result.append(occurrence) }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { return nil }
            cursor = next
        }
    }
}
