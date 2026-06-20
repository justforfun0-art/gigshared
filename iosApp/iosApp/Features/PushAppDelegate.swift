import UIKit

/// Minimal UIApplicationDelegate to receive APNs callbacks (a SwiftUI `App` has
/// none by default). Wired via `@UIApplicationDelegateAdaptor` in GigHourApp.
/// All push logic lives in `PushManager`; this just forwards the token.
final class PushAppDelegate: NSObject, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // PushManager.configure(...) is called from the App init once the
        // container exists; nothing else needed here at launch.
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in PushManager.shared.didRegisterAPNs(deviceToken: deviceToken) }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Non-fatal — push just won't be delivered to this device this session.
        print("APNs registration failed: \(error.localizedDescription)")
    }
}
