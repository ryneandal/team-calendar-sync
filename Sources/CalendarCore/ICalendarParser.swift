import Foundation

public struct CalendarEvent: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let start: Date
    public let end: Date?
    public let location: String?
    public let isAllDay: Bool
    public let isRecurring: Bool
}

public struct FeedPreview: Sendable {
    public let title: String?
    public let events: [CalendarEvent]
    public let containsRecurrence: Bool
    public let hasUnexpandedRecurrence: Bool
    public let skippedEvents: Int
    public let fetchedAt: Date

    public func upcoming(after date: Date = .now, limit: Int = 5) -> [CalendarEvent] {
        Array(events.filter { ($0.end ?? $0.start) >= date }.prefix(limit))
    }
}

/// A deliberately bounded preview reader. Subscriptions pass the original URL to the
/// destination, so its full iCalendar engine handles recurrence, alarms, and updates.
public enum ICalendarParser {
    private struct Property {
        let name: String
        let parameters: [String: String]
        let value: String
    }

    private struct Occurrence: Hashable {
        let uid: String
        let start: Date
    }

    private struct EventDuration {
        let days: Int
        let seconds: Int

        func end(from start: Date, calendar: Calendar) -> Date? {
            // Nominal days retain local wall time across DST; hours/minutes/seconds
            // are exact elapsed time, applied after the calendar-day component.
            calendar.date(byAdding: .day, value: days, to: start)?
                .addingTimeInterval(TimeInterval(seconds))
        }
    }

    private struct Series {
        let uid: String
        let event: CalendarEvent
        let timeZone: TimeZone
        let rule: String?
        let until: Date?
        let excluded: Set<Date>
        let additional: [Date]
        let unsupported: Bool
        let duration: EventDuration?
    }

