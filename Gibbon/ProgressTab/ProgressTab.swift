import SwiftUI
import SwiftData
import Charts
import PhotosUI

struct ProgressTab: View {
    @Bindable var profile: Profile
    @EnvironmentObject private var app: AppState
    @Query(sort: \FoodEntry.date, order: .reverse) private var allFoods: [FoodEntry]
    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]
    @Query(sort: \ExerciseEntry.date, order: .reverse) private var exercises: [ExerciseEntry]
    @Query(sort: \WaterEntry.date, order: .reverse) private var waters: [WaterEntry]

    private var foods: [FoodEntry] { allFoods.filter { !$0.isTemplate } }

    var body: some View {
        let current = Stats.latestWeight(weights, profile: profile)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Progress").font(.system(size: 32, weight: .bold)).padding(.top, 8)

                HStack(spacing: 12) {
                    streakCard
                    badgesCard
                }

                CurrentWeightCard(profile: profile, current: current)
                WeightChartCard(profile: profile, weights: weights, current: current)
                WeightChangesCard(profile: profile, weights: weights)
                ProgressPhotosCard(profile: profile)
                DailyCaloriesCard(profile: profile, foods: foods)
                WeeklyEnergyCard(foods: foods, exercises: exercises)
                ExpenditureChangesCard(exercises: exercises)
                BMICard(profile: profile, weightKg: current)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
    }

    private var streakCard: some View {
        let streak = Stats.streak(foods)
        return Button { app.present(.streak) } label: {
            VStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(LinearGradient(colors: [Theme.warn, Theme.burn], startPoint: .top, endPoint: .bottom))
                Text("\(streak)").font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(Theme.ink)
                Text("Day Streak").font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .card()
        }
        .buttonStyle(PressableStyle())
    }

    private var badgesCard: some View {
        let earned = Badges.all(foods: foods, waters: waters, weights: weights, exercises: exercises, profile: profile).filter(\.earned).count
        return Button { app.present(.badges) } label: {
            VStack(spacing: 6) {
                Image(systemName: "medal.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(LinearGradient(colors: [Theme.warn, Theme.carbs], startPoint: .top, endPoint: .bottom))
                Text("\(earned)").font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(Theme.ink)
                Text("Badges Earned").font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .card()
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - Weight

private struct CurrentWeightCard: View {
    @EnvironmentObject private var app: AppState
    let profile: Profile
    let current: Double

    var body: some View {
        let start = profile.startWeightKg
        let goal = profile.goalWeightKg
        let total = abs(start - goal)
        let done = total > 0.05 ? min(1, max(0, (goal < start ? start - current : current - start) / total)) : 1
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Current Weight").font(.subheadline).foregroundStyle(.secondary)
                    Text(Fmt.weight(current, profile.units)).font(.system(size: 28, weight: .bold, design: .rounded))
                }
                Spacer()
                Button { app.present(.weight) } label: {
                    Label("Log weight", systemImage: "arrow.right").labelStyle(TrailingIconLabelStyle())
                }
                .buttonStyle(PillButtonStyle(filled: true))
            }
            ProgressBar(value: done, color: Theme.ink, height: 6)
            HStack {
                Text("Start: ").foregroundStyle(.secondary) + Text(Fmt.weight(start, profile.units)).bold()
                Spacer()
                Text("Goal: ").foregroundStyle(.secondary) + Text(Fmt.weight(goal, profile.units)).bold()
            }
            .font(.caption)
            if profile.goal != .maintain,
               let date = Planner.goalDate(current: current, goal: goal, weeklyRateKg: profile.weeklyRateKg) {
                (Text("At your goal by ").foregroundStyle(.secondary) + Text(Fmt.longDate(date)).bold())
                    .font(.caption)
            } else if profile.goal != .maintain {
                Text("You've reached your goal weight! 🎉").font(.caption.weight(.semibold))
            }
        }
        .card()
    }
}

struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) { configuration.title; configuration.icon }
    }
}

