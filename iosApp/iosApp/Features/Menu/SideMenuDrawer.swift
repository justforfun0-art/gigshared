import SwiftUI
import Shared

/// One row in the side drawer.
struct DrawerItem: Identifiable {
    let id = UUID()
    let label: String
    let icon: String
    let action: DrawerAction
}

/// What a drawer row does — either select a tab or run a one-off action.
enum DrawerAction {
    case tab(Int)
    case messages
    case assistant
    case help
    case logout
}

/// Android-style navigation drawer (port of NavigationDrawer.kt): a left panel
/// with a role-gradient header (avatar initials + name + role) and a scrollable
/// menu, opened by the hamburger in the nav bar. Slides in over a scrim.
struct SideMenuDrawer: View {
    let isEmployer: Bool
    let userName: String?
    let selectedTab: Int
    let onSelectTab: (Int) -> Void
    let onMessages: () -> Void
    let onAssistant: () -> Void
    let onHelp: () -> Void
    let onLogout: () -> Void
    let onClose: () -> Void

    private var accent: Color { isEmployer ? GHTheme.tertiary : GHTheme.primary }
    private var headerGradient: LinearGradient {
        isEmployer
            ? LinearGradient(colors: [GHTheme.hex(0x10B981), GHTheme.hex(0x059669)], startPoint: .topLeading, endPoint: .bottomTrailing)
            : GHTheme.heroGradient
    }

    private var items: [DrawerItem] {
        if isEmployer {
            return [
                DrawerItem(label: L("nav_dashboard"), icon: "house", action: .tab(0)),
                DrawerItem(label: L("nav_my_jobs"), icon: "briefcase", action: .tab(1)),
                DrawerItem(label: L("nav_employer_applications"), icon: "person.2", action: .tab(2)),
                DrawerItem(label: L("nav_payments"), icon: "creditcard", action: .tab(3)),
                DrawerItem(label: L("nav_messages"), icon: "bubble.left.and.bubble.right", action: .messages),
                DrawerItem(label: L("assistant_title"), icon: "sparkles", action: .assistant),
                DrawerItem(label: L("nav_profile"), icon: "person.crop.circle", action: .tab(4)),
                DrawerItem(label: L("ios_help_support"), icon: "questionmark.circle", action: .help),
            ]
        } else {
            return [
                DrawerItem(label: L("nav_dashboard"), icon: "house", action: .tab(0)),
                DrawerItem(label: L("nav_jobs"), icon: "briefcase", action: .tab(1)),
                DrawerItem(label: L("nav_applications"), icon: "clock.arrow.circlepath", action: .tab(2)),
                DrawerItem(label: L("nav_earnings"), icon: "creditcard", action: .tab(3)),
                DrawerItem(label: L("nav_messages"), icon: "bubble.left.and.bubble.right", action: .messages),
                DrawerItem(label: L("assistant_title"), icon: "sparkles", action: .assistant),
                DrawerItem(label: L("nav_profile"), icon: "person.crop.circle", action: .tab(4)),
                DrawerItem(label: L("ios_help_support"), icon: "questionmark.circle", action: .help),
            ]
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            panel
            // Scrim — tap to dismiss.
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)
        }
        .transition(.move(edge: .leading))
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        row(item)
                    }
                }
                .padding(.vertical, 8)
            }
            Divider()
            row(DrawerItem(label: L("log_out"), icon: "rectangle.portrait.and.arrow.right", action: .logout),
                destructive: true)
                .padding(.bottom, 8)
        }
        .frame(width: 300)
        .frame(maxHeight: .infinity)
        .background(Color(.systemBackground))
        .ignoresSafeArea(edges: .vertical)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Circle().fill(.white).frame(width: 64, height: 64)
                .overlay(
                    Group {
                        if let initials = initials, !initials.isEmpty {
                            Text(initials).font(.title.weight(.bold)).foregroundStyle(accent)
                        } else {
                            Image(systemName: "person.fill").font(.title).foregroundStyle(accent)
                        }
                    }
                )
            Text(userName?.isEmpty == false ? userName! : L("ios_gighour_user"))
                .font(.title3.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
            Text(isEmployer ? L("employer") : L("employee"))
                .font(.caption).foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 56).padding(.bottom, 24)
        .background(headerGradient)
    }

    @ViewBuilder
    private func row(_ item: DrawerItem, destructive: Bool = false) -> some View {
        let isActive = isActive(item)
        Button {
            handle(item.action)
        } label: {
            HStack(spacing: 16) {
                Image(systemName: item.icon)
                    .font(.system(size: 20))
                    .frame(width: 24)
                    .foregroundStyle(destructive ? GHTheme.error : (isActive ? accent : GHTheme.onSurfaceVariant))
                Text(item.label)
                    .font(.body.weight(isActive ? .semibold : .regular))
                    .foregroundStyle(destructive ? GHTheme.error : (isActive ? accent : GHTheme.onBackground))
                Spacer()
            }
            .padding(.horizontal, 24).padding(.vertical, 14)
            .background(isActive ? accent.opacity(0.10) : .clear)
        }
        .buttonStyle(.plain)
    }

    private func isActive(_ item: DrawerItem) -> Bool {
        if case let .tab(i) = item.action { return i == selectedTab }
        return false
    }

    private func handle(_ action: DrawerAction) {
        onClose()
        switch action {
        case .tab(let i): onSelectTab(i)
        case .messages: onMessages()
        case .assistant: onAssistant()
        case .help: onHelp()
        case .logout: onLogout()
        }
    }

    private var initials: String? {
        guard let name = userName, !name.isEmpty else { return nil }
        let parts = name.split(separator: " ")
        let first = parts.first?.first.map(String.init) ?? ""
        let second = parts.dropFirst().first?.first.map(String.init) ?? ""
        return (first + second).uppercased()
    }
}
