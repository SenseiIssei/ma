import SwiftUI

/// The ensō, drawn like a single brush stroke: heavy where the brush lands,
/// thinning and splitting into dry bristles as the ink runs out.
///
/// Conforms to Animatable so `withAnimation` can paint it stroke by stroke.
struct EnsoView: View, Animatable {
    var progress: Double
    var lineWidth: CGFloat = 16
    var color: Color = Zen.ink
    /// Part of the circle left open, as in most ensō. 0.06 is a small gap.
    var gap: Double = 0.06

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Canvas { ctx, size in
            let p = min(1, max(0, progress))
            guard p > 0.001 else { return }
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 - lineWidth
            let start = -Double.pi / 2 - 0.5
            let fullSweep = 2 * Double.pi * (1 - gap)
            let steps = max(3, Int(220 * p))

            func point(_ u: Double, offset: CGFloat) -> CGPoint {
                let angle: Double = start + fullSweep * u
                let wobble = CGFloat(1 + 0.014 * sin(u * 7.3 + 0.8) + 0.006 * sin(u * 23))
                let r: CGFloat = (radius + offset) * wobble
                return CGPoint(x: center.x + r * CGFloat(cos(angle)), y: center.y + r * CGFloat(sin(angle)))
            }

            func width(_ u: Double) -> CGFloat {
                let landing: Double = min(1, u * 14)             // the brush touching down
                let fading: Double = 1 - pow(u, 2.4) * 0.72      // ink running out
                let pulse: Double = 0.9 + 0.1 * sin(u * 11)
                let factor: Double = max(0.12, (0.45 + 0.55 * landing) * fading * pulse)
                return lineWidth * CGFloat(factor)
            }

            // Main body of the stroke.
            for i in 0..<steps {
                let u0 = p * Double(i) / Double(steps)
                let u1 = p * Double(i + 1) / Double(steps)
                var seg = Path()
                seg.move(to: point(u0, offset: 0))
                seg.addLine(to: point(u1, offset: 0))
                ctx.stroke(seg, with: .color(color), style: StrokeStyle(lineWidth: width(u0), lineCap: .round))
            }

            // Dry bristles: thin strands that separate towards the tail.
            for (offsetFactor, alpha) in [(-0.32, 0.55), (0.3, 0.45), (0.05, 0.3)] {
                var strand = Path()
                var started = false
                for i in 0...steps {
                    let u = p * Double(i) / Double(steps)
                    guard u > 0.55 else { continue }
                    let spread = CGFloat(offsetFactor * (1 + (u - 0.55) * 2))
                    let pt = point(u, offset: width(u) * spread)
                    if started { strand.addLine(to: pt) } else { strand.move(to: pt); started = true }
                }
                ctx.stroke(strand, with: .color(Zen.paper.opacity(alpha)), style: StrokeStyle(lineWidth: max(0.8, lineWidth * 0.08), lineCap: .round))
            }
        }
    }
}

/// Slow breathing circle for the moment before a question.
struct BreathingEnso: View {
    var inhale: Bool
    var body: some View {
        EnsoView(progress: 1, lineWidth: 12, color: Zen.ink.opacity(0.85))
            .scaleEffect(inhale ? 1 : 0.72)
            .opacity(inhale ? 1 : 0.6)
    }
}
