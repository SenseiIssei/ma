import Foundation

// Breathing rhythms for the watch. The timings are copied from BreathPattern
// in App/Day/DayModels.swift, which the watch does not compile (it pulls in
// the whole day model). The test harness checks both stay equal.
// Foundation only, so the timing can be tested without a watch.

enum WatchBreathKind: Equatable {
    case inhale, holdFull, exhale, holdEmpty

    var label: String {
        switch self {
        case .inhale: return tr("Breathe in", "Einatmen")
        case .holdFull, .holdEmpty: return tr("Hold", "Halten")
        case .exhale: return tr("Breathe out", "Ausatmen")
        }
    }
}

struct WatchBreathStep: Equatable {
    var kind: WatchBreathKind
    var seconds: Double
}

struct WatchBreathPattern: Identifiable, Equatable, Hashable {
    let id: String
    let steps: [WatchBreathStep]

    static func == (lhs: WatchBreathPattern, rhs: WatchBreathPattern) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var cycle: Double { steps.reduce(0) { $0 + $1.seconds } }

    var title: String {
        switch id {
        case "box": return tr("Box", "Box")
        case "478": return "4-7-8"
        default: return tr("Calm", "Ruhe")
        }
    }

    /// "4-4-4-4", "4-7-8", "4-6".
    var rhythm: String {
        steps.map { String(Int($0.seconds)) }.joined(separator: "-")
    }

    static let box = WatchBreathPattern(id: "box", steps: [
        WatchBreathStep(kind: .inhale, seconds: 4), WatchBreathStep(kind: .holdFull, seconds: 4),
        WatchBreathStep(kind: .exhale, seconds: 4), WatchBreathStep(kind: .holdEmpty, seconds: 4),
    ])
    static let fourSevenEight = WatchBreathPattern(id: "478", steps: [
        WatchBreathStep(kind: .inhale, seconds: 4), WatchBreathStep(kind: .holdFull, seconds: 7),
        WatchBreathStep(kind: .exhale, seconds: 8),
    ])
    static let calm = WatchBreathPattern(id: "calm", steps: [
        WatchBreathStep(kind: .inhale, seconds: 4), WatchBreathStep(kind: .exhale, seconds: 6),
    ])
    static let all: [WatchBreathPattern] = [.box, .fourSevenEight, .calm]
    static let durations: [Int] = [1, 3, 5]

    /// A session always ends on a finished out-breath, never halfway in.
    func sessionLength(minutes: Int) -> Double {
        let wanted: Double = Double(max(1, minutes)) * 60
        return (wanted / cycle).rounded(.up) * cycle
    }

    func state(at elapsed: Double) -> WatchBreathState {
        let t: Double = max(0, elapsed)
        let cycleIndex = Int(t / cycle)
        var inCycle: Double = t - Double(cycleIndex) * cycle
        for (index, step) in steps.enumerated() {
            if inCycle < step.seconds || index == steps.count - 1 {
                let into: Double = min(inCycle, step.seconds)
                return WatchBreathState(cycle: cycleIndex, stepIndex: index, kind: step.kind,
                                        elapsedInStep: into, stepSeconds: step.seconds)
            }
            inCycle -= step.seconds
        }
        return WatchBreathState(cycle: cycleIndex, stepIndex: 0, kind: .inhale, elapsedInStep: 0, stepSeconds: 1)
    }

    /// Seconds from `elapsed` to the start of the next step, for the haptic
    /// loop: it sleeps exactly that long instead of polling.
    func secondsToNextStep(at elapsed: Double) -> Double {
        let now: WatchBreathState = state(at: elapsed)
        return max(0, now.stepSeconds - now.elapsedInStep)
    }
}

struct WatchBreathState: Equatable {
    var cycle: Int
    var stepIndex: Int
    var kind: WatchBreathKind
    var elapsedInStep: Double
    var stepSeconds: Double

    /// Changes on every phase switch, the trigger for haptics.
    var tick: Int { cycle * 16 + stepIndex }

    var secondsLeft: Int { max(1, Int((stepSeconds - elapsedInStep).rounded(.up))) }

    /// How open the circle is, 0 empty to 1 full, eased so it breathes.
    var openness: Double {
        let p: Double = stepSeconds > 0 ? min(1, max(0, elapsedInStep / stepSeconds)) : 1
        let eased: Double = 0.5 - cos(p * Double.pi) / 2
        switch kind {
        case .inhale: return eased
        case .holdFull: return 1
        case .exhale: return 1 - eased
        case .holdEmpty: return 0
        }
    }
}

/// Which haptic a phase starts with. Plain names so the mapping is testable
/// without WatchKit; BreathRunner turns them into WKHapticType.
enum BreathCue: Equatable {
    case start, stop, click

    static func at(_ kind: WatchBreathKind) -> BreathCue {
        switch kind {
        case .inhale: return .start
        case .exhale: return .stop
        case .holdFull, .holdEmpty: return .click
        }
    }
}
