import SwiftUI
import WidgetKit

@main
struct RecourseWidgetsBundle: WidgetBundle {
    var body: some Widget {
        WalletWidget()
    }
}

/// What is waiting for you, on the home screen.
///
/// It used to show the escrowed total and a protection deadline, for a feature the app
/// no longer has. Cheques replace it because they are the one thing worth interrupting
/// someone about: money another person has already promised, sitting there until it is
/// taken, with a date after which it stops being cashable.
struct WalletWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RecourseWallet", provider: WalletProvider()) { entry in
            WalletWidgetView(entry: entry)
        }
        .configurationDisplayName("Waiting for you")
        .description("Cheques you can cash, and your USDC balance.")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}

struct WalletEntry: TimelineEntry {
    let date: Date
    let snapshot: WalletSnapshot?
}

struct WalletProvider: TimelineProvider {
    // The widget gallery preview should look lived-in, not empty.
    private var sample: WalletSnapshot {
        WalletSnapshot(
            balanceBaseUnits: 248_500_000,
            cashableBaseUnits: 32_000_000,
            cashableCount: 2,
            nearestExpiry: Date().addingTimeInterval(4 * 86_400),
            updatedAt: Date()
        )
    }

    func placeholder(in context: Context) -> WalletEntry {
        WalletEntry(date: Date(), snapshot: sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (WalletEntry) -> Void) {
        let snapshot = context.isPreview ? sample : WalletSnapshot.load()
        completion(WalletEntry(date: Date(), snapshot: snapshot ?? sample))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WalletEntry>) -> Void) {
        // The app pushes a reload on every refresh; the 30-minute horizon only covers
        // the days-left arithmetic drifting while the app stays closed.
        let entry = WalletEntry(date: Date(), snapshot: WalletSnapshot.load())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(1800))))
    }
}

struct WalletWidgetView: View {
    let entry: WalletEntry

    @Environment(\.widgetFamily) private var family

    private let ledger = Color(red: 5 / 255, green: 99 / 255, blue: 74 / 255)

    private var snapshot: WalletSnapshot? { entry.snapshot }
    private var hasWaiting: Bool { (snapshot?.cashableCount ?? 0) > 0 }

    /// How long the soonest cheque has left. Nil once it is under a day, where a count
    /// of days would round to something misleading.
    private var daysLeft: String? {
        guard let expiry = snapshot?.nearestExpiry else { return nil }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: expiry).day ?? 0
        guard days >= 1 else { return nil }
        return days == 1 ? "1 day left" : "\(days) days left"
    }

    var body: some View {
        switch family {
        case .accessoryRectangular:
            accessory
        default:
            small
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 10, weight: .bold))
                Text("Recourse")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(ledger)

            Spacer(minLength: 0)

            if let snapshot, hasWaiting {
                Text(snapshot.cashableText)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(snapshot.cashableCount == 1 ? "waiting to cash" : "waiting · \(snapshot.cashableCount) cheques")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let daysLeft {
                    Text(daysLeft)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(ledger)
                }
            } else if let snapshot {
                Text(snapshot.balanceText)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("your balance")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                Text("No cheques waiting")
                    .font(.system(size: 13, weight: .semibold))
                Text("Open Recourse to get started")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var accessory: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Recourse")
                .font(.system(size: 12, weight: .semibold))
            if let snapshot, hasWaiting {
                Text("\(snapshot.cashableText) to cash")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(daysLeft ?? "\(snapshot.cashableCount) cheques")
                    .font(.system(size: 11, weight: .medium))
            } else if let snapshot {
                Text(snapshot.balanceText)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("balance")
                    .font(.system(size: 11, weight: .medium))
            } else {
                Text("No cheques waiting")
                    .font(.system(size: 12, weight: .medium))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
