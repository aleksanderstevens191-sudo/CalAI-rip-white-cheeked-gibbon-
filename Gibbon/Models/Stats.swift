import SwiftUI

extension Calendar {
    func days(back n: Int, from date: Date = .now) -> [Date] {
        let today = startOfDay(for: date)
        return (0..<n).reversed().compactMap { self.date(byAdding: .day, value: -$0, to: today) }
    }
}

enum RingStatus {
    case none, inProgress, onTrack, close, off
    var color: Color {
        switch self {
        case .none: Theme.track
        case .inProgress: Theme.ink
        case .onTrack: Theme.good
        case .close: Theme.warn
        case .off: Theme.bad
        }
    }
    static func forDay(eaten: Double, goal: Double) -> RingStatus {
        guard eaten > 0, goal > 0 else { return .none }
        let diff = abs(eaten - goal) / goal
        if diff <= 0.10 { return .onTrack }
        if diff <= 0.20 { return .close }
        return .off
    }
}

/// Everything the Home screen needs for one day.
struct DayStats {
    let day: Date
    let foods: [FoodEntry]
    let waters: [WaterEntry]
    let exercises: [ExerciseEntry]
    let eaten: Nutrients
    let burned: Double
    let waterMl: Double
    let rollover: Double
    let bonus: Double
    let goals: Nutrients
    let healthScore: Double?

    init(day: Date, profile: Profile, foods all: [FoodEntry], waters: [WaterEntry], exercises: [ExerciseEntry]) {
        let cal = Calendar.current
        self.day = day
        foods = all.filter { !$0.isTemplate && cal.isDate($0.date, inSameDayAs: day) }
        self.waters = waters.filter { cal.isDate($0.date, inSameDayAs: day) }
        self.exercises = exercises.filter { cal.isDate($0.date, inSameDayAs: day) }
        eaten = foods.reduce(.zero) { $0 + $1.totals }
        burned = self.exercises.reduce(0) { $0 + $1.calories }
        waterMl = self.waters.reduce(0) { $0 + $1.ml }
        rollover = profile.rolloverCalories ? Stats.rollover(profile: profile, foods: all, into: day) : 0
        bonus = rollover + (profile.addBurnedCalories ? burned : 0)
        var g = profile.goals
        g.calories += bonus
        goals = g
        let scored = foods.filter { $0.status == .ready && $0.healthScore != nil && $0.totals.calories > 0 }
        let weight = scored.reduce(0) { $0 + $1.totals.calories }
        healthScore = weight > 0 ? scored.reduce(0) { $0 + Double($1.healthScore ?? 0) * $1.totals.calories } / weight : nil
    }

    func left(_ kind: NutrientKind) -> Double { goals[kind] - eaten[kind] }
    func progress(_ kind: NutrientKind) -> Double { goals[kind] > 0 ? eaten[kind] / goals[kind] : 0 }
}

enum Stats {
    static var cal: Calendar { Calendar.current }

    static func loggedDays(_ foods: [FoodEntry]) -> Set<Date> {
        Set(foods.filter { !$0.isTemplate }.map { cal.startOfDay(for: $0.date) })
    }

    static func caloriesByDay(_ foods: [FoodEntry]) -> [Date: Double] {
        var out: [Date: Double] = [:]
        for f in foods where !f.isTemplate {
            out[cal.startOfDay(for: f.date), default: 0] += f.totals.calories
        }
        return out
    }

    static func nutrientsByDay(_ foods: [FoodEntry]) -> [Date: Nutrients] {
        var out: [Date: Nutrients] = [:]
        for f in foods where !f.isTemplate {
            out[cal.startOfDay(for: f.date), default: .zero] += f.totals
        }
        return out
    }

    static func burnedByDay(_ ex: [ExerciseEntry]) -> [Date: Double] {
        var out: [Date: Double] = [:]
        for e in ex { out[cal.startOfDay(for: e.date), default: 0] += e.calories }
        return out
    }

    /// Consecutive days with at least one meal, ending today (or yesterday if nothing is logged yet today).
    static func streak(_ foods: [FoodEntry]) -> Int {
        let days = loggedDays(foods)
        var day = cal.startOfDay(for: .now)
        if !days.contains(day) {
            day = cal.date(byAdding: .day, value: -1, to: day)!
        }
        var count = 0
        while days.contains(day) {
            count += 1
            day = cal.date(byAdding: .day, value: -1, to: day)!
        }
        return count
    }

