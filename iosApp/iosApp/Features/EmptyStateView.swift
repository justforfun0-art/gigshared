import SwiftUI

/// Animated empty-state — port of Android's `EmptyState` composable. A tinted
/// circle holding an SF Symbol that gently floats up/down, wrapped by an
/// expanding-and-fading pulse ring, with a positive title + description and an
/// optional action button. Reusable across the app's empty screens.
struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    var iconBG: Color = GHTheme.hex(0xD1FAE5)   // emerald-100
    var iconFG: Color = GHTheme.hex(0x059669)   // emerald-600
    var actionLabel: String? = nil
    var action: (() -> Void)? = nil

    @State private var floating = false
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                // Pulse ring — expands and fades, repeating.
                Circle()
                    .fill(iconBG)
                    .frame(width: 64, height: 64)
                    .scaleEffect(pulse ? 1.5 : 0.85)
                    .opacity(pulse ? 0 : 0.4)
                    .animation(.easeOut(duration: 2).repeatForever(autoreverses: false), value: pulse)
                // Floating icon disc.
                Circle()
                    .fill(iconBG)
                    .frame(width: 64, height: 64)
                    .overlay(Image(systemName: systemImage).font(.system(size: 30, weight: .medium)).foregroundStyle(iconFG))
                    .offset(y: floating ? -10 : 0)
                    .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: floating)
            }
            .frame(width: 80, height: 80)

            Text(title)
                .font(.headline)
                .foregroundStyle(GHTheme.onBackground)
                .multilineTextAlignment(.center)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(GHTheme.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)

            if let actionLabel, let action {
                Button(action: action) {
                    Text(actionLabel).fontWeight(.semibold).foregroundStyle(.white)
                        .padding(.horizontal, 20).padding(.vertical, 10)
                        .background(GHTheme.hex(0x7C3AED), in: Capsule())
                }
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 16)
        .onAppear { floating = true; pulse = true }
    }
}
