import SwiftUI

/// Water, a light look at the meals, a daily tip and the week. Self
/// reflection only: no calories, no scores, nothing to feel bad about.
struct FoodSection: View {
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(icon: "fork.knife", title: tr("Food and water", "Essen und Trinken"))
            WaterCard()
            MealsCard()
            NutritionTipCard(now: now)
            FoodWeekCard(now: now)
        }
    }
}

// MARK: - Water

struct WaterCard: View {
    @Environment(BalanceStore.self) private var balance

    var body: some View {
        let glasses: Int = balance.today.water
        let target: Int = balance.settings.waterTarget
        let left: Int = WaterMath.remaining(glasses: glasses, target: target)
        let targetBinding = Binding<Int>(
            get: { balance.settings.waterTarget },
            set: { balance.setWaterTarget($0) }
        )
        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 18) {
                addButton(glasses: glasses)
                VStack(alignment: .leading, spacing: 6) {
                    Text(Self.liters(glasses))
                        .displayFont(30)
                        .monospacedDigit()
                        .foregroundStyle(Zen.ink)
                        .contentTransition(.numericText())
                    Text(tr("of \(Self.liters(target))", "von \(Self.liters(target))"))
                        .scaledFont(size: 14, weight: .medium)
                        .foregroundStyle(Zen.inkSoft)
                    Text(left == 0
                         ? tr("Goal reached. Well done.", "Ziel erreicht. Gut gemacht.")
                         : tr("\(left) more to go", "noch \(left)"))
                        .scaledFont(size: 14, weight: .semibold)
                        .foregroundStyle(left == 0 ? Zen.matcha : Zen.ai)
                    Button {
                        Haptics.tap()
                        balance.removeWater()
                    } label: {
                        Label(tr("One less", "Eins weniger"), systemImage: "minus")
                            .scaledFont(size: 13, weight: .semibold)
                            .foregroundStyle(Zen.inkSoft)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .background(Zen.sand, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(glasses == 0)
                    .opacity(glasses == 0 ? 0.4 : 1)
                    .padding(.top, 4)
                }
                Spacer(minLength: 0)
            }

            glassRow(glasses: glasses, target: target)

            Stepper(value: targetBinding, in: WaterMath.targetRange) {
                Text(tr("Daily goal: \(target) glasses", "Tagesziel: \(target) Gläser"))
                    .scaledFont(size: 15, weight: .semibold)
                    .foregroundStyle(Zen.ink)
            }
            Text(tr("One glass is 250 ml. Tea and other unsweetened drinks count too.",
                    "Ein Glas sind 250 ml. Tee und andere ungesüßte Getränke zählen mit."))
                .scaledFont(size: 13)
                .foregroundStyle(Zen.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .zenCard(padding: 20)
    }

    /// The big target: a whole circle to tap, one glass per tap.
    private func addButton(glasses: Int) -> some View {
        let progress: Double = balance.waterProgress
        return Button {
            Haptics.tap()
            balance.addWater()
            if balance.waterProgress >= 1 && progress < 1 { Haptics.success() }
        } label: {
            ZStack {
                ProgressRing(progress: progress, lineWidth: 10, tint: Zen.ai)
                Circle()
                    .fill(Zen.ai.opacity(0.14))
                    .padding(16)
                VStack(spacing: 2) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Zen.ai)
                    Text("\(glasses)")
                        .displayFont(30)
                        .monospacedDigit()
                        .foregroundStyle(Zen.ink)
                        .contentTransition(.numericText())
                    Text(tr("+1 glass", "+1 Glas"))
                        .scaledFont(size: 12, weight: .semibold)
                        .foregroundStyle(Zen.inkSoft)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 26)
            }
            .frame(width: 140, height: 140)
            // Three lines inside a fixed circle: stop growing before they spill out.
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tr("Add a glass of water", "Ein Glas Wasser dazu"))
        .accessibilityValue(tr("\(glasses) of \(balance.settings.waterTarget) glasses", "\(glasses) von \(balance.settings.waterTarget) Gläsern"))
    }

    private func glassRow(glasses: Int, target: Int) -> some View {
        let shown: Int = max(target, glasses)
        let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 6), count: 8)
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(0..<shown, id: \.self) { index in
                Image(systemName: index < glasses ? "drop.fill" : "drop")
                    .scaledFont(size: 18, weight: .semibold)
                    .foregroundStyle(index < glasses ? Zen.ai : Zen.inkFaint)
            }
        }
        .accessibilityHidden(true)
    }

    static func liters(_ glasses: Int) -> String {
        let value: Double = WaterMath.liters(glasses: glasses)
        let number: String = value.formatted(.number.precision(.fractionLength(0...2)).locale(Loc.locale))
        return tr("\(number) l", "\(number) l")
    }
}

// MARK: - Meals

