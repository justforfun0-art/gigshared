import SwiftUI

/// Lets any tab-root screen show the hamburger (open side-menu) button in its
/// nav bar without threading state through every initializer. RootView publishes
/// an "open drawer" action into the environment; screens add `.drawerToolbar()`
/// inside their own NavigationStack so the button attaches to their nav bar.
private struct OpenDrawerKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    var openDrawer: (() -> Void)? {
        get { self[OpenDrawerKey.self] }
        set { self[OpenDrawerKey.self] = newValue }
    }
}

private struct DrawerToolbarModifier: ViewModifier {
    @Environment(\.openDrawer) private var openDrawer

    func body(content: Content) -> some View {
        content.toolbar {
            if let openDrawer {
                ToolbarItem(placement: .topBarLeading) {
                    Button { openDrawer() } label: {
                        Image(systemName: "line.3.horizontal")
                    }
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
