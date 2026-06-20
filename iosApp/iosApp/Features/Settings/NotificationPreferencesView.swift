import SwiftUI
import Shared

/// Notification Preferences — channel + category toggles, upserted to the server
/// via the shared NotificationRepository (Android NotificationPreferencesScreen).
/// iOS has no local DataStore mirror, so toggles start at the model defaults and
/// each change is saved immediately (the server returns the canonical set).
struct NotificationPreferencesView: View {
    let notifications: any NotificationRepository
    @StateObject private var viewModel: NotificationPreferencesViewModel
    @Environment(\.dismiss) private var dismiss

    init(notifications: any NotificationRepository) {
        self.notifications = notifications
        _viewModel = StateObject(wrappedValue: NotificationPreferencesViewModel(notifications: notifications))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L("notif_prefs_channels")) {
                    toggle(L("notif_prefs_push"), \.pushEnabled)
                    toggle(L("notif_prefs_inapp"), \.inAppEnabled)
                    toggle(L("notif_prefs_whatsapp"), \.whatsappEnabled)
                    toggle(L("notif_prefs_email"), \.emailEnabled)
                }
                Section(L("notif_prefs_categories")) {
                    toggle(L("notif_prefs_job_alerts"), \.jobAlertsEnabled)
                    toggle(L("notif_prefs_application_updates"), \.applicationUpdatesEnabled)
                    toggle(L("notif_prefs_payment_updates"), \.paymentUpdatesEnabled)
                    toggle(L("notif_prefs_messages"), \.messagesEnabled)
                    toggle(L("notif_prefs_marketing"), \.marketingEnabled)
                }
                if let err = viewModel.error {
                    Section { Text(err).font(.caption).foregroundStyle(GHTheme.error) }
                }
            }
            .navigationTitle(L("notif_prefs_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.isSaving { ProgressView() } else { Button(L("close")) { dismiss() } }
                }
            }
        }
    }

    /// A toggle bound to a Bool keypath on the prefs struct; saving on change.
    private func toggle(_ label: String, _ key: WritableKeyPath<PrefsState, Bool>) -> some View {
        Toggle(label, isOn: Binding(
            get: { viewModel.prefs[keyPath: key] },
            set: { newValue in
                var p = viewModel.prefs; p[keyPath: key] = newValue
                Task { await viewModel.save(p) }
            }
        ))
        .tint(GHTheme.primary)
        .disabled(viewModel.isSaving)
    }
}

/// Plain-Swift mirror of the shared NotificationPreferences (so SwiftUI can use
/// WritableKeyPaths — the Kotlin data class is immutable from Swift).
struct PrefsState {
    var pushEnabled = true
    var inAppEnabled = true
    var whatsappEnabled = true
    var emailEnabled = false
    var jobAlertsEnabled = true
    var applicationUpdatesEnabled = true
    var paymentUpdatesEnabled = true
    var messagesEnabled = true
    var marketingEnabled = false
}

@MainActor
final class NotificationPreferencesViewModel: ObservableObject {
    @Published var prefs = PrefsState()
    @Published var isSaving = false
    @Published var error: String?

    private let notifications: any NotificationRepository
    init(notifications: any NotificationRepository) { self.notifications = notifications }

    /// Upsert the full desired set; reflect the server's canonical response.
    func save(_ next: PrefsState) async {
        prefs = next   // optimistic
        isSaving = true; error = nil
        defer { isSaving = false }
        let model = NotificationPreferences(
            pushEnabled: next.pushEnabled, inAppEnabled: next.inAppEnabled,
            whatsappEnabled: next.whatsappEnabled, emailEnabled: next.emailEnabled,
            jobAlertsEnabled: next.jobAlertsEnabled, applicationUpdatesEnabled: next.applicationUpdatesEnabled,
            paymentUpdatesEnabled: next.paymentUpdatesEnabled, messagesEnabled: next.messagesEnabled,
            marketingEnabled: next.marketingEnabled
        )
        do {
            let saved = try await IosHelpersKt.saveNotificationPreferencesOrThrow(notifications, prefs: model)
            prefs = PrefsState(
                pushEnabled: saved.pushEnabled, inAppEnabled: saved.inAppEnabled,
                whatsappEnabled: saved.whatsappEnabled, emailEnabled: saved.emailEnabled,
                jobAlertsEnabled: saved.jobAlertsEnabled, applicationUpdatesEnabled: saved.applicationUpdatesEnabled,
                paymentUpdatesEnabled: saved.paymentUpdatesEnabled, messagesEnabled: saved.messagesEnabled,
                marketingEnabled: saved.marketingEnabled
            )
        } catch {
            self.error = (error as NSError).localizedDescription
        }
    }
}
