import SwiftUI
import UIKit
import UserNotifications

/// Real notification state, not a wall of dead toggles: the permission row reflects the
/// system setting, and anything listed below is an actual pending request on this
/// device.
///
/// There is nothing to schedule yet. Dispute deadline reminders went with the protected
/// checkout, and the honest thing is to say so rather than keep a toggle that controls
/// nothing. Cheque expiry reminders are the natural replacement.
struct NotificationsSettingsView: View {
    let paymentStore: BuyerPaymentStore
    let push: PushCoordinator

    @State private var authorizationStatus: UNAuthorizationStatus?
    @State private var pendingReminders: [PendingReminder] = []
    @Environment(\.openURL) private var openURL

    struct PendingReminder: Identifiable {
        let id: String
        let body: String
        let fireDate: Date?
    }

    var body: some View {
        List {
            permissionSection
            registrationSection

            if pendingReminders.isEmpty {
                Section {
                    Text("Nothing scheduled")
                        .font(.recourse(13, .medium))
                        .foregroundStyle(RecourseColor.nightMuted)
                } footer: {
                    Text("Reminders are scheduled on this iPhone. From its server, Recourse sends two kinds of alert: money arriving in your account, with the amount and who sent it, and team alerts, a proposal waiting for you or a change you can veto. Neither carries your balance.")
                }
            } else {
                Section("Scheduled") {
                    ForEach(pendingReminders) { reminder in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(reminder.body)
                                .font(.recourse(13, .medium))
                                .foregroundStyle(RecourseColor.nightText)
                            if let fireDate = reminder.fireDate {
                                Text(fireDate.formatted(date: .abbreviated, time: .shortened))
                                    .font(.recourse(11))
                                    .foregroundStyle(RecourseColor.nightMuted)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(RecourseColor.night)
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await paymentStore.refreshBuyer()
            await refreshState()
        }
    }

    @ViewBuilder
    private var permissionSection: some View {
        Section {
            switch authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                Label {
                    Text("Notifications allowed")
                        .font(.recourse(14, .medium))
                        .foregroundStyle(RecourseColor.nightText)
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(RecourseColor.ledger)
                }
            case .denied:
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Notifications are off in iOS Settings")
                                .font(.recourse(14, .medium))
                                .foregroundStyle(RecourseColor.nightText)
                            Text("Open Settings to allow them")
                                .font(.recourse(11))
                                .foregroundStyle(RecourseColor.nightMuted)
                        }
                    } icon: {
                        Image(systemName: "bell.slash.fill")
                            .foregroundStyle(RecourseColor.nightMuted)
                    }
                }
                .buttonStyle(.plain)
            default:
                Button {
                    // Permission alone is not enough; the phone also has to fetch a
                    // token and hand it to the server, which enableAlerts does.
                    Task {
                        await push.enableAlerts()
                        await refreshState()
                    }
                } label: {
                    Label("Allow notifications", systemImage: "bell.badge.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(RecourseColor.ledger)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // Whether the server knows this phone. Without this row a missing alert is a
    // mystery; with it the answer is on screen.
    @ViewBuilder
    private var registrationSection: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(registrationTitle)
                        .font(.recourse(14, .medium))
                        .foregroundStyle(RecourseColor.nightText)
                    if let detail = registrationDetail {
                        Text(detail)
                            .font(.recourse(11))
                            .foregroundStyle(RecourseColor.nightMuted)
                    }
                }
            } icon: {
                Image(systemName: push.registration == .registered ? "iphone.badge.checkmark" : "iphone.slash")
                    .foregroundStyle(push.registration == .registered ? RecourseColor.ledger : RecourseColor.nightMuted)
            }
            Button {
                Task {
                    await push.reregister()
                    await refreshState()
                }
            } label: {
                Label("Register this iPhone again", systemImage: "arrow.clockwise")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(RecourseColor.ledger)
            }
            .buttonStyle(.plain)
        } header: {
            Text("Alerts from Recourse")
        } footer: {
            Text("Builds from Xcode reach Apple's test gateway and TestFlight builds the live one. This build uses the \(PushCoordinator.environment) gateway.")
        }
    }

    private var registrationTitle: String {
        switch push.registration {
        case .registered: "This iPhone is registered"
        case .waitingForToken: "Waiting for Apple to issue a token"
        case .failed: "Registration failed"
        case .none: "Not registered yet"
        }
    }

    private var registrationDetail: String? {
        switch push.registration {
        case .registered: "The server can alert this phone."
        case .waitingForToken: "iOS usually answers within a second on a real device."
        case .failed(let reason): reason
        case .none: "Allow notifications above, or register again."
        }
    }

    private func refreshState() async {
        let center = UNUserNotificationCenter.current()
        authorizationStatus = await center.notificationSettings().authorizationStatus
        let now = Date()
        pendingReminders = await center.pendingNotificationRequests()
            .map { request in
                let interval = (request.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval
                return PendingReminder(
                    id: request.identifier,
                    body: request.content.body,
                    fireDate: interval.map { now.addingTimeInterval($0) }
                )
            }
            .sorted { ($0.fireDate ?? .distantFuture) < ($1.fireDate ?? .distantFuture) }
    }
}

/// Named wallet addresses for the send flow, managed here and picked from the
/// send screen. Device-local, like the wallet key they pair with.
struct AddressBookView: View {
    let store: AddressBookStore
    @State private var showsEditor = false

    var body: some View {
        List {
            if store.recipients.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No saved addresses", systemImage: "person.crop.rectangle.stack")
                    } description: {
                        Text("Save the wallet addresses you send USDC to, and pick them by name instead of pasting 0x strings.")
                    } actions: {
                        Button("Add address") { showsEditor = true }
                            .font(.recourse(14, .bold))
                            .foregroundStyle(RecourseColor.ledger)
                    }
                    .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(store.recipients) { recipient in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(recipient.label)
                                .font(.recourse(14, .bold))
                                .foregroundStyle(RecourseColor.nightText)
                            Text(recipient.address)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(RecourseColor.nightMuted)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .padding(.vertical, 2)
                    }
                    .onDelete { offsets in
                        for offset in offsets {
                            store.remove(store.recipients[offset])
                        }
                    }
                } footer: {
                    Text("Saved on this iPhone only. Swipe to delete.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(RecourseColor.night)
        .navigationTitle("Address book")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showsEditor = true
                } label: {
                    Image(systemName: "plus")
                }
                .tint(RecourseColor.ledger)
            }
        }
        .sheet(isPresented: $showsEditor) {
            RecipientEditorView(store: store)
        }
    }
}

/// Add-a-recipient form, shared by the address book screen and the send flow's
/// "save this address" affordance.
struct RecipientEditorView: View {
    let store: AddressBookStore
    var prefilledAddress = ""

    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var address = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $label)
                    TextField("Wallet address (0x…)", text: $address)
                        .font(.system(size: 13, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("The address is validated before saving.")
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(RecourseColor.ledger)
                    }
                }
            }
            .navigationTitle("Save address")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(label.trimmingCharacters(in: .whitespaces).isEmpty || address.isEmpty)
                }
            }
            .onAppear {
                if address.isEmpty { address = prefilledAddress }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        do {
            try store.add(label: label, address: address)
            dismiss()
        } catch AddressBookStore.AddError.invalidAddress {
            errorMessage = "That is not a valid wallet address."
        } catch AddressBookStore.AddError.duplicateAddress {
            errorMessage = "That address is already saved."
        } catch {
            errorMessage = "Give this address a name."
        }
    }
}