    public static func parse(_ data: Data, now: Date = .now, localTimeZone: TimeZone = .current) throws -> FeedPreview {
        guard data.count <= FeedClient.maximumBytes else { throw FeedError.tooLarge }
        guard let text = String(data: data, encoding: .utf8) else { throw FeedError.invalidEncoding }
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var lines: [String] = []
        for line in normalized.components(separatedBy: "\n") {
            if line.hasPrefix(" ") || line.hasPrefix("\t"), !lines.isEmpty {
                lines[lines.count - 1] += line.dropFirst()
            } else {
                lines.append(line.trimmingCharacters(in: CharacterSet(charactersIn: "\u{feff}")))
            }
        }
        guard lines.first(where: { !$0.isEmpty })?.uppercased() == "BEGIN:VCALENDAR",
            lines.last(where: { !$0.isEmpty })?.uppercased() == "END:VCALENDAR"
        else {
            throw FeedError.invalidCalendar
        }

        var title: String?
        var defaultZone = localTimeZone
        var fields: [String: Property]?
        var nestedDepth = 0
        var events: [String: CalendarEvent] = [:]
        var skipped = 0
        var containsRecurrence = false
        var hasUnexpandedRecurrence = false
        var series: [Series] = []
        var overrides: Set<Occurrence> = []
        var rangedSeries = Set<String>()
        var dateProperties: [Property] = []
        for line in lines {
            guard let property = property(line) else { continue }
            if property.name == "BEGIN", property.value.uppercased() == "VEVENT" {
                guard fields == nil else { throw FeedError.invalidCalendar }
                fields = [:]
                nestedDepth = 0
                dateProperties = []
            } else if property.name == "END", property.value.uppercased() == "VEVENT" {
                guard let values = fields, nestedDepth == 0 else { throw FeedError.invalidCalendar }
                fields = nil
                if values["RRULE"] != nil || values["RDATE"] != nil { containsRecurrence = true }
                if let uid = values["UID"]?.value, let recurrenceID = values["RECURRENCE-ID"] {
                    if let originalStart = date(recurrenceID, defaultZone: defaultZone, localTimeZone: localTimeZone) {
                        overrides.insert(Occurrence(uid: uid, start: originalStart))
                    }
                    if recurrenceID.parameters["RANGE"] != nil {
                        // A range changes later instances too. Keep explicit events,
                        // but do not invent unchanged dates for the rest of the series.
                        rangedSeries.insert(uid)
                        containsRecurrence = true
                        hasUnexpandedRecurrence = true
                    }
                }
                if values["STATUS"]?.value.uppercased() == "CANCELLED" { continue }
                guard let startProperty = values["DTSTART"],
                    let start = date(startProperty, defaultZone: defaultZone, localTimeZone: localTimeZone)
                else {
                    skipped += 1
                    continue
                }
                let allDay = startProperty.parameters["VALUE"] == "DATE" || startProperty.value.count == 8
                let zone =
                    allDay
                    ? localTimeZone
                    : startProperty.value.hasSuffix("Z")
                        ? TimeZone(secondsFromGMT: 0)!
                        : startProperty.parameters["TZID"].flatMap(timeZone) ?? defaultZone
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = zone
                var end = values["DTEND"].flatMap { date($0, defaultZone: defaultZone, localTimeZone: localTimeZone) }
                var eventDuration: EventDuration?
                if let property = values["DURATION"] {
                    guard values["DTEND"] == nil,
                        let parsed = duration(property.value, isAllDay: allDay),
                        let durationEnd = parsed.end(from: start, calendar: calendar)
                    else {
                        skipped += 1
                        continue
                    }
                    eventDuration = parsed
                    end = durationEnd
                }
                if end == nil, allDay {
                    end = calendar.date(byAdding: .day, value: 1, to: start)
                }
                let uid = values["UID"]?.value ?? "\(start.timeIntervalSince1970)-\(values["SUMMARY"]?.value ?? "")"
                let identifier = uid + "|" + (values["RECURRENCE-ID"]?.value ?? "")
                let event = CalendarEvent(
                    id: identifier,
                    title: unescape(values["SUMMARY"]?.value ?? "Untitled event"),
                    start: start, end: end,
                    location: values["LOCATION"].map { unescape($0.value) },
                    isAllDay: allDay,
                    isRecurring: values["RRULE"] != nil || values["RDATE"] != nil
                )
                events[identifier] = event
                if event.isRecurring, values["RECURRENCE-ID"] == nil {
                    let rule = values["RRULE"]?.value
                    let untilValue = rule?.split(separator: ";").first { $0.uppercased().hasPrefix("UNTIL=") }?
                        .split(separator: "=", maxSplits: 1).last.map(String.init)
                    let until = untilValue.flatMap {
                        date(
                            Property(name: "UNTIL", parameters: startProperty.parameters, value: $0),
                            defaultZone: zone, localTimeZone: localTimeZone)
                    }
                    var excluded: Set<Date> = []
                    var additional: [Date] = []
                    var unsupported = values["EXRULE"] != nil
                    for property in dateProperties {
                        for value in property.value.split(separator: ",") {
                            if let parsed = date(
                                Property(name: property.name, parameters: property.parameters, value: String(value)),
                                defaultZone: zone, localTimeZone: localTimeZone)
                            {
                                if property.name == "EXDATE" {
                                    excluded.insert(parsed)
                                } else {
                                    additional.append(parsed)
                                }
                            } else {
                                unsupported = true
                            }
                        }
                    }
                    series.append(
                        Series(
                            uid: uid, event: event, timeZone: zone, rule: rule, until: until,
                            excluded: excluded, additional: additional, unsupported: unsupported,
                            duration: eventDuration))
                }
            } else if fields != nil {
                if property.name == "BEGIN" {
                    nestedDepth += 1
                } else if property.name == "END" {
                    nestedDepth = max(0, nestedDepth - 1)
                } else if nestedDepth == 0 {
                    fields?[property.name] = property
                    if property.name == "EXDATE" || property.name == "RDATE" { dateProperties.append(property) }
                }
            } else if property.name == "X-WR-CALNAME" {
                title = unescape(property.value)
            } else if property.name == "X-WR-TIMEZONE", let zone = timeZone(property.value) {
                defaultZone = zone
            }
        }
        guard fields == nil else { throw FeedError.invalidCalendar }
        var remainingCandidateDays = RecurrenceExpander.maximumCandidateDays
        for item in series {
            guard events.count < 20_000 else {
                hasUnexpandedRecurrence = true
                break
            }
            if item.excluded.contains(item.event.start)
                || overrides.contains(Occurrence(uid: item.uid, start: item.event.start))
            {
                events.removeValue(forKey: item.event.id)
            }
            guard !item.unsupported, !rangedSeries.contains(item.uid) else {
                hasUnexpandedRecurrence = true
                continue
            }
            let generated: [Date]?
            if let rule = item.rule {
                let eventLength = max(0, (item.event.end ?? item.event.start).timeIntervalSince(item.event.start))
                generated = RecurrenceExpander.dates(
                    rule: rule, start: item.event.start,
                    timeZone: item.timeZone, now: now, until: item.until,
                    eventLength: eventLength,
                    remainingCandidateDays: &remainingCandidateDays)
            } else {
                generated = []
            }
            guard let generated else {
                hasUnexpandedRecurrence = true
                continue
            }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = item.timeZone
            for start in Set(generated + item.additional) where start != item.event.start {
                guard events.count < 20_000 else {
                    hasUnexpandedRecurrence = true
                    break
                }
                guard !item.excluded.contains(start), !overrides.contains(Occurrence(uid: item.uid, start: start))
                else { continue }
                let end = item.event.end.flatMap { originalEnd -> Date? in
                    if let duration = item.duration { return duration.end(from: start, calendar: calendar) }
                    if item.event.isAllDay {
                        let days = calendar.dateComponents([.day], from: item.event.start, to: originalEnd).day ?? 1
                        return calendar.date(byAdding: .day, value: days, to: start)
                    }
                    return start.addingTimeInterval(originalEnd.timeIntervalSince(item.event.start))
                }
                let id = item.uid + "|occurrence-\(start.timeIntervalSince1970)"
                events[id] = CalendarEvent(
                    id: id, title: item.event.title, start: start, end: end,
                    location: item.event.location, isAllDay: item.event.isAllDay, isRecurring: true)
            }
        }
        return FeedPreview(
            title: title, events: events.values.sorted { $0.start < $1.start },
            containsRecurrence: containsRecurrence, hasUnexpandedRecurrence: hasUnexpandedRecurrence,
            skippedEvents: skipped, fetchedAt: now)
    }

