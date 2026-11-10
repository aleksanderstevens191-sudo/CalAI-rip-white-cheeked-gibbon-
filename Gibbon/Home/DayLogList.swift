import SwiftUI
import SwiftData

private enum LogItem: Identifiable {
    case food(FoodEntry)
    case water(WaterEntry)
    case exercise(ExerciseEntry)

    var id: String {
        switch self {
        case .food(let f): "f\(f.uuid)"
        case .water(let w): "w\(w.uuid)"
        case .exercise(let e): "e\(e.uuid)"
        }
    }
    var date: Date {
        switch self {
        case .food(let f): f.date
        case .water(let w): w.date
        case .exercise(let e): e.date
        }
    }
}

struct DayLogList: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.modelContext) private var context
    let stats: DayStats
    let profile: Profile

    var body: some View {
        let items = (stats.foods.map(LogItem.food) + stats.waters.map(LogItem.water) + stats.exercises.map(LogItem.exercise))
            .sorted { $0.date > $1.date }
        VStack(alignment: .leading, spacing: 12) {
            Text(Calendar.current.isDateInToday(stats.day) ? "Recently uploaded" : Fmt.dayLabel(stats.day))
                .font(.title3.weight(.semibold))
                .padding(.top, 4)

            if stats.foods.contains(where: { $0.status == .ready }) {
                mealBreakdown
            }

            if items.isEmpty {
                emptyCard
            } else {
                ForEach(items) { item in
                    switch item {
                    case .food(let f): FoodRow(entry: f, units: profile.units)
                    case .water(let w): WaterRow(entry: w, units: profile.units)
                    case .exercise(let e): ExerciseRow(entry: e)
                    }
                }
            }
        }
    }

    private var mealBreakdown: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(MealType.allCases) { m in
                    let meals = stats.foods.filter { $0.meal == m && $0.status == .ready }
                    let kcal = meals.reduce(0) { $0 + $1.totals.calories }
                    HStack(spacing: 6) {
                        Image(systemName: m.icon).font(.caption)
                        Text(m.title).font(.caption.weight(.semibold))
                        Text(meals.isEmpty ? "–" : "\(kcal.int) cal").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Theme.card, in: Capsule())
                    .opacity(meals.isEmpty ? 0.6 : 1)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var emptyCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Image("Gibbon").resizable().scaledToFit().frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 6) {
                    Capsule().fill(Theme.cardMuted).frame(width: 120, height: 8)
                    Capsule().fill(Theme.cardMuted).frame(width: 80, height: 8)
                }
                Spacer()
            }
            .padding(14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 30)
            Text("Tap + to add your first meal of the day")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .background(Theme.cardMuted.opacity(0.6), in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }
}

// MARK: - Rows

