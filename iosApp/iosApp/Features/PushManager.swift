import Foundation
import UIKit
import UserNotifications
import Shared

#if canImport(FirebaseCore)
import FirebaseCore
#endif
#if canImport(FirebaseMessaging)
import FirebaseMessaging
#endif

/// Coordinates push registration for iOS, mirroring Android's FCM flow.
///
/// Activation is gated on the Firebase SDK being present in the build:
/// - With `FirebaseMessaging` linked, it configures Firebase, captures the FCM
///   registration token, and upserts it to `user_fcm_tokens` (platform = "ios")
///   so the existing server send-path delivers to the device unchanged.
/// - Without the SDK, it still requests notification permission and registers
///   for remote notifications (so the build works), but has no FCM token to
///   upload — push is inert until the SDK + GoogleService-Info.plist are added.
///
/// The token is cached and (re)uploaded once a user id is known, so a token that
/// arrives before login is still persisted after sign-in (Android parity).
@MainActor
final class PushManager: NSObject {
    static let shared = PushManager()

    private var pushTokens: (any PushTokenRepository)?
    private var userId: String?
    private var pendingFcmToken: String?

    private override init() { super.init() }

    /// Called once at launch from the AppDelegate.
    func configure(pushTokens: any PushTokenRepository) {
        self.pushTokens = pushTokens
        #if canImport(FirebaseCore)
        if FirebaseApp.app() == nil { FirebaseApp.configure() }
        #endif
        #if canImport(FirebaseMessaging)
        Messaging.messaging().delegate = self
        #endif
        UNUserNotificationCenter.current().delegate = self
    }

    /// Ask for notification permission, then register for remote notifications.
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
        }
    }

    /// Bind the signed-in user so any cached/just-arrived token gets uploaded.
    func setUserId(_ id: String?) {
        userId = id
        if id != nil, let token = pendingFcmToken { upload(token: token) }
    }

    // MARK: - APNs token → FCM

    /// Forward the raw APNs token to Firebase (it derives the FCM token from it).
    func didRegisterAPNs(deviceToken: Data) {
        #if canImport(FirebaseMessaging)
        Messaging.messaging().apnsToken = deviceToken
        #endif
    }

    /// Persist + (if we have a user) upload the FCM registration token.
    func handleFcmToken(_ token: String?) {
        guard let token, !token.isEmpty else { return }
        pendingFcmToken = token
        if userId != nil { upload(token: token) }
    }

    private func upload(token: String) {
        guard let pushTokens, let userId else { return }
        Task {
            // Best-effort; a failure just means the next launch/refresh retries.
            try? await IosHelpersKt.registerTokenOrThrow(pushTokens, userId: userId, token: token)
        }
    }
}

// MARK: - Foreground presentation + tap routing

extension PushManager: UNUserNotificationCenterDelegate {
    /// Show banners while the app is foregrounded (Android shows an in-app banner
    /// for the same high-signal statuses).
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }

    /// Tap routing — publish the payload so the app can deep-link (matches the
    /// Android tap → section behaviour). Consumers observe `.pushNotificationTapped`.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        NotificationCenter.default.post(name: .pushNotificationTapped, object: nil, userInfo: info)
        completionHandler()
    }
}

#if canImport(FirebaseMessaging)
extension PushManager: MessagingDelegate {
    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        Task { @MainActor in self.handleFcmToken(fcmToken) }
    }
}
#endif

extension Notification.Name {
    /// Posted (with the push userInfo) when the user taps a push notification.
    static let pushNotificationTapped = Notification.Name("pushNotificationTapped")
}
