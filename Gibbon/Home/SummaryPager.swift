import SwiftUI
import SwiftData

struct SummaryPager: View {
    let stats: DayStats
    let profile: Profile
    let latestWeightKg: Double
    @State private var page = 0

    var body: some View {
        VStack(spacing: 10) {
            TabView(selection: $page) {
                MacrosPage(stats: stats).tag(0).padding(.horizontal, 2)
                MicrosPage(stats: stats).tag(1).padding(.horizontal, 2)
                ActivityPage(stats: stats, profile: profile, latestWeightKg: latestWeightKg).tag(2).padding(.horizontal, 2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 316)

            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(i == page ? Theme.ink : Theme.track)
                        .frame(width: 7, height: 7)
                }
            }
            .frame(maxWidth: .infinity)
            .animation(.snappy, value: page)
        }
    }
}

// MARK: - Page 1: calories + macros

private struct MacrosPage: View {
    let stats: DayStats
    @AppStorage("home.showEaten") private var showEaten = false

    var body: some View {
        VStack(spacing: 12) {
            calorieCard
            HStack(spacing: 10) {
                ForEach(NutrientKind.macros) { k in
                    NutrientRingCard(kind: k, stats: stats, showEaten: showEaten)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var calorieCard: some View {
        let left = stats.left(.calories)
        return Button {
            Haptics.tap()
            withAnimation(.snappy) { showEaten.toggle() }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    if showEaten {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text("\(stats.eaten.calories.int)")
                                .font(.system(size: 46, weight: .bold, design: .rounded))
                            Text("/\(stats.goals.calories.int)")
                                .font(.title3.weight(.medium)).foregroundStyle(.secondary)
                        }
                    } else {
                        Text("\(abs(left).int)")
                            .font(.system(size: 46, weight: .bold, design: .rounded))
                    }
                    HStack(spacing: 8) {
                        Text(showEaten ? "Calories eaten" : (left >= 0 ? "Calories left" : "Calories over"))
                            .font(.subheadline)
                            .foregroundStyle(left < 0 && !showEaten ? Theme.bad : .secondary)
                        Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
                        if stats.bonus > 0 {
                            Label("+\(stats.bonus.int)", systemImage: stats.rollover > 0 ? "arrow.uturn.backward" : "flame")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                        }
                    }
                }
                .contentTransition(.numericText())
                Spacer()
                RingView(progress: stats.progress(.calories),
                         color: left < 0 ? Theme.bad : Theme.ink, lineWidth: 10) {
                    Image(systemName: "flame.fill").font(.system(size: 22)).foregroundStyle(Theme.ink)
                }
                .frame(width: 104, height: 104)
            }
            .foregroundStyle(Theme.ink)
            .card(padding: 20)
        }
        .buttonStyle(PressableStyle())
    }
}

struct NutrientRingCard: View {
    let kind: NutrientKind
    let stats: DayStats
    var showEaten = false

    var body: some View {
        let left = stats.left(kind)
        VStack(alignment: .leading, spacing: 2) {
            if showEaten {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("\(stats.eaten[kind].int)").font(.system(size: 18, weight: .bold, design: .rounded))
                    Text("/\(stats.goals[kind].int)\(kind.shortUnit)").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text(kind.format(abs(left))).font(.system(size: 18, weight: .bold, design: .rounded))
            }
            Text("\(kind.title) \(showEaten ? "eaten" : (left >= 0 ? "left" : "over"))")
                .font(.caption)
                .foregroundStyle(left < 0 && !showEaten && !kind.isLimit ? Theme.ink : (left < 0 && kind.isLimit ? Theme.bad : .secondary))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            RingView(progress: stats.progress(kind), color: kind.color, lineWidth: 7) {
                NutrientIcon(kind: kind, size: 15)
            }
            .frame(width: 66, height: 66)
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentTransition(.numericText())
        .card(padding: 12)
    }
}

// MARK: - Page 2: fiber, sugar, sodium + health score

private struct MicrosPage: View {
    let stats: DayStats
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                ForEach(NutrientKind.micros) { k in
                    NutrientRingCard(kind: k, stats: stats)
                }
            }
            HealthScoreCard(score: stats.healthScore)
        }
        .padding(.vertical, 4)
    }
}

