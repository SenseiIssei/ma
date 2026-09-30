import SwiftUI

/// Once a brush-stroke ensō, now a clean ring. The name stays so older call
/// sites keep working; new code should use `ProgressRing` directly.
struct EnsoView: View, Animatable {
    var progress: Double
    var lineWidth: CGFloat = 16
    var color: Color = Zen.shu
    var gap: Double = 0

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        ProgressRing(progress: progress, lineWidth: lineWidth, tint: color)
    }
}

/// Soft layered circles that swell on the in-breath and settle on the out-breath.
struct BreathingEnso: View {
    var inhale: Bool
    var tint: Color = Zen.shu
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // With Reduce Motion the circles hold still and only brighten or dim.
        let grow: Bool = reduceMotion ? true : inhale
        let glow: Double = reduceMotion ? (inhale ? 1 : 0.45) : 1
        ZStack {
            Circle()
                .fill(tint.opacity(0.10))
                .scaleEffect(grow ? 1.0 : 0.62)
            Circle()
                .fill(tint.opacity(0.18))
                .scaleEffect(grow ? 0.78 : 0.5)
            Circle()
                .fill(Zen.accentGradient)
                .scaleEffect(grow ? 0.52 : 0.36)
                .shadow(color: tint.opacity(0.35), radius: 24, y: 8)
                .opacity(glow)
        }
        .accessibilityHidden(true)
    }
}