private enum WeightRange: String, CaseIterable, Identifiable {
    case d90 = "90D", m6 = "6M", y1 = "1Y", all = "ALL"
    var id: String { rawValue }
    var days: Int? {
        switch self {
        case .d90: 90
        case .m6: 182
        case .y1: 365
        case .all: nil
        }
    }
}

private struct WeightChartCard: View {
    let profile: Profile
    let weights: [WeightEntry]
    let current: Double
    @State private var range: WeightRange = .all

    var body: some View {
        let cutoff = range.days.flatMap { Calendar.current.date(byAdding: .day, value: -$0, to: .now) }
        let points = weights.filter { cutoff == nil || $0.date >= cutoff! }
        let values = points.map { Fmt.weightValue($0.kg, profile.units) }
        let goalV = Fmt.weightValue(profile.goalWeightKg, profile.units)
        let lo = (values + [goalV]).min() ?? 0
        let hi = (values + [goalV]).max() ?? 1
        let pad = max(2, (hi - lo) * 0.15)
        let total = abs(profile.startWeightKg - profile.goalWeightKg)
        let pct = total > 0.05 ? min(1, max(0, abs(current - profile.startWeightKg) / total)) : 0

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Weight Progress").font(.headline)
                Spacer()
                Label("\(Int((pct * 100).rounded()))% of goal", systemImage: "flag")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Theme.cardMuted, in: Capsule())
            }
            if points.isEmpty {
                EmptyStateView(icon: "scalemass", title: "No weigh-ins yet", message: "Log your weight to see your trend.")
            } else {
                Chart {
                    ForEach(points) { w in
                        LineMark(x: .value("Date", w.date), y: .value("Weight", Fmt.weightValue(w.kg, profile.units)))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(Theme.ink)
                        PointMark(x: .value("Date", w.date), y: .value("Weight", Fmt.weightValue(w.kg, profile.units)))
                            .foregroundStyle(Theme.ink)
                            .symbolSize(points.count > 30 ? 0 : 30)
                    }
                    if profile.goal != .maintain {
                        RuleMark(y: .value("Goal", goalV))
                            .foregroundStyle(Theme.good)
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                            .annotation(position: .top, alignment: .leading) {
                                Text("Goal").font(.caption2).foregroundStyle(Theme.good)
                            }
                    }
                }
                .chartYScale(domain: (lo - pad)...(hi + pad))
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated).day()) } }
                .frame(height: 200)
            }
            Picker("Range", selection: $range) {
                ForEach(WeightRange.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        }
        .card()
    }
}

private struct WeightChangesCard: View {
    let profile: Profile
    let weights: [WeightEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Weight Changes").font(.headline)
            ForEach([3, 7, 14, 30, 90, 0], id: \.self) { days in
                let change = changeOver(days)
                HStack {
                    Text(days == 0 ? "All Time" : "\(days) day").font(.subheadline).foregroundStyle(.secondary)
                        .frame(width: 70, alignment: .leading)
                    ProgressBar(value: min(1, abs(change ?? 0) / 5), color: (change ?? 0) < 0 ? Theme.good : Theme.fat, height: 8)
                        .frame(width: 50)
                    Spacer()
                    Text(change.map { "\(Fmt.number(abs($0), decimals: 1)) \(profile.units.weightUnit)" } ?? "–")
                        .font(.subheadline.weight(.medium))
                        .frame(width: 80, alignment: .trailing)
                    HStack(spacing: 4) {
                        Image(systemName: icon(change))
                        Text(label(change))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 92, alignment: .leading)
                }
            }
        }
        .card()
    }

    /// Latest weight minus the weight at the start of the window, in display units.
    private func changeOver(_ days: Int) -> Double? {
        guard let latest = weights.last else { return nil }
        let baseline: WeightEntry?
        if days == 0 {
            baseline = weights.first
        } else {
            let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .now
            baseline = weights.last(where: { $0.date <= cutoff }) ?? weights.first(where: { $0.date >= cutoff })
        }
        guard let baseline else { return nil }
        return Fmt.weightValue(latest.kg - baseline.kg, profile.units)
    }
    private func icon(_ c: Double?) -> String {
        guard let c, abs(c) >= 0.05 else { return "arrow.right" }
        return c > 0 ? "arrow.up.right" : "arrow.down.right"
    }
    private func label(_ c: Double?) -> String {
        guard let c, abs(c) >= 0.05 else { return "No change" }
        return c > 0 ? "Increase" : "Decrease"
    }
}