struct HealthScoreCard: View {
    let score: Double?
    var notes: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "heart.text.square.fill").foregroundStyle(Theme.bad)
                Text("Health Score").font(.headline)
                Spacer()
                Text(score.map { "\(Int($0.rounded()))/10" } ?? "N/A").font(.headline)
            }
            ProgressBar(value: (score ?? 0) / 10, color: color, height: 7)
            Text(notes ?? (score == nil
                 ? "Track a few foods to generate your health score for today. Your score reflects nutritional content and how processed your meals are."
                 : summary))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }

    private var color: Color {
        guard let s = score else { return Theme.track }
        if s >= 7 { return Theme.good }
        if s >= 4 { return Theme.warn }
        return Theme.bad
    }

    private var summary: String {
        guard let s = score else { return "" }
        if s >= 8 { return "Excellent — mostly whole, nutrient-dense foods today." }
        if s >= 6 { return "Good balance. A little more fiber or fewer processed foods would push this higher." }
        if s >= 4 { return "Fair. Try swapping some processed items for whole foods, vegetables and lean protein." }
        return "Today leans heavily on processed food, added sugar or sodium."
    }
}

// MARK: - Page 3: exercise, weight, water

private struct ActivityPage: View {
    @EnvironmentObject private var app: AppState
    let stats: DayStats
    let profile: Profile
    let latestWeightKg: Double

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                burnedCard
                weightCard
            }
            WaterCard(ml: stats.waterMl, goalMl: profile.waterGoalMl, units: profile.units)
        }
        .padding(.vertical, 4)
    }

    private var burnedCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Calories burned").font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(stats.burned.int)").font(.system(size: 26, weight: .bold, design: .rounded))
                Text("cal").font(.caption).foregroundStyle(.secondary)
            }
            if stats.exercises.isEmpty {
                Text("No workouts yet").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(stats.exercises.prefix(2)) { e in
                    HStack(spacing: 6) {
                        Image(systemName: e.kind.icon).font(.caption)
                        Text(e.name).font(.caption).lineLimit(1)
                        Spacer(minLength: 2)
                        Text("\(e.calories.int)").font(.caption.weight(.semibold))
                    }
                }
            }
            Spacer(minLength: 0)
            Button("Log exercise") { app.present(.exercise) }
                .buttonStyle(PillButtonStyle(filled: true))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .card(padding: 14)
    }

    private var weightCard: some View {
        let diff = latestWeightKg - profile.startWeightKg
        return VStack(alignment: .leading, spacing: 8) {
            Text("Current weight").font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(Fmt.number(Fmt.weightValue(latestWeightKg, profile.units), decimals: 1))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text(profile.units.weightUnit).font(.caption).foregroundStyle(.secondary)
            }
            Text("\(Fmt.signed(Fmt.weightValue(diff, profile.units))) \(profile.units.weightUnit) since start")
                .font(.caption).foregroundStyle(.secondary)
            Text("Goal: \(Fmt.weight(profile.goalWeightKg, profile.units))")
                .font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button("Log weight") { app.present(.weight) }
                .buttonStyle(PillButtonStyle(filled: true))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .card(padding: 14)
    }
}

struct WaterCard: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.modelContext) private var context
    let ml: Double
    let goalMl: Double
    let units: UnitSystem

    var body: some View {
        HStack(spacing: 12) {
            RingView(progress: goalMl > 0 ? ml / goalMl : 0, color: Theme.water, lineWidth: 5) {
                Image(systemName: "drop.fill").font(.system(size: 14)).foregroundStyle(Theme.water)
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("Water").font(.caption).foregroundStyle(.secondary)
                Text(Fmt.water(ml, units)).font(.headline)
            }
            Spacer()
            Button {
                Haptics.tap()
                context.insert(WaterEntry(date: app.logTimestamp, ml: units == .imperial ? 8 * Fmt.mlPerOz : 250))
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 32, height: 32)
                    .background(Theme.cardMuted, in: Circle())
            }
            .foregroundStyle(Theme.ink)
            .accessibilityLabel("Add one glass")
            Button("Log Water") { app.present(.water) }
                .buttonStyle(PillButtonStyle())
        }
        .card(padding: 14)
    }
}
