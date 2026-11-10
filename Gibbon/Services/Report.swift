import SwiftUI

enum Report {
    @MainActor
    static func makePDF(profile: Profile, foods: [FoodEntry], weights: [WeightEntry], exercises: [ExerciseEntry]) -> URL? {
        let view = ReportView(profile: profile, foods: foods, weights: weights, exercises: exercises)
            .frame(width: 612)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: view)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Gibbon Summary \(Date.now.formatted(.iso8601.year().month().day())).pdf")
        var ok = false
        renderer.render { size, draw in
            var box = CGRect(origin: .zero, size: size)
            guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            pdf.beginPDFPage(nil)
            draw(pdf)
            pdf.endPDFPage()
            pdf.closePDF()
            ok = true
        }
        return ok ? url : nil
    }

    static func makeCSV(foods: [FoodEntry]) -> URL? {
        var rows = ["date,time,meal,name,servings,calories,protein_g,carbs_g,fat_g,fiber_g,sugar_g,sodium_mg,health_score,ingredients"]
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let tf = DateFormatter()
        tf.dateFormat = "HH:mm"
        func q(_ s: String) -> String { "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\"" }
        for f in foods {
            let t = f.totals
            let ings = f.sortedIngredients.map { "\($0.name) \($0.grams.int)g" }.joined(separator: "; ")
            rows.append([df.string(from: f.date), tf.string(from: f.date), f.meal.title, q(f.name),
                         Fmt.number(f.servings, decimals: 2), "\(t.calories.int)", Fmt.number(t.protein),
                         Fmt.number(t.carbs), Fmt.number(t.fat), Fmt.number(t.fiber), Fmt.number(t.sugar),
                         "\(t.sodium.int)", f.healthScore.map(String.init) ?? "", q(ings)].joined(separator: ","))
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Gibbon meals.csv")
        do {
            try rows.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}

private struct ReportView: View {
    let profile: Profile
    let foods: [FoodEntry]
    let weights: [WeightEntry]
    let exercises: [ExerciseEntry]

    var body: some View {
        let byDay = Stats.nutrientsByDay(foods)
        let last7 = Calendar.current.days(back: 7)
        let last30 = Calendar.current.days(back: 30)
        let logged7 = last7.compactMap { byDay[$0] }
        let logged30 = last30.compactMap { byDay[$0] }
        let avg7 = average(logged7)
        let avg30 = average(logged30)
        let current = Stats.latestWeight(weights, profile: profile)

        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("White Cheeked Gibbon summary").font(.system(size: 26, weight: .bold))
                    Text("\(profile.name.isEmpty ? "" : profile.name + " · ")Generated \(Fmt.longDate(.now))").foregroundStyle(.secondary)
                }
                Spacer()
                Image("Gibbon").resizable().scaledToFit().frame(width: 56, height: 56)
            }

            section("Goals") {
                grid([
                    ("Calories", "\(profile.calorieGoal.int)"),
                    ("Protein", "\(profile.proteinGoal.int) g"),
                    ("Carbs", "\(profile.carbsGoal.int) g"),
                    ("Fat", "\(profile.fatGoal.int) g"),
                    ("Goal", profile.goal.title),
                    ("Goal weight", Fmt.weight(profile.goalWeightKg, profile.units)),
                ])
            }

            section("Weight") {
                grid([
                    ("Start", Fmt.weight(profile.startWeightKg, profile.units)),
                    ("Current", Fmt.weight(current, profile.units)),
                    ("Change", "\(Fmt.signed(Fmt.weightValue(current - profile.startWeightKg, profile.units))) \(profile.units.weightUnit)"),
                    ("BMI", Fmt.number(Planner.bmi(kg: current, cm: profile.heightCm))),
                    ("Weigh-ins", "\(weights.count)"),
                    ("Height", Fmt.height(profile.heightCm, profile.units)),
                ])
            }

            section("Nutrition averages (days logged)") {
                VStack(alignment: .leading, spacing: 6) {
                    row("Last 7 days (\(logged7.count) logged)", avg7)
                    row("Last 30 days (\(logged30.count) logged)", avg30)
                }
            }

            section("Habits") {
                grid([
                    ("Current streak", "\(Stats.streak(foods)) days"),
                    ("Longest streak", "\(Stats.longestStreak(foods)) days"),
                    ("Meals logged", "\(foods.count)"),
                    ("Workouts", "\(exercises.count)"),
                    ("Burned (30 d)", "\(exercises.filter { $0.date >= (last30.first ?? .now) }.reduce(0) { $0 + $1.calories }.int) cal"),
                    ("Days on target (30 d)", "\(logged30.filter { RingStatus.forDay(eaten: $0.calories, goal: profile.calorieGoal) == .onTrack }.count)"),
                ])
            }

            section("Last 7 days") {
                VStack(spacing: 4) {
                    ForEach(last7, id: \.self) { d in
                        let n = byDay[d] ?? .zero
                        HStack {
                            Text(d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())).frame(width: 110, alignment: .leading)
                            Text("\(n.calories.int) cal").frame(width: 80, alignment: .trailing)
                            Text("P \(n.protein.int)g · C \(n.carbs.int)g · F \(n.fat.int)g").foregroundStyle(.secondary)
                            Spacer()
                        }
                        .font(.system(size: 12))
                    }
                }
            }
        }
        .padding(36)
        .background(.white)
        .foregroundStyle(.black)
    }

    private func average(_ days: [Nutrients]) -> Nutrients {
        guard !days.isEmpty else { return .zero }
        return days.reduce(.zero, +).scaled(1 / Double(days.count))
    }

    private func row(_ title: String, _ n: Nutrients) -> some View {
        HStack {
            Text(title).frame(width: 200, alignment: .leading)
            Text("\(n.calories.int) cal · P \(n.protein.int)g · C \(n.carbs.int)g · F \(n.fat.int)g · Fiber \(n.fiber.int)g")
        }
        .font(.system(size: 12))
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 15, weight: .semibold))
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(white: 0.96), in: RoundedRectangle(cornerRadius: 12))
    }

    private func grid(_ items: [(String, String)]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3), alignment: .leading, spacing: 8) {
            ForEach(items, id: \.0) { item in
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.0).font(.system(size: 10)).foregroundStyle(.secondary)
                    Text(item.1).font(.system(size: 13, weight: .semibold))
                }
            }
        }
    }
}
