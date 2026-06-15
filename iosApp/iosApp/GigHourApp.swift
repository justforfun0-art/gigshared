import SwiftUI
import Shared

@main
struct GigHourApp: App {

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
        self.container = container
    }

    var body: some Scene {
        WindowGroup {
            RootView(container: container)
        }
    }

    private static func plist(_ key: String) -> String {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String) ?? ""
    }
}
