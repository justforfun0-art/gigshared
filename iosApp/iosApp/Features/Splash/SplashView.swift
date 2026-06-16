import SwiftUI
import UIKit

/// Orbit Design System splash — the iOS port of Android's AnimatedSplashScreen:
/// dark radial-gradient stage, a gradient clock-icon tile (white open ring +
/// fixed mint arm with a pulsing dot + a continuously rotating white sweep),
/// the GigHour wordmark with a mint accent tagline, and animated loading dots.
struct SplashView: View {

    // Orbit palette (matches the Android constants).
    private static let bgDeep = Color(red: 0x0E/255, green: 0x08/255, blue: 0x28/255)
    private static let bgBase = Color(red: 0x16/255, green: 0x10/255, blue: 0x37/255)
    private static let violet = Color(red: 0x59/255, green: 0x21/255, blue: 0xB5/255)
    private static let mint   = Color(red: 0x26/255, green: 0xD9/255, blue: 0x62/255)
    private static let fg     = Color.white
    private static let fg2    = Color.white.opacity(0.70)

    @State private var tileShown = false
    @State private var wordmarkShown = false

    var body: some View {
        ZStack {
            RadialGradient(
                gradient: Gradient(stops: [
                    .init(color: Self.violet, location: 0.0),
                    .init(color: Self.bgBase, location: 0.55),
                    .init(color: Self.bgDeep, location: 1.0)
                ]),
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 1200
            )
            .ignoresSafeArea()

            VStack(spacing: 40) {
                ClockIconTile()
                    .opacity(tileShown ? 1 : 0)
                    .scaleEffect(tileShown ? 1 : 0.85)

                wordmark
                    .opacity(wordmarkShown ? 1 : 0)
            }
            .padding(.horizontal, 24)

            VStack {
                Spacer()
                LoadingDots()
                    .padding(.bottom, 64)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.7)) { tileShown = true }
            withAnimation(.easeInOut(duration: 0.6).delay(0.2)) { wordmarkShown = true }
        }
    }

    private var wordmark: some View {
        VStack(spacing: 10) {
            Text(L("app_name"))
                .font(.system(size: 40, weight: .bold))
                .tracking(-0.8)
                .foregroundStyle(Self.fg)

            Text(L("splash_subtagline"))
                .font(.system(size: 12, weight: .semibold))
                .tracking(2.6)
                .foregroundStyle(Self.mint)

            Text(L("splash_tagline"))
                .font(.system(size: 15))
                .foregroundStyle(Self.fg2)
        }
        .multilineTextAlignment(.center)
    }
}

/// The animated clock-icon tile: a violet gradient rounded square holding a
/// white ring, a fixed mint clock arm + pulsing dot, a center pin, and a white
/// sweep hand that rotates once every 4.5s. Driven by TimelineView so the
/// animation is continuous and self-contained.
private struct ClockIconTile: View {
    private static let mint = Color(red: 0x26/255, green: 0xD9/255, blue: 0x62/255)
    private static let bgBase = Color(red: 0x16/255, green: 0x10/255, blue: 0x37/255)
    private static let violet = Color(red: 0x59/255, green: 0x21/255, blue: 0xB5/255)

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let sweep = Angle.degrees((t.truncatingRemainder(dividingBy: 4.5) / 4.5) * 360)
            // Smooth 0..1 pulse on a 2.2s triangle wave for the mint dot + glow.
            let pulse = abs((t.truncatingRemainder(dividingBy: 2.2) / 2.2) * 2 - 1)

            ZStack {
                // Soft mint glow halo behind the tile.
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [Self.mint.opacity(0.18), .clear]),
                            center: .center, startRadius: 0, endRadius: 160
                        )
                    )
                    .frame(width: 320, height: 320)
                    .scaleEffect(0.96 + 0.08 * pulse)
                    .opacity(0.55 + 0.4 * pulse)

                // Tile + clock face.
                Canvas { ctx, size in
                    let cx = size.width / 2, cy = size.height / 2
                    let s = size.width
                    let ringR = s * (48.0 / 160.0)
                    let stroke = s * (4.0 / 160.0)
                    let armLen = s * (28.0 / 160.0)
                    let sweepLen = s * (42.0 / 160.0)
                    let dotOff = s * (32.0 / 160.0)
                    let dotR = s * ((3.5 + 1.1 * pulse) / 160.0)
                    let pin = s * (3.4 / 160.0)
                    let c = CGPoint(x: cx, y: cy)

                    // White open ring.
                    var ring = Path()
                    ring.addArc(center: c, radius: ringR, startAngle: .zero, endAngle: .degrees(360), clockwise: false)
                    ctx.stroke(ring, with: .color(.white), lineWidth: stroke)

                    // Fixed mint arm (12 o'clock).
                    var arm = Path()
                    arm.move(to: c)
                    arm.addLine(to: CGPoint(x: cx, y: cy - armLen))
                    ctx.stroke(arm, with: .color(Self.mint), style: StrokeStyle(lineWidth: stroke, lineCap: .round))

                    // Pulsing mint dot near 12.
                    let dotRect = CGRect(x: cx - dotR, y: cy - dotOff - dotR, width: dotR * 2, height: dotR * 2)
                    ctx.fill(Path(ellipseIn: dotRect), with: .color(Self.mint))

                    // Rotating white sweep hand.
                    var sweepPath = Path()
                    sweepPath.move(to: c)
                    sweepPath.addLine(to: CGPoint(x: cx, y: cy - sweepLen))
                    var rotated = ctx
                    rotated.translateBy(x: cx, y: cy)
                    rotated.rotate(by: sweep)
                    rotated.translateBy(x: -cx, y: -cy)
                    rotated.stroke(sweepPath, with: .color(.white), style: StrokeStyle(lineWidth: stroke, lineCap: .round))

                    // Center pin.
                    let pinRect = CGRect(x: cx - pin, y: cy - pin, width: pin * 2, height: pin * 2)
                    ctx.fill(Path(ellipseIn: pinRect), with: .color(.white))
                }
                .frame(width: 160, height: 160)
                .background(
                    LinearGradient(colors: [Self.bgBase, Self.violet], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .clipShape(RoundedRectangle(cornerRadius: 36))
            }
        }
    }
}

/// Three loading dots that ripple from translucent white to mint.
private struct LoadingDots: View {
    private static let fg3 = Color.white.opacity(0.48)
    private static let mint = Color(red: 0x26/255, green: 0xD9/255, blue: 0x62/255)

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { i in
                    let phase = abs(((t - Double(i) * 0.15).truncatingRemainder(dividingBy: 1.2) / 1.2) * 2 - 1)
                    Circle()
                        .fill(Self.fg3.interpolated(to: Self.mint, amount: phase))
                        .frame(width: 6, height: 6)
                        .opacity(0.3 + 0.7 * phase)
                }
            }
        }
    }
}

private extension Color {
    /// Linear RGB interpolation between two colors (for the dot ripple).
    func interpolated(to other: Color, amount: Double) -> Color {
        let a = UIColor(self), b = UIColor(other)
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        let t = CGFloat(max(0, min(1, amount)))
        return Color(red: ar + (br - ar) * t, green: ag + (bg - ag) * t, blue: ab + (bb - ab) * t)
            .opacity(aa + (ba - aa) * t)
    }
}