// MARK: - Photos

private struct ProgressPhotosCard: View {
    @Environment(\.modelContext) private var context
    let profile: Profile
    @Query(sort: \ProgressPhoto.date, order: .reverse) private var photos: [ProgressPhoto]
    @State private var item: PhotosPickerItem?
    @State private var viewing: ProgressPhoto?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Progress Photos").font(.headline)
                Spacer()
                if !photos.isEmpty {
                    PhotosPicker(selection: $item, matching: .images) {
                        Label("Add", systemImage: "plus")
                    }
                    .buttonStyle(PillButtonStyle())
                }
            }
            if photos.isEmpty {
                HStack(spacing: 14) {
                    Image(systemName: "figure.stand")
                        .font(.system(size: 34))
                        .frame(width: 70, height: 80)
                        .background(Theme.cardMuted, in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Want to add a photo to track your progress?").font(.subheadline).foregroundStyle(.secondary)
                        PhotosPicker(selection: $item, matching: .images) {
                            Label("Upload a Photo", systemImage: "plus")
                        }
                        .buttonStyle(PillButtonStyle())
                    }
                }
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(photos) { p in
                            Button { viewing = p } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    if let d = p.imageData, let img = UIImage(data: d) {
                                        Image(uiImage: img).resizable().scaledToFill()
                                            .frame(width: 100, height: 130)
                                            .clipShape(RoundedRectangle(cornerRadius: 14))
                                    }
                                    Text(Fmt.shortDate(p.date)).font(.caption2.weight(.semibold)).foregroundStyle(Theme.ink)
                                    if let kg = p.weightKg {
                                        Text(Fmt.weight(kg, profile.units)).font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .card()
        .onChange(of: item) { _, newItem in
            guard let newItem else { return }
            Task {
                if let d = try? await newItem.loadTransferable(type: Data.self), let img = UIImage(data: d) {
                    context.insert(ProgressPhoto(date: .now, imageData: img.jpegForStorage(), weightKg: profile.currentWeightKg))
                }
                item = nil
            }
        }
        .fullScreenCover(item: $viewing) { p in
            PhotoViewer(photo: p, units: profile.units)
        }
    }
}

private struct PhotoViewer: View {
    let photo: ProgressPhoto
    let units: UnitSystem
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let d = photo.imageData, let img = UIImage(data: d) {
                Image(uiImage: img).resizable().scaledToFit()
            }
            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.headline).foregroundStyle(.white)
                            .frame(width: 40, height: 40).background(.white.opacity(0.2), in: Circle())
                    }
                    Spacer()
                    Button(role: .destructive) {
                        context.delete(photo)
                        dismiss()
                    } label: {
                        Image(systemName: "trash").font(.headline).foregroundStyle(.white)
                            .frame(width: 40, height: 40).background(.white.opacity(0.2), in: Circle())
                    }
                }
                Spacer()
                VStack(spacing: 2) {
                    Text(Fmt.longDate(photo.date)).font(.headline)
                    if let kg = photo.weightKg { Text(Fmt.weight(kg, units)).font(.subheadline) }
                }
                .foregroundStyle(.white)
            }
            .padding(20)
        }
    }
}

// MARK: - Calories & energy

private struct WeekPicker: View {
    @Binding var offset: Int
    var body: some View {
        Picker("Week", selection: $offset) {
            Text("This wk").tag(0)
            Text("Last wk").tag(-1)
            Text("2 wk ago").tag(-2)
            Text("3 wk ago").tag(-3)
        }
        .pickerStyle(.segmented)
    }
}

private struct DailyCaloriesCard: View {
    let profile: Profile
    let foods: [FoodEntry]
    @State private var offset = 0

    private struct Bar: Identifiable {
        let id = UUID()
        let day: Date
        let macro: String
        let kcal: Double
    }

