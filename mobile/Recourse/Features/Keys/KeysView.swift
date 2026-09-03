import SwiftUI

/// The three keys behind the account, in the layout Fuse taught people to read:
/// two Active Keys that sign every spend, and the Recovery Keys that can only help
/// get back in.
struct KeysView: View {
    let environment: AppEnvironment

    @State private var explainer: KeyExplainer?
    @State private var showsRestore = false
    @State private var showsUpgrade = false

    private var store: SmartAccountStore { environment.smartAccounts }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header
                statusLead
                activeKeys
                recoveryKeys
                escapeHatch
            }
            .padding(20)
        }
        .background(RecourseColor.night)
        .navigationTitle("Keys")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $explainer) { KeyExplainerSheet(explainer: $0) }
        .sheet(isPresented: $showsRestore) {
            NavigationStack { RestoreDeviceView(environment: environment) }
        }
        .sheet(isPresented: $showsUpgrade) {
            NavigationStack { UpgradeAccountView(environment: environment) }
        }
        .task { await store.refresh() }
    }

    // MARK: Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Two keys to spend.\nOne more to get back in.")
                .font(.recourse(24, .bold))
                .foregroundStyle(RecourseColor.nightText)
                .fixedSize(horizontal: false, vertical: true)
            Text("Every send is signed by the key in this phone and the key in your iCloud. Neither works alone, and Recourse never holds either.")
                .font(.recourse(13))
                .foregroundStyle(RecourseColor.nightMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var statusLead: some View {
        switch store.phase {
        case .needsRestore:
            lead(
                icon: "iphone.and.arrow.forward",
                title: "This phone is not your Device Key yet",
                detail: "Your account lives on another phone. Move it here with a code we email you.",
                action: "Restore this phone"
            ) { showsRestore = true }
        case .none:
            lead(
                icon: "sparkles",
                title: "Move to a three-key account",
                detail: "Your money is behind one key today. Set up the account that needs two.",
                action: "Set up"
            ) { showsUpgrade = true }
        case .failed(let message):
            lead(icon: "exclamationmark.triangle.fill", title: "Setup did not finish", detail: message, action: "Try again") {
                showsUpgrade = true
            }
        case .provisioning(let message):
            HStack(spacing: 12) {
                ProgressView().tint(RecourseColor.nightText)
                Text(message)
                    .font(.recourse(13, .semibold))
                    .foregroundStyle(RecourseColor.nightText)
            }
            .padding(14)
        case .live, .unknown:
            EmptyView()
        }
    }

    private var activeKeys: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Active keys", detail: "Both sign every payment")
            HStack(spacing: 12) {
                KeyCard(
                    icon: "faceid",
                    tint: RecourseColor.nightText,
                    title: "Device",
                    detail: deviceDetail,
                    live: store.phase == .live
                ) { explainer = .device }
                KeyCard(
                    icon: "icloud.fill",
                    tint: Color(red: 0.16, green: 0.50, blue: 0.98),
                    title: "Cloud",
                    detail: "iCloud Keychain",
                    live: store.record != nil
                ) { explainer = .cloud }
            }
        }
    }

    private var deviceDetail: String {
        switch store.phase {
        case .live: return "This iPhone, Face ID"
        case .needsRestore: return "Another phone"
        default: return "Not set up yet"
        }
    }

    private var recoveryKeys: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Recovery keys", detail: "Can restore access, never spend")
            Button { explainer = .recovery } label: {
                HStack(spacing: 12) {
                    Image(systemName: "envelope.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(RecourseColor.ledger)
                        .frame(width: 38, height: 38)
                        .background(RecourseColor.nightChip, in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Email")
                            .font(.recourse(14, .semibold))
                            .foregroundStyle(RecourseColor.nightText)
                        Text(environment.accountSession.account?.email ?? "The email on your account")
                            .font(.recourse(12))
                            .foregroundStyle(RecourseColor.nightMuted)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(store.record == nil ? "Pending" : "Active")
                        .font(.recourse(11, .bold))
                        .foregroundStyle(store.record == nil ? RecourseColor.nightMuted : RecourseColor.ledger)
                }
                .padding(14)
                .background(RecourseColor.nightChip, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var escapeHatch: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("If you lose this phone", detail: nil)
            Text("Sign in on a new iPhone. Your Cloud Key arrives with iCloud, or from your recovery PIN. A code to your email swaps the Device Key over. Nothing to write down.")
                .font(.recourse(12))
                .foregroundStyle(RecourseColor.nightMuted)
                .fixedSize(horizontal: false, vertical: true)
            NavigationLink {
                WalletRecoveryView(environment: environment)
            } label: {
                HStack {
                    Label("Recovery PIN for the Cloud Key", systemImage: "lock.rotation")
                        .font(.recourse(13, .semibold))
                        .foregroundStyle(RecourseColor.nightText)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(RecourseColor.nightMuted)
                }
                .padding(14)
                .background(RecourseColor.nightChip, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func sectionTitle(_ title: String, detail: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.recourse(15, .bold))
                .foregroundStyle(RecourseColor.nightText)
            Spacer()
            if let detail {
                Text(detail)
                    .font(.recourse(11))
                    .foregroundStyle(RecourseColor.nightMuted)
            }
        }
    }

    private func lead(icon: String, title: String, detail: String, action: String, perform: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(RecourseColor.ledger)
                    .frame(width: 38, height: 38)
                    .background(RecourseColor.nightChip, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.recourse(13, .semibold))
                        .foregroundStyle(RecourseColor.nightText)
                    Text(detail)
                        .font(.recourse(11))
                        .foregroundStyle(RecourseColor.nightMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Button(action: perform) {
                Text(action)
                    .font(.recourse(14, .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(RecourseColor.ledger, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(RecourseColor.nightChip, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// One active key, as a card.
private struct KeyCard: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String
    let live: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(tint)
                    Spacer()
                    Circle()
                        .fill(live ? RecourseColor.ledger : RecourseColor.nightMuted.opacity(0.5))
                        .frame(width: 8, height: 8)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.recourse(15, .bold))
                        .foregroundStyle(RecourseColor.nightText)
                    Text(detail)
                        .font(.recourse(11))
                        .foregroundStyle(RecourseColor.nightMuted)
                        .lineLimit(2)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
            .background(RecourseColor.nightChip, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Explainers

enum KeyExplainer: String, Identifiable {
    case device, cloud, recovery

    var id: String { rawValue }

    var title: String {
        switch self {
        case .device: return "What's a Device Key?"
        case .cloud: return "What's a Cloud Key?"
        case .recovery: return "What's a Recovery Key?"
        }
    }

    var icon: String {
        switch self {
        case .device: return "faceid"
        case .cloud: return "icloud.fill"
        case .recovery: return "envelope.fill"
        }
    }

    var tint: Color {
        switch self {
        case .device: return RecourseColor.nightText
        case .cloud: return Color(red: 0.16, green: 0.50, blue: 0.98)
        case .recovery: return RecourseColor.ledger
        }
    }

    var points: [(icon: String, heading: String, body: String)] {
        switch self {
        case .device:
            return [
                ("key.fill", "Active key", "Signs every payment, together with your Cloud Key."),
                ("lock.shield.fill", "Made by this iPhone", "Created inside the Secure Enclave and unlocked by Face ID. It cannot be copied off the phone."),
                ("arrow.triangle.2.circlepath", "If you lose it", "Your Cloud Key and your Recovery Key move the account to a new phone."),
            ]
        case .cloud:
            return [
                ("key.fill", "Active key", "Signs every payment, together with your Device Key."),
                ("icloud.fill", "Follows your Apple ID", "Kept in iCloud Keychain, so it is on every iPhone you sign into. A recovery PIN backs it up for any other device."),
                ("arrow.triangle.2.circlepath", "If you lose it", "Restore it from your recovery PIN on any phone."),
            ]
        case .recovery:
            return [
                ("envelope.fill", "Your email", "A code sent to your email lets Recourse add its signature to one thing: moving your Device Key to a new phone."),
                ("hand.raised.fill", "Recovery only", "It can never send money, alone or with another Recovery Key. It needs one of your active keys."),
                ("building.columns.fill", "Held by Recourse, sealed", "We keep it encrypted and it is one of three. On its own it does nothing."),
            ]
        }
    }
}

struct KeyExplainerSheet: View {
    let explainer: KeyExplainer
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(RecourseColor.nightMuted)
                        .frame(width: 32, height: 32)
                        .background(RecourseColor.nightChip, in: Circle())
                }
                .buttonStyle(.plain)
            }
            VStack(spacing: 14) {
                Image(systemName: explainer.icon)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(explainer == .device ? RecourseColor.night : .white)
                    .frame(width: 64, height: 64)
                    .background(explainer.tint, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                Text(explainer.title)
                    .font(.recourse(20, .bold))
                    .foregroundStyle(RecourseColor.nightText)
            }
            .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 18) {
                ForEach(explainer.points, id: \.heading) { point in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: point.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(RecourseColor.nightText)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(point.heading)
                                .font(.recourse(14, .semibold))
                                .foregroundStyle(RecourseColor.nightText)
                            Text(point.body)
                                .font(.recourse(12))
                                .foregroundStyle(RecourseColor.nightMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            Button { dismiss() } label: {
                Text("Got it")
                    .font(.recourse(15, .semibold))
                    .foregroundStyle(RecourseColor.nightText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(RecourseColor.nightChip, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(22)
        .background(RecourseColor.night)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }
}
