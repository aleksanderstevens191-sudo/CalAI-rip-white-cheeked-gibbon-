import SwiftUI

enum Sex: String, CaseIterable, Identifiable, Codable {
    case male, female, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .male: "Male"
        case .female: "Female"
        case .other: "Other"
        }
    }
}

enum WeightGoal: String, CaseIterable, Identifiable, Codable {
    case lose, maintain, gain
    var id: String { rawValue }
    var title: String {
        switch self {
        case .lose: "Lose weight"
        case .maintain: "Maintain"
        case .gain: "Gain weight"
        }
    }
    var icon: String {
        switch self {
        case .lose: "arrow.down.right"
        case .maintain: "equal"
        case .gain: "arrow.up.right"
        }
    }
}

enum ActivityLevel: String, CaseIterable, Identifiable, Codable {
    case low, moderate, high
    var id: String { rawValue }
    var title: String {
        switch self {
        case .low: "0–2"
        case .moderate: "3–5"
        case .high: "6+"
        }
    }
    var subtitle: String {
        switch self {
        case .low: "Workouts now and then"
        case .moderate: "A few workouts per week"
        case .high: "Dedicated athlete"
        }
    }
    var icon: String {
        switch self {
        case .low: "circle.fill"
        case .moderate: "circle.grid.2x1.fill"
        case .high: "circle.grid.3x3.fill"
        }
    }
    /// Multiplier applied to BMR to estimate total daily energy expenditure.
    var factor: Double {
        switch self {
        case .low: 1.375
        case .moderate: 1.55
        case .high: 1.725
        }
    }
}

enum UnitSystem: String, CaseIterable, Identifiable, Codable {
    case imperial, metric
    var id: String { rawValue }
    var title: String { self == .imperial ? "Imperial" : "Metric" }
    var weightUnit: String { self == .imperial ? "lbs" : "kg" }
}

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum MealType: String, CaseIterable, Identifiable, Codable {
    case breakfast, lunch, dinner, snack
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .breakfast: "sunrise.fill"
        case .lunch: "sun.max.fill"
        case .dinner: "moon.stars.fill"
        case .snack: "carrot.fill"
        }
    }
    static func guess(for date: Date) -> MealType {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 4..<11: return .breakfast
        case 11..<15: return .lunch
        case 17..<22: return .dinner
        default: return .snack
        }
    }
}

enum EntrySource: String, Codable {
    case photo, label, barcode, text, database, manual, saved
    var icon: String {
        switch self {
        case .photo: "camera.fill"
        case .label: "doc.text.viewfinder"
        case .barcode: "barcode"
        case .text: "text.bubble.fill"
        case .database: "magnifyingglass"
        case .manual: "square.and.pencil"
        case .saved: "bookmark.fill"
        }
    }
}

enum EntryStatus: String, Codable {
    case analyzing, ready, failed
}

enum ExerciseKind: String, CaseIterable, Identifiable, Codable {
    case run, weights, describe, manual
    var id: String { rawValue }
    var title: String {
        switch self {
        case .run: "Run"
        case .weights: "Weight lifting"
        case .describe: "Describe"
        case .manual: "Manual"
        }
    }
    var subtitle: String {
        switch self {
        case .run: "Running, jogging, sprinting, etc."
        case .weights: "Machines, free weights, etc."
        case .describe: "Write your workout in text"
        case .manual: "Enter exactly how many calories you burned"
        }
    }
    var icon: String {
        switch self {
        case .run: "figure.run"
        case .weights: "dumbbell.fill"
        case .describe: "pencil.and.list.clipboard"
        case .manual: "flame.fill"
        }
    }
}

enum Intensity: String, CaseIterable, Identifiable, Codable {
    case high, medium, low
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    func subtitle(for kind: ExerciseKind) -> String {
        switch (kind, self) {
        case (.run, .high): "Sprinting – 14 mph (4 minute miles)"
        case (.run, .medium): "Jogging – 6 mph (10 minute miles)"
        case (.run, .low): "Chill walk – 3 mph (20 minute miles)"
        case (_, .high): "Training to failure, breathing heavily"
        case (_, .medium): "Sweating a lot, many reps"
        case (_, .low): "Not breaking a sweat, light effort"
        }
    }
    /// Metabolic equivalent (MET) for each activity/intensity pair.
    func met(for kind: ExerciseKind) -> Double {
        switch (kind, self) {
        case (.run, .high): 12.5
        case (.run, .medium): 9.8
        case (.run, .low): 3.5
        case (_, .high): 6.0
        case (_, .medium): 5.0
        case (_, .low): 3.5
        }
    }
}
