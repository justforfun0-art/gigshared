import SwiftUI
import Shared

/// Settings sheet — a SwiftUI port of Android's EmployeeSettingsScreen, scoped
/// to the features iOS currently has: Preferences (Notifications, Language),
/// Support (Privacy Policy, Terms of Service, About), and Account (logout).
/// Privacy/Terms open the hosted pages in an in-app Safari view, matching
/// Android's openUrl("https://www.gighour.com/privacy" | "/terms").
struct SettingsView: View {

    /// Opens the notifications list (passed up so the parent owns the repo/sheet).
    let onNotifications: (() -> Void)?
    /// Optional repos enabling the Notification-Preferences + Payment-Methods rows.
    var notificationsRepo: (any NotificationRepository)? = nil
    var beneficiaries: (any BeneficiaryRepository)? = nil
    let onLogout: () -> Void

    @ObservedObject private var locale = LocaleManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var safariURL: URL?
    @State private var showAbout = false
    @State private var showNotifPrefs = false
    @State private var showPaymentMethods = false

    private static let privacyURL = URL(string: "https://www.gighour.com/privacy")!
    private static let termsURL = URL(string: "https://www.gighour.com/terms")!

    var body: some View {
        NavigationStack {
            Form {
                Section(L("settings_preferences")) {
                    if onNotifications != nil {
                        Button {
                            dismiss(); onNotifications?()
                        } label: { settingsLabel(L("profile_notifications"), "bell") }
                    }
                    Picker(selection: Binding(
                        get: { locale.language },
                        set: { locale.setLanguage($0) }
                    )) {
                        ForEach(LocaleManager.Language.allCases) { lang in
                            Text(lang.nativeName).tag(lang)
                        }
                    } label: {
                        settingsLabel(L("language"), "globe")
                    }
                    .tint(GHTheme.primary)
                    if notificationsRepo != nil {
                        Button { showNotifPrefs = true } label: {
                            settingsLabel(L("notif_prefs_title"), "bell.badge")
                        }
                    }
                    if beneficiaries != nil {
                        Button { showPaymentMethods = true } label: {
                            settingsLabel(L("payment_methods_title"), "creditcard")
                        }
                    }
                }

                Section(L("settings_support")) {
                    Button { safariURL = Self.privacyURL } label: {
                        settingsLabel(L("privacy_policy"), "lock.shield")
                    }
                    Button { safariURL = Self.termsURL } label: {
                        settingsLabel(L("terms_of_service"), "doc.text")
                    }
                    Button { showAbout = true } label: {
                        settingsLabel(L("about_gighour"), "info.circle")
                    }
                }

                Section(L("settings_account")) {
                    Button(role: .destructive) {
                        dismiss(); onLogout()
                    } label: {
                        settingsLabel(L("log_out"), "rectangle.portrait.and.arrow.right", tint: GHTheme.error)
                    }
                }
            }
            .navigationTitle(L("nav_settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("close")) { dismiss() }
                }
            }
            .sheet(isPresented: $showNotifPrefs) {
                if let notificationsRepo { NotificationPreferencesView(notifications: notificationsRepo) }
            }
            .sheet(isPresented: $showPaymentMethods) {
                if let beneficiaries { PaymentMethodsView(beneficiaries: beneficiaries) }
            }
            .sheet(item: $safariURL) { url in
                SafariSheet(url: url).ignoresSafeArea()
            }
            .alert(L("about_gighour"), isPresented: $showAbout) {
                Button(L("close"), role: .cancel) { }
            } message: {
                Text("GigHour v1.0.0\n\nGigHour connects workers with employers for short-term gig jobs.")
            }
        }
    }

    private func settingsLabel(_ title: String, _ icon: String, tint: Color = GHTheme.onBackground) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(tint == GHTheme.onBackground ? GHTheme.primary : tint)
            Text(title).foregroundStyle(tint)
        }
    }
}
// (URL: Identifiable for .sheet(item:) is already declared in PaymentsView.swift)
