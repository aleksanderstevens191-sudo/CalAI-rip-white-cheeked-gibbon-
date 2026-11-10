import Foundation

/// Turns body stats and goals into daily targets.
enum Planner {
    struct Plan: Equatable {
        var calories: Double
        var protein: Double
        var carbs: Double
        var fat: Double
        var fiber: Double
        var sugar: Double
        var sodium: Double
        var waterMl: Double
    }

    static let kcalPerKg: Double = 7700

    static func age(from birth: Date, at date: Date = .now) -> Int {
        Calendar.current.dateComponents([.year], from: birth, to: date).year ?? 30
    }

    /// Mifflin–St Jeor resting metabolic rate.
    static func bmr(sex: Sex, kg: Double, cm: Double, age: Int) -> Double {
        let base = 10 * kg + 6.25 * cm - 5 * Double(age)
        switch sex {
        case .male: return base + 5
        case .female: return base - 161
        case .other: return base - 78
        }
    }

    static func tdee(sex: Sex, kg: Double, cm: Double, age: Int, activity: ActivityLevel) -> Double {
        bmr(sex: sex, kg: kg, cm: cm, age: age) * activity.factor
    }

    static func makePlan(sex: Sex, birthDate: Date, heightCm: Double, weightKg: Double,
                         activity: ActivityLevel, goal: WeightGoal, weeklyRateKg: Double) -> Plan {
        let age = age(from: birthDate)
        let maintenance = tdee(sex: sex, kg: weightKg, cm: heightCm, age: age, activity: activity)
        let dailyDelta = weeklyRateKg * kcalPerKg / 7
        var calories: Double
        switch goal {
        case .lose: calories = maintenance - dailyDelta
        case .maintain: calories = maintenance
        case .gain: calories = maintenance + dailyDelta
        }
        let floor: Double = sex == .female ? 1200 : (sex == .male ? 1500 : 1350)
        calories = max(floor, calories)
        calories = (calories / 10).rounded() * 10

        // Protein: ~2 g/kg while cutting or bulking, 1.6 g/kg to maintain, kept between 20–35% of calories.
        let perKg = goal == .maintain ? 1.6 : 2.0
        var protein = weightKg * perKg
        protein = min(max(protein, calories * 0.20 / 4), calories * 0.35 / 4)
        let fat = calories * 0.27 / 9
        let carbs = max(0, (calories - protein * 4 - fat * 9) / 4)
        let fiber = calories / 1000 * 14
        let sugar = calories * 0.15 / 4
        let waterOz = min(128, max(64, weightKg * 2.20462 * 0.5))

        return Plan(calories: calories,
                    protein: protein.rounded(),
                    carbs: carbs.rounded(),
                    fat: fat.rounded(),
                    fiber: fiber.rounded(),
                    sugar: sugar.rounded(),
                    sodium: 2300,
                    waterMl: (waterOz * 29.5735 / 10).rounded() * 10)
    }

    static func makePlan(for p: Profile) -> Plan {
        makePlan(sex: p.sex, birthDate: p.birthDate, heightCm: p.heightCm, weightKg: p.currentWeightKg,
                 activity: p.activity, goal: p.goal, weeklyRateKg: p.weeklyRateKg)
    }

    /// When the goal weight should be reached at the chosen weekly pace.
    static func goalDate(current: Double, goal: Double, weeklyRateKg: Double, from date: Date = .now) -> Date? {
        let remaining = abs(current - goal)
        guard weeklyRateKg > 0, remaining > 0.05 else { return nil }
        let days = remaining / weeklyRateKg * 7
        return Calendar.current.date(byAdding: .day, value: Int(days.rounded()), to: date)
    }

    static func bmi(kg: Double, cm: Double) -> Double {
        let m = cm / 100
        guard m > 0 else { return 0 }
        return kg / (m * m)
    }
}