struct FoodRow: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var analysis: AnalysisManager
    @Environment(\.modelContext) private var context
    let entry: FoodEntry
    let units: UnitSystem

    var body: some View {
        Button {
            if entry.status == .failed { retry() } else { app.present(.foodDetail(entry)) }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    FoodThumbnail(data: entry.imageData, source: entry.source, size: 88)
                    if entry.status == .analyzing {
                        Color.black.opacity(0.45).clipShape(RoundedRectangle(cornerRadius: 16))
                        RingView(progress: analysis.progress[entry.uuid] ?? 0.05, color: .white, lineWidth: 4) {
                            Text("\(Int(((analysis.progress[entry.uuid] ?? 0.05) * 100).rounded()))%")
                                .font(.caption.weight(.bold)).foregroundStyle(.white)
                        }
                        .frame(width: 48, height: 48)
                    }
                }
                .frame(width: 88, height: 88)

                VStack(alignment: .leading, spacing: 7) {
                    switch entry.status {
                    case .analyzing:
                        Text("Analyzing food…").font(.headline)
                        Text("Finding every ingredient").font(.caption).foregroundStyle(.secondary)
                        Capsule().fill(Theme.cardMuted).frame(width: 110, height: 7)
                        Capsule().fill(Theme.cardMuted).frame(width: 70, height: 7)
                    case .failed:
                        Text("Couldn't analyze").font(.headline)
                        Text(entry.errorMessage ?? "Something went wrong.")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        Label("Tap to retry", systemImage: "arrow.clockwise").font(.caption.weight(.semibold))
                    case .ready:
                        HStack(alignment: .top) {
                            Text(entry.name).font(.headline).lineLimit(2).multilineTextAlignment(.leading)
                            Spacer(minLength: 6)
                            Text(Fmt.time(entry.date))
                                .font(.caption2)
                                .padding(.horizontal, 7).padding(.vertical, 4)
                                .background(Theme.cardMuted, in: Capsule())
                        }
                        HStack(spacing: 4) {
                            Image(systemName: "flame.fill").font(.caption)
                            Text("\(entry.totals.calories.int) calories").font(.subheadline.weight(.semibold))
                            Text("· \(entry.meal.title)").font(.caption).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 12) {
                            ForEach(NutrientKind.macros) { k in
                                HStack(spacing: 3) {
                                    NutrientIcon(kind: k, size: 10)
                                    Text(k.format(entry.totals[k])).font(.caption)
                                }
                            }
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(Theme.ink)
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 10, y: 3)
        }
        .buttonStyle(PressableStyle())
        .contextMenu {
            if entry.status == .ready {
                Button { app.present(.foodDetail(entry)) } label: { Label("Edit", systemImage: "pencil") }
                Button {
                    entry.duplicate(into: context, date: app.logTimestamp, asTemplate: false)
                    app.showToast("Logged again")
                } label: { Label("Log again", systemImage: "plus.square.on.square") }
                Button {
                    entry.duplicate(into: context, date: .now, asTemplate: true)
                    app.showToast("Saved to Saved foods")
                } label: { Label("Save food", systemImage: "bookmark") }
            }
            if entry.status == .failed {
                Button { retry() } label: { Label("Retry", systemImage: "arrow.clockwise") }
            }
            Button(role: .destructive) {
                context.delete(entry)
            } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private func retry() {
        let kind: AnalysisManager.Kind
        switch entry.source {
        case .label: kind = .label
        case .text: kind = .text(entry.userHint)
        default: kind = .photo
        }
        analysis.run(entry, kind: kind, context: context)
    }
}

private struct WaterRow: View {
    @Environment(\.modelContext) private var context
    let entry: WaterEntry
    let units: UnitSystem
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "drop.fill")
                .font(.title3)
                .foregroundStyle(Theme.water)
                .frame(width: 52, height: 52)
                .background(Theme.water.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 3) {
                Text("Water").font(.subheadline.weight(.semibold))
                Text(units == .imperial ? "\(Int(Fmt.waterValue(entry.ml, units).rounded())) fl oz" : "\(Int(entry.ml.rounded())) ml")
                    .font(.headline)
            }
            Spacer()
            Text(Fmt.time(entry.date)).font(.caption).foregroundStyle(.secondary)
            Menu {
                Button(role: .destructive) { context.delete(entry) } label: { Label("Delete", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis").foregroundStyle(.secondary).frame(width: 30, height: 30)
            }
        }
        .card(padding: 12)
    }
}

private struct ExerciseRow: View {
    @Environment(\.modelContext) private var context
    let entry: ExerciseEntry
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: entry.kind.icon)
                .font(.title3)
                .foregroundStyle(Theme.burn)
                .frame(width: 52, height: 52)
                .background(Theme.burn.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name).font(.subheadline.weight(.semibold))
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill").font(.caption)
                    Text("\(entry.calories.int) cal burned").font(.headline)
                }
                if entry.minutes > 0 {
                    Text("\(Int(entry.minutes)) min\(entry.kind == .run || entry.kind == .weights ? " · \(entry.intensity.title) intensity" : "")")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(Fmt.time(entry.date)).font(.caption).foregroundStyle(.secondary)
            Menu {
                Button(role: .destructive) { context.delete(entry) } label: { Label("Delete", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis").foregroundStyle(.secondary).frame(width: 30, height: 30)
            }
        }
        .card(padding: 12)
    }
}
