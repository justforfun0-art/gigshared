import SwiftUI
import Shared

@main
struct GigHourApp: App {

    @UIApplicationDelegateAdaptor(PushAppDelegate.self) private var appDelegate
    private let container: AppContainer

    init() {
        // Load secrets from Info.plist (populated from a non-committed xcconfig).
        // apiBaseUrl MUST end in "/api/".
        let config = BackendConfig(
            supabaseUrl: Self.plist("SUPABASE_URL"),
            supabaseAnonKey: Self.plist("SUPABASE_ANON_KEY"),
            apiBaseUrl: Self.plist("API_BASE_URL")
        )
        let container = AppContainer(config: config)
        container.startServerTimeSync()
        container.backfillSecureTokensFromSession()
        self.container = container

        // Push: configure Firebase (if linked) + ask permission. Inert without
        // the Firebase SDK — see PushManager.
        PushManager.shared.configure(pushTokens: container.pushTokens)
        PushManager.shared.requestAuthorization()
    }

    var body: some Scene {
        WindowGroup {
            RootContainerView(container: container)
        }
    }

    private static func plist(_ key: String) -> String {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String) ?? ""
    }
}

/// Shows the animated splash for a short beat on cold launch, then cross-fades
/// to the app. Mirrors Android, where AnimatedSplashScreen is shown over the
/// content until startup work settles.
private struct RootContainerView: View {
    let container: AppContainer
    @State private var showSplash = true

    var body: some View {
        ZStack {
            RootView(container: container)

            if showSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .task {
            // ~1.8s hero beat, then fade out (matches the Android dwell).
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            withAnimation(.easeOut(duration: 0.4)) { showSplash = false }
        }
    }
}
