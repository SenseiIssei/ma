import SwiftUI

/// Bedtime, alarm and a short wind-down before sleep. The reminder is one
/// local notification a day; the list is ticked by hand, on purpose.
struct SleepSection: View {
    @Environment(BalanceStore.self) private var balance
    @Environment(\.selectRootTab) private var selectRootTab
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(icon: "moon.stars.fill", title: tr("Sleep", "Schlaf"))
            Illustration(name: "IllustrationEvening", height: 150)
                .overlay(alignment: .bottomLeading) { opportunityBadge }
            planCard
            checklist
            nightTip
        }
    }

    // MARK: Opportunity

    private var opportunityBadge: some View {
        let plan: SleepPlan = balance.settings.sleep
        return VStack(alignment: .leading, spacing: 2) {
            Text(SleepPlan.durationText(plan.opportunity))
                .font(.display(26))
                .foregroundStyle(Zen.ink)
            Text(tr("of sleep opportunity", "Zeit zum Schlafen"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Zen.inkSoft)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(12)
    }

    /// In the evening and at night: what is left if you went to bed now.
    private var phaseLine: String {
        let plan: SleepPlan = balance.settings.sleep
        let untilWake: Int = plan.minutesUntilWake(from: now)
        switch plan.phase(at: now) {
        case .day:
            return tr("Wind-down starts at \(SleepPlan.clock(plan.windDownStart)).",
                      "Das Runterfahren beginnt um \(SleepPlan.clock(plan.windDownStart)).")
        case .windDown:
            return tr("Wind-down time. If you sleep now: \(SleepPlan.durationText(untilWake)) until your alarm.",
                      "Zeit zum Runterfahren. Wenn du jetzt schläfst: \(SleepPlan.durationText(untilWake)) bis zum Wecker.")
        case .night:
            return tr("Past bedtime. \(SleepPlan.durationText(untilWake)) left until your alarm.",
                      "Schon Schlafenszeit. Noch \(SleepPlan.durationText(untilWake)) bis zum Wecker.")
        }
    }

    // MARK: Plan

    private var planCard: some View {
        let plan: SleepPlan = balance.settings.sleep
        let bedtime = Binding<Date>(
            get: { Self.date(minute: plan.bedtime) },
            set: { value in
                var next = balance.settings.sleep
                next.bedtime = SleepPlan.minuteOfDay(value)
                balance.setSleep(next)
            }
        )
        let wake = Binding<Date>(
            get: { Self.date(minute: plan.wake) },
            set: { value in
                var next = balance.settings.sleep
                next.wake = SleepPlan.minuteOfDay(value)
                balance.setSleep(next)
            }
        )
        let reminder = Binding<Bool>(
            get: { balance.settings.reminder },
            set: { on in Task { await balance.setReminder(on) } }
        )
        return VStack(alignment: .leading, spacing: 16) {
            timeRow(icon: "bed.double.fill", tint: Zen.shu, title: tr("Bedtime", "Schlafenszeit"), selection: bedtime)
            timeRow(icon: "alarm.fill", tint: Zen.kin, title: tr("Alarm", "Wecker"), selection: wake)

            Divider().overlay(Zen.line)

            VStack(alignment: .leading, spacing: 10) {
                Text(tr("Wind-down before bed", "Runterfahren vor dem Schlafen"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Zen.ink)
                HStack(spacing: 8) {
                    ForEach(SleepPlan.windDownChoices, id: \.self) { minutes in
                        Chip(title: tr("\(minutes) min", "\(minutes) Min."), selected: plan.windDown == minutes) {
                            var next = balance.settings.sleep
                            next.windDown = minutes
                            balance.setSleep(next)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }

            Toggle(isOn: reminder) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("Remind me to wind down", "Erinner mich ans Runterfahren"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Zen.ink)
                    Text(tr("Every day at \(SleepPlan.clock(plan.windDownStart)).", "Jeden Tag um \(SleepPlan.clock(plan.windDownStart))."))
                        .font(.system(size: 13))
                        .foregroundStyle(Zen.inkSoft)
                }
            }
            .tint(Zen.shu)

            BalanceNote(icon: "clock", text: phaseLine)
        }
        .zenCard(padding: 20)
    }

    private func timeRow(icon: String, tint: Color, title: String, selection: Binding<Date>) -> some View {
        HStack(spacing: 12) {
            IconBadge(systemName: icon, tint: tint, size: 36)
            DatePicker(selection: selection, displayedComponents: .hourAndMinute) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Zen.ink)
            }
            .environment(\.locale, Loc.locale)
        }
    }

    /// A date today at the given minute, only for the time pickers.
    static func date(minute: Int) -> Date {
        let start: Date = Calendar.current.startOfDay(for: Date())
        return Calendar.current.date(byAdding: .minute, value: SleepPlan.normalized(minute), to: start) ?? start
    }

    // MARK: Checklist

    private var checklist: some View {
        let ticked: Set<WindDownItem> = balance.tonight.windDown
        let highlight: Bool = balance.settings.sleep.phase(at: now) != .day
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(tr("Tonight's wind-down", "Runterfahren heute Abend"))
                    .font(.display(18))
                    .foregroundStyle(Zen.ink)
                Spacer()
                Text("\(ticked.count)/\(WindDownItem.allCases.count)")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(ticked.count == WindDownItem.allCases.count ? Zen.matcha : Zen.inkSoft)
            }
            ForEach(WindDownItem.allCases) { item in
                checkRow(item, on: ticked.contains(item))
            }
        }
        .zenCard(padding: 20)
        .overlay(
            RoundedRectangle(cornerRadius: Zen.radius, style: .continuous)
                .strokeBorder(Zen.shu.opacity(highlight ? 0.6 : 0), lineWidth: 1.5)
        )
    }

    private func checkRow(_ item: WindDownItem, on: Bool) -> some View {
        Button {
            if on { Haptics.tap() } else { Haptics.success() }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { balance.toggle(item) }
        } label: {
            HStack(spacing: 12) {
                IconBadge(systemName: item.symbol, tint: Zen.shu, size: 36, filled: on)
                Text(item.title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(on ? Zen.inkSoft : Zen.ink)
                    .strikethrough(on, color: Zen.inkFaint)
                Spacer(minLength: 0)
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(on ? Zen.matcha : Zen.inkFaint)
                    .contentTransition(.symbolEffect(.replace))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: Night boundary

    private var nightTip: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                IconBadge(systemName: "shield.lefthalf.filled", tint: Zen.shu, size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("Let the night guard itself", "Lass die Nacht auf sich aufpassen"))
                        .font(.display(18))
                        .foregroundStyle(Zen.ink)
                    Text(tr("The Night template under Boundaries keeps the feeds closed from 22:00 to 07:00, so the wind-down is not a fight with your thumb.",
                            "Die Vorlage Nacht unter Grenzen hält die Feeds von 22:00 bis 07:00 geschlossen, damit das Runterfahren kein Kampf mit deinem Daumen wird."))
                        .font(.system(size: 14))
                        .foregroundStyle(Zen.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Button {
                Haptics.tap()
                selectRootTab(.rules)
            } label: {
                Label(tr("Open Boundaries", "Grenzen öffnen"), systemImage: "arrow.right")
            }
            .buttonStyle(.quiet)
        }
        .zenCard(padding: 20)
    }
}