    static func longestStreak(_ foods: [FoodEntry]) -> Int {
        let days = loggedDays(foods).sorted()
        var best = 0, run = 0
        var prev: Date?
        for d in days {
            if let p = prev, cal.dateComponents([.day], from: p, to: d).day == 1 { run += 1 } else { run = 1 }
            best = max(best, run)
            prev = d
        }
        return best
    }

    /// Up to 200 unused calories from the previous day carry over.
    static func rollover(profile: Profile, foods: [FoodEntry], into day: Date) -> Double {
        guard let yesterday = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: day)) else { return 0 }
        let yFoods = foods.filter { !$0.isTemplate && cal.isDate($0.date, inSameDayAs: yesterday) }
        guard !yFoods.isEmpty else { return 0 }
        let eaten = yFoods.reduce(0) { $0 + $1.totals.calories }
        return min(200, max(0, profile.calorieGoal - eaten)).rounded()
    }

    static func latestWeight(_ weights: [WeightEntry], profile: Profile) -> Double {
        weights.max(by: { $0.date < $1.date })?.kg ?? profile.currentWeightKg
    }

    /// Start of the calendar week containing `date`, offset by whole weeks.
    static func weekStart(offset: Int, from date: Date = .now) -> Date {
        let start = cal.dateInterval(of: .weekOfYear, for: date)?.start ?? cal.startOfDay(for: date)
        return cal.date(byAdding: .weekOfYear, value: offset, to: start) ?? start
    }

    static func weekDays(offset: Int) -> [Date] {
        let s = weekStart(offset: offset)
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: s) }
    }
}

// MARK: - Formatting

enum Fmt {
    static let lbPerKg = 2.20462
    static let mlPerOz = 29.5735

    static func weightValue(_ kg: Double, _ u: UnitSystem) -> Double {
        u == .imperial ? kg * lbPerKg : kg
    }
    static func kg(from value: Double, _ u: UnitSystem) -> Double {
        u == .imperial ? value / lbPerKg : value
    }
    static func weight(_ kg: Double, _ u: UnitSystem, decimals: Int = 1) -> String {
        let v = weightValue(kg, u)
        return "\(number(v, decimals: decimals)) \(u.weightUnit)"
    }
    static func number(_ v: Double, decimals: Int = 1) -> String {
        if decimals == 0 || v.rounded() == v { return String(Int(v.rounded())) }
        return String(format: "%.\(decimals)f", v)
    }
    static func height(_ cm: Double, _ u: UnitSystem) -> String {
        if u == .metric { return "\(Int(cm.rounded())) cm" }
        let totalIn = Int((cm / 2.54).rounded())
        return "\(totalIn / 12)′ \(totalIn % 12)″"
    }
    static func waterValue(_ ml: Double, _ u: UnitSystem) -> Double {
        u == .imperial ? ml / mlPerOz : ml
    }
    static func water(_ ml: Double, _ u: UnitSystem) -> String {
        if u == .metric { return "\(Int(ml.rounded())) ml" }
        let oz = ml / mlPerOz
        let cups = oz / 8
        return "\(Int(oz.rounded())) fl oz (\(number(cups, decimals: cups.rounded() == cups ? 0 : 1)) cups)"
    }
    static func time(_ d: Date) -> String { d.formatted(date: .omitted, time: .shortened) }
    static func shortDate(_ d: Date) -> String { d.formatted(.dateTime.month(.abbreviated).day()) }
    static func longDate(_ d: Date) -> String { d.formatted(.dateTime.month(.abbreviated).day().year()) }
    static func signed(_ v: Double, decimals: Int = 1) -> String {
        let s = number(abs(v), decimals: decimals)
        if abs(v) < 0.05 { return "0" }
        return v > 0 ? "+\(s)" : "−\(s)"
    }
    static func dayLabel(_ d: Date) -> String {
        let c = Calendar.current
        if c.isDateInToday(d) { return "Today" }
        if c.isDateInYesterday(d) { return "Yesterday" }
        return d.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}

extension Double {
    var int: Int { Int(self.rounded()) }
}
