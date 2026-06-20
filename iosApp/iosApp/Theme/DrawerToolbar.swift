import SwiftUI

/// Lets any tab-root screen show the hamburger (open side-menu) button in its
/// nav bar without threading state through every initializer. RootView publishes
/// an "open drawer" action into the environment; screens add `.drawerToolbar()`
/// inside their own NavigationStack so the button attaches to their nav bar.
private struct OpenDrawerKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}
private struct TopBarMessagesKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}
private struct TopBarNotificationsKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    var openDrawer: (() -> Void)? {
        get { self[OpenDrawerKey.self] }
        set { self[OpenDrawerKey.self] = newValue }
    }
    /// Opens the messages screen from the global top-bar action.
    var topBarMessages: (() -> Void)? {
        get { self[TopBarMessagesKey.self] }
        set { self[TopBarMessagesKey.self] = newValue }
    }
    /// Opens the notifications screen from the global top-bar action.
    var topBarNotifications: (() -> Void)? {
        get { self[TopBarNotificationsKey.self] }
        set { self[TopBarNotificationsKey.self] = newValue }
    }
}

private struct DrawerToolbarModifier: ViewModifier {
    @Environment(\.openDrawer) private var openDrawer
    @Environment(\.topBarMessages) private var onMessages
    @Environment(\.topBarNotifications) private var onNotifications
    @ObservedObject private var locale = LocaleManager.shared

    func body(content: Content) -> some View {
        content.toolbar {
            if let openDrawer {
                ToolbarItem(placement: .topBarLeading) {
                    Button { openDrawer() } label: {
                        Image(systemName: "line.3.horizontal")
                    }
                }
            }
            // Trailing global actions (Android GigHourTopAppBar): language,
            // messages, notifications. SwiftUI lays a trailing group out
            // right-to-left, so the Android order reads correctly as listed.
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    ForEach(LocaleManager.Language.allCases) { lang in
                        Button { locale.setLanguage(lang) } label: {
                            if lang == locale.language {
                                Label(lang.nativeName, systemImage: "checkmark")
                            } else {
                                Text("\(lang.nativeName) · \(lang.englishName)")
                            }
                        }
                    }
                } label: {
                    Image(systemName: "globe")
                }
                if let onMessages {
                    Button { onMessages() } label: { Image(systemName: "bubble.left.and.bubble.right") }
                }
                if let onNotifications {
                    Button { onNotifications() } label: { Image(systemName: "bell") }
                }
            }
        }
    }
}

extension View {
    /// Adds the side-menu hamburger to this screen's nav bar (no-op if no
    /// open-drawer action is provided by an ancestor).
    func drawerToolbar() -> some View { modifier(DrawerToolbarModifier()) }
}
