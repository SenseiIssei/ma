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

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.10))
                .scaleEffect(inhale ? 1.0 : 0.62)
            Circle()
                .fill(tint.opacity(0.18))
                .scaleEffect(inhale ? 0.78 : 0.5)
            Circle()
                .fill(Zen.accentGradient)
                .scaleEffect(inhale ? 0.52 : 0.36)
                .shadow(color: tint.opacity(0.35), radius: 24, y: 8)
        }
    }
}