    var body: some View {
        let byDay = Stats.nutrientsByDay(foods)
        let days = Stats.weekDays(offset: offset)
        let bars = days.flatMap { d -> [Bar] in
            let n = byDay[d] ?? .zero
            return [Bar(day: d, macro: "Protein", kcal: n.protein * 4),
                    Bar(day: d, macro: "Carbs", kcal: n.carbs * 4),
                    Bar(day: d, macro: "Fat", kcal: n.fat * 9)]
        }
        let logged = days.compactMap { byDay[$0] }.filter { $0.calories > 0 }
        let avg = logged.isEmpty ? 0 : logged.reduce(0) { $0 + $1.calories } / Double(logged.count)

        VStack(alignment: .leading, spacing: 14) {
            Text("Daily Average Calories").font(.headline)
            if logged.isEmpty {
                EmptyStateView()
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(avg.int)").font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("cal / day").font(.subheadline).foregroundStyle(.secondary)
                }
                Chart {
                    ForEach(bars) { b in
                        BarMark(x: .value("Day", b.day, unit: .day), y: .value("Calories", b.kcal))
                            .foregroundStyle(by: .value("Macro", b.macro))
                            .cornerRadius(4)
                    }
                    RuleMark(y: .value("Goal", profile.calorieGoal))
                        .foregroundStyle(Color.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
                .chartForegroundStyleScale(["Protein": Theme.protein, "Carbs": Theme.carbs, "Fat": Theme.fat])
                .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)) } }
                .frame(height: 180)
            }
            WeekPicker(offset: $offset)
        }
        .card()
    }
}

private struct WeeklyEnergyCard: View {
    let foods: [FoodEntry]
    let exercises: [ExerciseEntry]
    @State private var offset = 0

    private struct Bar: Identifiable {
        let id = UUID()
        let day: Date
        let kind: String
        let kcal: Double
    }

    var body: some View {
        let eaten = Stats.caloriesByDay(foods)
        let burned = Stats.burnedByDay(exercises)
        let days = Stats.weekDays(offset: offset)
        let bars = days.flatMap { d in
            [Bar(day: d, kind: "Consumed", kcal: eaten[d] ?? 0), Bar(day: d, kind: "Burned", kcal: burned[d] ?? 0)]
        }
        let totalIn = days.reduce(0) { $0 + (eaten[$1] ?? 0) }
        let totalOut = days.reduce(0) { $0 + (burned[$1] ?? 0) }

        VStack(alignment: .leading, spacing: 14) {
            Text("Weekly Energy").font(.headline)
            if totalIn == 0 && totalOut == 0 {
                EmptyStateView()
            } else {
                HStack(spacing: 18) {
                    stat("Burned", totalOut, Theme.burn)
                    stat("Consumed", totalIn, Theme.ink)
                    stat("Energy", totalIn - totalOut, totalIn - totalOut > 0 ? Theme.good : Theme.bad, signed: true)
                }
                Chart(bars) { b in
                    BarMark(x: .value("Day", b.day, unit: .day), y: .value("Calories", b.kcal))
                        .foregroundStyle(by: .value("Type", b.kind))
                        .position(by: .value("Type", b.kind))
                        .cornerRadius(3)
                }
                .chartForegroundStyleScale(["Consumed": Theme.ink, "Burned": Theme.burn])
                .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)) } }
                .frame(height: 170)
            }
            WeekPicker(offset: $offset)
        }
        .card()
    }

    private func stat(_ title: String, _ v: Double, _ color: Color, signed: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(signed ? "\(v >= 0 ? "+" : "−")\(abs(v).int)" : "\(v.int)")
                .font(.headline).foregroundStyle(color)
        }
    }
}