    private static func duration(_ input: String, isAllDay: Bool) -> EventDuration? {
        let value = input.uppercased()
        let pattern = #"^\+?P(?:([0-9]+)W|(?:([0-9]+)D)?(?:T(?:([0-9]+)H)?(?:([0-9]+)M)?(?:([0-9]+)S)?)?)$"#
        guard !value.hasSuffix("T"), !isAllDay || !value.contains("T"),
            let expression = try? NSRegularExpression(pattern: pattern),
            let match = expression.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
            match.range.length == value.utf16.count
        else { return nil }
        // Extremely large durations cannot be usefully expanded by this bounded
        // preview. Reject them explicitly, and avoid overflowing integer arithmetic.
        let maximumSeconds = RecurrenceExpander.maximumCandidateDays * 86_400
        var components: [Int] = []
        for index in 1..<match.numberOfRanges {
            guard let range = Range(match.range(at: index), in: value) else {
                components.append(0)
                continue
            }
            guard let number = Int(value[range]), number <= maximumSeconds else { return nil }
            components.append(number)
        }
        let days = components[0] * 7 + components[1]
        let seconds = components[2] * 3_600 + components[3] * 60 + components[4]
        let total = days * 86_400 + seconds
        guard total > 0, total <= maximumSeconds else { return nil }
        return EventDuration(days: days, seconds: seconds)
    }

    private static func property(_ line: String) -> Property? {
        var quoted = false
        var separator: String.Index?
        for index in line.indices {
            if line[index] == "\"" { quoted.toggle() }
            if line[index] == ":", !quoted {
                separator = index
                break
            }
        }
        guard let separator else { return nil }
        let components = line[..<separator].split(separator: ";")
        guard let name = components.first else { return nil }
        var parameters: [String: String] = [:]
        for component in components.dropFirst() {
            let pair = component.split(separator: "=", maxSplits: 1)
            if pair.count == 2 {
                parameters[pair[0].uppercased()] = String(pair[1]).trimmingCharacters(
                    in: CharacterSet(charactersIn: "\""))
            }
        }
        return Property(
            name: name.uppercased(), parameters: parameters,
            value: String(line[line.index(after: separator)...]))
    }

    private static func date(_ property: Property, defaultZone: TimeZone, localTimeZone: TimeZone) -> Date? {
        let value = property.value
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.isLenient = false
        if value.count == 8 {
            // DATE values are calendar days, not instants in the feed's time zone.
            // Keep the displayed date stable for subscribers west or east of UTC.
            formatter.timeZone = localTimeZone
            formatter.dateFormat = "yyyyMMdd"
        } else if value.hasSuffix("Z") {
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        } else {
            if let identifier = property.parameters["TZID"] {
                guard let zone = timeZone(identifier) else { return nil }
                formatter.timeZone = zone
            } else {
                formatter.timeZone = defaultZone
            }
            formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        }
        return formatter.date(from: value)
    }

    private static func timeZone(_ identifier: String) -> TimeZone? {
        // Twitch publishes IANA zone names with a leading slash.
        TimeZone(identifier: identifier) ?? TimeZone(identifier: String(identifier.drop(while: { $0 == "/" })))
    }

    private static func unescape(_ value: String) -> String {
        var result = ""
        var escaped = false
        for character in value {
            if escaped {
                result.append(character == "n" || character == "N" ? "\n" : character)
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else {
                result.append(character)
            }
        }
        if escaped { result.append("\\") }
        return result
    }
}
