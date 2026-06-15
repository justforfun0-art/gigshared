import SwiftUI
import Shared

/// The app's design tokens — a direct port of Android's ui/theme/Color.kt so the
/// iOS screens share the same violet/green palette, neutrals, and status colors.
enum GHTheme {
    // Brand
    static let primary = hex(0x7C3AED)        // violet-600
    static let primaryVariant = hex(0x6D28D9)
    static let primaryLight = hex(0xA78BFA)
    static let primaryContainer = hex(0xF5F3FF)

    static let secondary = hex(0x6366F1)      // indigo-500
    static let secondaryContainer = hex(0xE0E7FF)

    static let tertiary = hex(0x10B981)       // emerald-500
    static let tertiaryVariant = hex(0x059669)
    static let tertiaryContainer = hex(0xD1FAE5)

    // Neutrals
    static let onBackground = hex(0x111827)   // gray-900
    static let surfaceVariant = hex(0xF9FAFB) // gray-50
    static let onSurfaceVariant = hex(0x6B7280) // gray-500
    static let muted = hex(0x9CA3AF)          // gray-400
    static let outline = hex(0xE5E7EB)        // gray-200

    // Status
    static let success = hex(0x22C55E)
    static let successContainer = hex(0xDCFCE7)
    static let warning = hex(0xF59E0B)
    static let warningContainer = hex(0xFEF3C7)
    static let error = hex(0xEF4444)
    static let errorContainer = hex(0xFEE2E2)
    static let info = hex(0x3B82F6)
    static let infoContainer = hex(0xDBEAFE)

    /// Header/CTA gradient (violet → indigo), the web/Android hero gradient.
    static let heroGradient = LinearGradient(
        colors: [hex(0x7C3AED), hex(0x9333EA), hex(0x4F46E5)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    /// Soft page background (violet-50 → white → indigo-50).
    static let pageGradient = LinearGradient(
        colors: [hex(0xF5F3FF), .white, hex(0xEEF2FF)],
        startPoint: .top, endPoint: .bottom
    )

    static func hex(_ rgb: UInt) -> Color {
        Color(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}

/// Per-status badge colors (text + soft background), ported from Android's
/// getStatusColors. Used by the Applications list + work-session screens.
struct StatusStyle {
    let text: Color
    let background: Color

    static func of(_ status: ApplicationStatus) -> StatusStyle {
        switch status {
        case .applied:
            return StatusStyle(text: GHTheme.hex(0x1D4ED8), background: GHTheme.hex(0xDBEAFE))
        case .shortlisted:
            return StatusStyle(text: GHTheme.hex(0x1D4ED8), background: GHTheme.hex(0xDBEAFE))
        case .selected:
            return StatusStyle(text: GHTheme.hex(0x047857), background: GHTheme.hex(0xD1FAE5))
        case .accepted, .hired:
            return StatusStyle(text: GHTheme.hex(0x15803D), background: GHTheme.hex(0xDCFCE7))
        case .otpRequested:
            return StatusStyle(text: GHTheme.hex(0x7C3AED), background: GHTheme.hex(0xEDE9FE))
        case .workInProgress:
            return StatusStyle(text: GHTheme.hex(0x4338CA), background: GHTheme.hex(0xE0E7FF))
        case .completionPending:
            return StatusStyle(text: GHTheme.hex(0xC2410C), background: GHTheme.hex(0xFFEDD5))
        case .paymentPending:
            return StatusStyle(text: GHTheme.hex(0xA16207), background: GHTheme.hex(0xFEF9C3))
        case .completed:
            return StatusStyle(text: GHTheme.hex(0x15803D), background: GHTheme.hex(0xDCFCE7))
        case .rejected, .rejectedOnce, .rejectedAndReshown, .noShow, .jobCancelled, .positionFilled:
            return StatusStyle(text: GHTheme.hex(0x991B1B), background: GHTheme.hex(0xFEE2E2))
        case .expired, .withdrawn, .notInterested:
            return StatusStyle(text: GHTheme.hex(0x6B7280), background: GHTheme.hex(0xF3F4F6))
        default:
            return StatusStyle(text: GHTheme.hex(0x6B7280), background: GHTheme.hex(0xF3F4F6))
        }
    }
}

// MARK: - Reusable card surface

/// The standard rounded white card with a hairline outline + soft shadow used
/// across the restyled list screens (matches Android's Card look).
struct GHCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(GHTheme.outline, lineWidth: 1))
            .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }
}

/// A soft status pill (text + tinted capsule), Android's StatusBadge.
struct StatusBadgeView: View {
    let status: ApplicationStatus
    var body: some View {
        let s = StatusStyle.of(status)
        Text(status.toDisplayString())
            .font(.caption.weight(.semibold))
            .foregroundStyle(s.text)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(s.background, in: Capsule())
    }
}