struct MealsCard: View {
    @Environment(BalanceStore.self) private var balance

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(tr("Meal check", "Mahlzeiten-Check"))
                    .displayFont(18)
                    .foregroundStyle(Zen.ink)
                Text(tr("Only for you: no calories, no judgement. Just a look at what was on the plate.",
                        "Nur für dich: keine Kalorien, kein Urteil. Nur ein Blick auf das, was auf dem Teller war."))
                    .scaledFont(size: 13)
                    .foregroundStyle(Zen.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Meal.allCases) { meal in
                mealRow(meal)
                if meal != Meal.allCases.last {
                    Divider().overlay(Zen.line)
                }
            }
        }
        .zenCard(padding: 20)
    }

    private func mealRow(_ meal: Meal) -> some View {
        let entry: MealEntry = balance.today.meal(meal)
        let columns: [GridItem] = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                Haptics.tap()
                balance.toggleEaten(meal)
            } label: {
                HStack(spacing: 12) {
                    IconBadge(systemName: meal.symbol, tint: Zen.kin, size: 36, filled: entry.eaten)
                    Text(meal.title)
                        .scaledFont(size: 16, weight: .semibold, design: .rounded)
                        .foregroundStyle(Zen.ink)
                    Spacer(minLength: 0)
                    Image(systemName: entry.eaten ? "checkmark.circle.fill" : "circle")
                        .scaledFont(size: 22)
                        .foregroundStyle(entry.eaten ? Zen.matcha : Zen.inkFaint)
                        .contentTransition(.symbolEffect(.replace))
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(entry.eaten ? .isSelected : [])
            .accessibilityValue(entry.eaten ? tr("Eaten", "Gegessen") : "")

            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(MealTag.allCases) { tag in
                    tagPill(tag, on: entry.tags.contains(tag)) {
                        balance.toggle(tag, for: meal)
                    }
                }
            }
        }
    }

    private func tagPill(_ tag: MealTag, on: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Label(tag.title, systemImage: tag.symbol)
                .scaledFont(size: 13, weight: .semibold, design: .rounded)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .foregroundStyle(on ? Color.white : Zen.ink)
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(on ? AnyShapeStyle(Zen.matcha) : AnyShapeStyle(Zen.sand),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

// MARK: - Tip

struct NutritionTipCard: View {
    let now: Date
    @State private var offset = 0

    var body: some View {
        let tips: [NutritionTip] = NutritionTip.all
        let tip: NutritionTip = tips[NutritionTip.index(for: now, offset: offset, count: tips.count)]
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                IconBadge(systemName: tip.symbol, tint: Zen.matcha, size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(offset == 0 ? tr("Tip of the day", "Tipp des Tages") : tr("Another tip", "Noch ein Tipp"))
                        .scaledFont(size: 12, weight: .semibold)
                        .foregroundStyle(Zen.inkSoft)
                    Text(tip.title)
                        .displayFont(18)
                        .foregroundStyle(Zen.ink)
                    Text(tip.text)
                        .scaledFont(size: 15)
                        .foregroundStyle(Zen.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .id(tip.title)
            .transition(.opacity)
            Button {
                Haptics.tap()
                withAnimation(.easeInOut(duration: 0.3)) { offset += 1 }
            } label: {
                Label(tr("Next tip", "Nächster Tipp"), systemImage: "arrow.triangle.2.circlepath")
                    .scaledFont(size: 14, weight: .semibold)
                    .foregroundStyle(Zen.shu)
            }
            .buttonStyle(.plain)
        }
        .zenCard(padding: 20)
    }
}

// MARK: - Week

struct FoodWeekCard: View {
    @Environment(BalanceStore.self) private var balance
    let now: Date

    var body: some View {
        let week: [BalanceStore.WeekDay] = balance.week(asOf: now)
        let waterDays: Int = week.filter(\.water).count
        let veggieDays: Int = week.filter(\.vegetables).count
        let streak: Int = balance.waterStreak
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(tr("This week", "Diese Woche"))
                    .displayFont(18)
                    .foregroundStyle(Zen.ink)
                Spacer()
                if streak > 1 {
                    Label(tr("\(streak) days of water", "\(streak) Tage Wasser"), systemImage: "flame.fill")
                        .scaledFont(size: 13, weight: .semibold)
                        .foregroundStyle(Zen.kin)
                }
            }
            HStack(spacing: 0) {
                ForEach(week) { day in
                    column(day, isToday: day.key == balance.key(for: now))
                        .frame(maxWidth: .infinity)
                }
            }
            .dynamicTypeSize(...denseTypeLimit)
            HStack(spacing: 16) {
                legend(icon: "drop.fill", tint: Zen.ai,
                       text: tr("Water goal: \(waterDays) of 7", "Wasserziel: \(waterDays) von 7"))
                legend(icon: "carrot.fill", tint: Zen.matcha,
                       text: tr("Vegetables: \(veggieDays) of 7", "Gemüse: \(veggieDays) von 7"))
            }
        }
        .zenCard(padding: 20)
    }

    private func column(_ day: BalanceStore.WeekDay, isToday: Bool) -> some View {
        let letter: String = day.date.formatted(.dateTime.weekday(.narrow).locale(Loc.locale))
        return VStack(spacing: 10) {
            Text(letter)
                .scaledFont(size: 13, weight: isToday ? .bold : .semibold, design: .rounded)
                .foregroundStyle(isToday ? Zen.shu : Zen.inkSoft)
            Image(systemName: day.water ? "drop.fill" : "drop")
                .scaledFont(size: 17, weight: .semibold)
                .foregroundStyle(day.water ? Zen.ai : Zen.inkFaint)
            Image(systemName: "carrot.fill")
                .scaledFont(size: 17, weight: .semibold)
                .foregroundStyle(day.vegetables ? Zen.matcha : Zen.inkFaint.opacity(0.5))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.date.formatted(.dateTime.weekday(.wide).locale(Loc.locale)))
        .accessibilityValue(accessibilityValue(day))
    }

    private func accessibilityValue(_ day: BalanceStore.WeekDay) -> String {
        let water: String = day.water ? tr("water goal reached", "Wasserziel erreicht") : tr("water goal open", "Wasserziel offen")
        let veg: String = day.vegetables ? tr("vegetables", "Gemüse") : tr("no vegetables logged", "kein Gemüse eingetragen")
        return water + ", " + veg
    }

    private func legend(icon: String, tint: Color, text: String) -> some View {
        Label {
            Text(text)
                .foregroundStyle(Zen.inkSoft)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(tint)
        }
        .scaledFont(size: 13, weight: .medium)
    }
}
