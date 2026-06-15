import SwiftUI
import UIKit

/// A bottom navigation item (matches Android's NavigationItem).
struct GHTab: Identifiable {
    let id = UUID()
    let label: String
    let icon: String      // SF Symbol
    var badge: Int = 0
}

/// Android-style bottom navigation bar — the iOS port of BottomNavigationBar.kt.
/// White bar with a soft top shadow, role accent color (violet for employees,
/// green for employers), a top indicator pill over the selected tab, larger
/// icons, gray unselected items, and a press-scale bounce. Replaces SwiftUI's
/// stock TabView bar (which can't be styled this way).
struct GHBottomBar: View {
    let tabs: [GHTab]
    @Binding var selected: Int
    let isEmployer: Bool

    private var accent: Color { isEmployer ? GHTheme.tertiary : GHTheme.primary }
    private let unselected = GHTheme.onSurfaceVariant   // gray-500

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                item(tab, isSelected: index == selected)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if selected != index {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            selected = index
                        }
                    }
            }
        }
        .frame(height: 64)
        .padding(.horizontal, 4)
        .background(
            Color(.systemBackground)
                .shadow(color: .black.opacity(0.06), radius: 8, y: -2)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    @ViewBuilder
    private func item(_ tab: GHTab, isSelected: Bool) -> some View {
        ZStack(alignment: .top) {
            // Top indicator pill over the selected tab.
            if isSelected {
                RoundedRectangle(cornerRadius: 2)
                    .fill(accent)
                    .frame(width: 32, height: 3)
            }
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: tab.icon)
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(isSelected ? accent : unselected)
                        .frame(width: 30, height: 30)
                    if tab.badge > 0 {
                        Text(tab.badge > 99 ? "99+" : "\(tab.badge)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(GHTheme.error, in: Capsule())
                            .offset(x: 10, y: -4)
                    }
                }
                Text(tab.label)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? accent : unselected)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.top, 10)
            .padding(.bottom, 6)
            .scaleEffect(isSelected ? 1 : 1)
        }
    }
}