private struct ExpenditureChangesCard: View {
    let exercises: [ExerciseEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Expenditure Changes").font(.headline)
            ForEach([3, 7, 14, 30, 90], id: \.self) { days in
                let (now, prev) = totals(days)
                let change = now - prev
                HStack {
                    Text("\(days) day").font(.subheadline).foregroundStyle(.secondary).frame(width: 60, alignment: .leading)
                    ProgressBar(value: min(1, now / max(1, Double(days) * 500)), color: Theme.burn, height: 8).frame(width: 50)
                    Spacer()
                    Text("\(now.int) cal").font(.subheadline.weight(.medium)).frame(width: 80, alignment: .trailing)
                    HStack(spacing: 4) {
                        Image(systemName: abs(change) < 1 ? "arrow.right" : (change > 0 ? "arrow.up.right" : "arrow.down.right"))
                        Text(abs(change) < 1 ? "No change" : "\(change > 0 ? "+" : "−")\(abs(change).int)")
                    }
                    .font(.caption).foregroundStyle(.secondary).frame(width: 92, alignment: .leading)
                }
            }
            Text("Calories burned from logged exercise, compared with the period before.")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .card()
    }

    private func totals(_ days: Int) -> (Double, Double) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        guard let start = cal.date(byAdding: .day, value: -(days - 1), to: today),
              let prevStart = cal.date(byAdding: .day, value: -days, to: start) else { return (0, 0) }
        let now = exercises.filter { $0.date >= start }.reduce(0) { $0 + $1.calories }
        let prev = exercises.filter { $0.date >= prevStart && $0.date < start }.reduce(0) { $0 + $1.calories }
        return (now, prev)
    }
}

// MARK: - BMI

private struct BMICard: View {
    let profile: Profile
    let weightKg: Double
    @State private var showInfo = false

    var body: some View {
        let bmi = Planner.bmi(kg: weightKg, cm: profile.heightCm)
        let (label, color) = category(bmi)
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Your BMI").font(.headline)
                Spacer()
                Button { showInfo = true } label: { Image(systemName: "questionmark.circle").foregroundStyle(.secondary) }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Fmt.number(bmi, decimals: 1)).font(.system(size: 30, weight: .bold, design: .rounded))
                Text("Your weight is").font(.subheadline).foregroundStyle(.secondary)
                Text(label).font(.caption.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(color.opacity(0.18), in: Capsule())
                    .foregroundStyle(color)
            }
            GeometryReader { geo in
                let segments: [(Color, Double)] = [(Theme.fat, 18.5 - 15), (Theme.good, 25 - 18.5), (Theme.warn, 30 - 25), (Theme.bad, 40 - 30)]
                let totalRange = 40.0 - 15
                ZStack(alignment: .leading) {
                    HStack(spacing: 3) {
                        ForEach(0..<segments.count, id: \.self) { i in
                            Capsule().fill(segments[i].0)
                                .frame(width: max(0, geo.size.width * segments[i].1 / totalRange - 3))
                        }
                    }
                    Capsule().fill(Theme.ink).frame(width: 3, height: 20)
                        .offset(x: geo.size.width * min(1, max(0, (bmi - 15) / totalRange)) - 1.5)
                }
                .frame(height: 20)
            }
            .frame(height: 20)
            HStack {
                legend("Underweight", "<18.5", Theme.fat)
                legend("Healthy", "18.5–24.9", Theme.good)
                legend("Overweight", "25–29.9", Theme.warn)
                legend("Obese", ">30", Theme.bad)
            }
        }
        .card()
        .sheet(isPresented: $showInfo) {
            VStack(alignment: .leading, spacing: 14) {
                SheetHeader(title: "About BMI") { showInfo = false }
                Text("Body Mass Index is your weight in kilograms divided by your height in meters squared. It's a quick screening number, not a diagnosis — it doesn't distinguish muscle from fat, so athletes often read as \"overweight\".")
                Text("Use it alongside your weight trend, how you feel, and measurements like waist size.")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 20)
            .presentationDetents([.medium])
        }
    }

    private func category(_ bmi: Double) -> (String, Color) {
        switch bmi {
        case ..<18.5: ("Underweight", Theme.fat)
        case ..<25: ("Healthy", Theme.good)
        case ..<30: ("Overweight", Theme.warn)
        default: ("Obese", Theme.bad)
        }
    }

    private func legend(_ title: String, _ range: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 3) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(title).font(.system(size: 10))
            }
            Text(range).font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
