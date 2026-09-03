import SwiftUI

/// Takes an account that predates the Safe from one key to three, and moves its
/// balance across. New accounts never see this; onboarding does the same work
/// inline.
struct UpgradeAccountView: View {
    let environment: AppEnvironment

    private enum Stage: Equatable {
        case explain
        case working(String)
        case done(moved: USDCAmount?)
    }

    @State private var stage: Stage = .explain
    @State private var problem: String?
    @Environment(\.dismiss) private var dismiss

    private var store: SmartAccountStore { environment.smartAccounts }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                switch stage {
                case .explain:
                    header("Three keys, one tap", "Your money moves to an account that needs two keys to spend. Sending stays one tap, because both keys are on this phone.")
                    steps
                    action("Set up my account") { await upgrade() }
                case .working(let message):
                    header("Setting up", message)
                    ProgressView().tint(RecourseColor.nightText).frame(maxWidth: .infinity).padding(.top, 30)
                case .done(let moved):
                    header("Your account is ready", moved.map { "\(currency($0)) moved to it." } ?? "Deposits now land in it.")
                    if let address = store.record?.safe {
                        Text(address)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(RecourseColor.nightMuted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    action("Done") { dismiss() }
                }
                if let problem {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .font(.recourse(12, .medium))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)
        }
        .background(RecourseColor.night)
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 14) {
            step("faceid", "A Device Key is made in this iPhone", "Inside the Secure Enclave. It never leaves.")
            step("icloud.fill", "Your current key becomes the Cloud Key", "Same key, same iCloud sync, same PIN backup.")
            step("envelope.fill", "A Recovery Key is sealed for your email", "It can only ever help you onto a new phone.")
            step("arrow.right.circle.fill", "Your balance moves across", "One transfer, paid by the old key. Uncashed cheques stay behind until they clear.")
        }
        .padding(14)
        .background(RecourseColor.nightChip, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func upgrade() async {
        problem = nil
        stage = .working("Creating your account on Arc")
        do {
            _ = try await store.provision()
            stage = .working("Moving your balance")
            let gateway = try environment.makeCloudKeyGateway()
            let committed = environment.chequeBook.committed
            var moved: USDCAmount?
            if let amount = try await store.cloudBalanceToSweep(reader: gateway, committed: committed) {
                _ = try await store.sweepCloudBalance(amount, gateway: gateway)
                moved = amount
            }
            await environment.paymentStore.refreshBuyer()
            stage = .done(moved: moved)
        } catch {
            problem = (error as? SmartAccountAPIError)?.message ?? "Setup did not finish. Try again."
            stage = .explain
        }
    }

    private func currency(_ amount: USDCAmount) -> String {
        "$" + amount.decimalString
    }

    private func header(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.recourse(24, .bold))
                .foregroundStyle(RecourseColor.nightText)
            Text(detail)
                .font(.recourse(13))
                .foregroundStyle(RecourseColor.nightMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func step(_ icon: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(RecourseColor.ledger)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.recourse(14, .semibold))
                    .foregroundStyle(RecourseColor.nightText)
                Text(body)
                    .font(.recourse(12))
                    .foregroundStyle(RecourseColor.nightMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func action(_ title: String, _ work: @escaping () async -> Void) -> some View {
        Button {
            Task { await work() }
        } label: {
            Text(title)
                .font(.recourse(15, .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(RecourseColor.ledger, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
