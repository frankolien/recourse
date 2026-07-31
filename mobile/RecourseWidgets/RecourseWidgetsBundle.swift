import SwiftUI
import WidgetKit

@main
struct RecourseWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ProtectionWidget()
    }
}

struct ProtectionWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RecourseProtection", provider: ProtectionProvider()) { entry in
            ProtectionWidgetView(entry: entry)
        }
        .configurationDisplayName("Protected now")
        .description("Your escrowed total and the next protection deadline.")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}

struct ProtectionEntry: TimelineEntry {
    let date: Date
    let snapshot: ProtectionSnapshot?
}

struct ProtectionProvider: TimelineProvider {
    // The widget gallery preview should look lived-in, not empty.
    private var sample: ProtectionSnapshot {
        ProtectionSnapshot(
            protectedBaseUnits: 103_440_000,
            activeCount: 3,
            nearestDeadline: Date().addingTimeInterval(4 * 86_400),
            updatedAt: Date()
        )
    }

    func placeholder(in context: Context) -> ProtectionEntry {
        ProtectionEntry(date: Date(), snapshot: sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (ProtectionEntry) -> Void) {
        let snapshot = context.isPreview ? sample : ProtectionSnapshot.load()
        completion(ProtectionEntry(date: Date(), snapshot: snapshot ?? sample))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ProtectionEntry>) -> Void) {
        // The app pushes a reload on every refresh; the 30-minute horizon only
        // covers the days-left arithmetic drifting while the app stays closed.
        let entry = ProtectionEntry(date: Date(), snapshot: ProtectionSnapshot.load())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(1800))))
    }
}

struct ProtectionWidgetView: View {
    let entry: ProtectionEntry

    @Environment(\.widgetFamily) private var family

    private let ledger = Color(red: 5 / 255, green: 99 / 255, blue: 74 / 255)

    var body: some View {
        Group {
            switch family {
            case .accessoryRectangular:
                lockScreenBody
            default:
                homeScreenBody
            }
        }
        .containerBackground(for: .widget) {
            Color(.systemBackground)
        }
    }

    private var homeScreenBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text("Recourse")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(ledger)

            Spacer()

            if let snapshot = entry.snapshot, snapshot.activeCount > 0 {
                Text(snapshot.protectedText)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("protected · \(snapshot.activeCount) active")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                if let daysLeft {
                    Text(daysLeft)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ledger)
                }
            } else {
                Text("Nothing protected")
                    .font(.system(size: 15, weight: .semibold))
                Text("Scan a checkout to start")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var lockScreenBody: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text("Recourse")
                    .font(.system(size: 12, weight: .semibold))
            }
            if let snapshot = entry.snapshot, snapshot.activeCount > 0 {
                Text("\(snapshot.protectedText) protected")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Text(daysLeft ?? "\(snapshot.activeCount) active")
                    .font(.system(size: 11, weight: .medium))
            } else {
                Text("Nothing protected")
                    .font(.system(size: 13, weight: .semibold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var daysLeft: String? {
        guard let deadline = entry.snapshot?.nearestDeadline else { return nil }
        let days = max(0, Calendar.current.dateComponents([.day], from: entry.date, to: deadline).day ?? 0)
        return days == 0 ? "ends today" : "ends in \(days)d"
    }
}
