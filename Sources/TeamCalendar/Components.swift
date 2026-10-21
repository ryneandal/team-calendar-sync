import CalendarCore
import SwiftUI

extension Color {
    init(hex: String) {
        let value = UInt32(hex, radix: 16) ?? 0x35877B
        self.init(
            .sRGB, red: Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255, blue: Double(value & 0xff) / 255, opacity: 1)
    }
}

struct TeamBadge: View {
    let feed: CalendarFeed
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(Color(hex: feed.color).gradient)
            if feed.sport == .motorsport || feed.sport == .custom {
                Image(systemName: feed.sport.symbol)
                    .font(.system(size: size * 0.42, weight: .semibold))
            } else {
                Text(feed.monogram).font(.system(size: size * 0.27, weight: .heavy, design: .rounded))
            }
        }
        .foregroundStyle(.white)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title).font(.title3.weight(.semibold))
            Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SmallHeading: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold)).tracking(1.1)
            .foregroundStyle(.secondary)
    }
}

struct EventRow: View {
    let event: CalendarEvent
    @Environment(\.calendar) private var calendar

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 2) {
                Text(event.start.formatted(.dateTime.month(.abbreviated)).uppercased())
                    .font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                Text(event.start.formatted(.dateTime.day()))
                    .font(.system(size: 22, weight: .medium, design: .rounded))
            }
            .frame(width: 43, height: 48)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 5) {
                Text(event.title).font(.system(size: 12, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                Text(scheduleDescription)
                    .font(.caption).foregroundStyle(.secondary)
                if let location = event.location, !location.isEmpty {
                    Text(location).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private var scheduleDescription: String {
        guard event.isAllDay else {
            return event.start.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        }
        // iCalendar's all-day DTEND is exclusive: a Monday-to-Monday golf
        // tournament occupies Monday through Sunday, not the following Monday.
        if let end = event.end,
            let lastDay = calendar.date(byAdding: .day, value: -1, to: end),
            lastDay > event.start
        {
            let style = Date.FormatStyle.dateTime.month(.abbreviated).day()
            return "\(event.start.formatted(style)) – \(lastDay.formatted(style)) · All day"
        }
        return "All day"
    }
}
