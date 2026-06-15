import SwiftUI

/// A short celebratory confetti burst shown on an apply swipe (port of the
/// Android ConfettiAnimation). Particles fall + spin from the top over ~0.9s,
/// drawn in a single Canvas driven by TimelineView.
struct ConfettiView: View {
    private struct Particle {
        let x: CGFloat          // 0..1 horizontal start
        let color: Color
        let delay: Double
        let drift: CGFloat      // horizontal drift factor
        let spin: Double
        let size: CGFloat
    }

    private let start = Date()
    private let particles: [Particle]

    init() {
        let colors: [Color] = [
            Color(red: 0x22/255, green: 0xC5/255, blue: 0x5E/255),
            Color(red: 0x3B/255, green: 0x82/255, blue: 0xF6/255),
            Color(red: 0xF5/255, green: 0x9E/255, blue: 0x0B/255),
            Color(red: 0xEC/255, green: 0x48/255, blue: 0x99/255),
            Color(red: 0x8B/255, green: 0x5C/255, blue: 0xF6/255)
        ]
        particles = (0..<70).map { _ in
            Particle(
                x: .random(in: 0...1),
                color: colors.randomElement()!,
                delay: .random(in: 0...0.2),
                drift: .random(in: -0.15...0.15),
                spin: .random(in: 0...360),
                size: .random(in: 5...10)
            )
        }
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSince(start)
                for p in particles {
                    let pt = t - p.delay
                    guard pt > 0 else { continue }
                    let progress = min(pt / 0.9, 1.0)
                    let y = size.height * CGFloat(progress) * 1.05
                    let x = size.width * (p.x + p.drift * CGFloat(progress))
                    let alpha = 1.0 - progress
                    var rect = ctx
                    rect.translateBy(x: x, y: y)
                    rect.rotate(by: .degrees(p.spin + progress * 360))
                    rect.opacity = alpha
                    let r = CGRect(x: -p.size / 2, y: -p.size / 2, width: p.size, height: p.size * 0.6)
                    rect.fill(Path(roundedRect: r, cornerRadius: 1), with: .color(p.color))
                }
            }
            .ignoresSafeArea()
        }
    }
}
