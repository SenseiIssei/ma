import SwiftUI

/// Karesansui, the dry garden. Every finished pomodoro sets a stone into the
/// raked sand, the streak grows moss around them, and each resisted impulse
/// leaves a small pebble. By evening the day is readable at a glance.
struct ZenGarden: View {
    var stones: Int
    var pebbles: Int
    var mossDays: Int

    private static let spots: [(x: Double, y: Double, r: Double)] = [
        (0.24, 0.52, 1.0), (0.70, 0.38, 0.85), (0.52, 0.74, 0.7), (0.87, 0.72, 0.75),
        (0.10, 0.28, 0.6), (0.42, 0.30, 0.65), (0.62, 0.60, 0.55), (0.33, 0.82, 0.6),
    ]

    var body: some View {
        Canvas { ctx, size in
            let rect = CGRect(origin: .zero, size: size)
            let clip = Path(roundedRect: rect, cornerRadius: Zen.radius, style: .continuous)
            ctx.clip(to: clip)
            ctx.fill(clip, with: .color(Zen.sand))

            let base: CGFloat = min(size.width, size.height) * 0.09
            var placed: [(center: CGPoint, r: CGFloat)] = []
            for spot in Self.spots.prefix(min(stones, Self.spots.count)) {
                let center = CGPoint(x: CGFloat(spot.x) * size.width, y: CGFloat(spot.y) * size.height)
                placed.append((center: center, r: base * CGFloat(spot.r)))
            }

            // Raked lines, broken wherever a stone sits.
            let rake = Zen.inkFaint.opacity(0.45)
            var y: CGFloat = 10
            while y < size.height {
                var path = Path()
                var drawing = false
                var x: CGFloat = 0
                while x <= size.width {
                    let wave = CGFloat(sin(Double(x) / 38 + Double(y) / 21) * 1.4)
                    let pt = CGPoint(x: x, y: y + wave)
                    let blocked = placed.contains { stone in
                        let dx: CGFloat = pt.x - stone.center.x
                        let dy: CGFloat = pt.y - stone.center.y
                        return (dx * dx + dy * dy).squareRoot() < stone.r * 2.6
                    }
                    if blocked {
                        drawing = false
                    } else if drawing {
                        path.addLine(to: pt)
                    } else {
                        path.move(to: pt)
                        drawing = true
                    }
                    x += 4
                }
                ctx.stroke(path, with: .color(rake), lineWidth: 1)
                y += 9
            }

            // Ripples around each stone, then moss, then the stone itself.
            for (index, stone) in placed.enumerated() {
                for ring in 1...3 {
                    let r = stone.r * (1.25 + 0.45 * CGFloat(ring))
                    let circle = Path(ellipseIn: CGRect(x: stone.center.x - r, y: stone.center.y - r * 0.82, width: r * 2, height: r * 1.64))
                    ctx.stroke(circle, with: .color(rake), lineWidth: 1)
                }
                if index < mossDays {
                    var rng = SeededRandom(seed: UInt64(index + 3))
                    for _ in 0..<9 {
                        let a: Double = rng.next() * 2 * Double.pi
                        let d: CGFloat = stone.r * CGFloat(0.8 + rng.next() * 0.45)
                        let s: CGFloat = stone.r * CGFloat(0.22 + rng.next() * 0.2)
                        let cx: CGFloat = stone.center.x + CGFloat(cos(a)) * d
                        let cy: CGFloat = stone.center.y + CGFloat(sin(a)) * d * 0.7 + stone.r * 0.2
                        let c = CGPoint(x: cx, y: cy)
                        ctx.fill(Path(ellipseIn: CGRect(x: c.x - s, y: c.y - s * 0.7, width: s * 2, height: s * 1.4)), with: .color(Zen.matcha.opacity(0.75)))
                    }
                }
                let body = CGRect(x: stone.center.x - stone.r, y: stone.center.y - stone.r * 0.72, width: stone.r * 2, height: stone.r * 1.44)
                ctx.fill(Path(ellipseIn: body.offsetBy(dx: 2, dy: 3)), with: .color(Zen.ink.opacity(0.12)))
                ctx.fill(Path(ellipseIn: body), with: .color(Zen.stone))
                let shine = CGRect(x: body.minX + body.width * 0.22, y: body.minY + body.height * 0.14, width: body.width * 0.34, height: body.height * 0.26)
                ctx.fill(Path(ellipseIn: shine), with: .color(Color.white.opacity(0.14)))
            }

            // Pebbles for resisted impulses, scattered along the bottom edge.
            var rng = SeededRandom(seed: 99)
            for _ in 0..<min(pebbles, 40) {
                let x: CGFloat = CGFloat(0.05 + rng.next() * 0.9) * size.width
                let yy: CGFloat = size.height - CGFloat(8 + rng.next() * 22)
                let s: CGFloat = CGFloat(2 + rng.next() * 2.4)
                ctx.fill(Path(ellipseIn: CGRect(x: x - s, y: yy - s * 0.7, width: s * 2, height: s * 1.4)), with: .color(Zen.stone.opacity(0.7)))
            }
        }
    }
}
