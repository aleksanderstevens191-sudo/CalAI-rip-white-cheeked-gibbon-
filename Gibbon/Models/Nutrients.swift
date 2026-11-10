import SwiftUI

struct Nutrients: Codable, Equatable {
    var calories: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    var fiber: Double = 0
    var sugar: Double = 0
    /// Milligrams.
    var sodium: Double = 0

    static let zero = Nutrients()

    static func + (l: Nutrients, r: Nutrients) -> Nutrients {
        Nutrients(calories: l.calories + r.calories,
                  protein: l.protein + r.protein,
                  carbs: l.carbs + r.carbs,
                  fat: l.fat + r.fat,
                  fiber: l.fiber + r.fiber,
                  sugar: l.sugar + r.sugar,
                  sodium: l.sodium + r.sodium)
    }

    static func += (l: inout Nutrients, r: Nutrients) { l = l + r }

    func scaled(_ f: Double) -> Nutrients {
        Nutrients(calories: calories * f, protein: protein * f, carbs: carbs * f, fat: fat * f,
                  fiber: fiber * f, sugar: sugar * f, sodium: sodium * f)
    }

    subscript(kind: NutrientKind) -> Double {
        get {
            switch kind {
            case .calories: calories
            case .protein: protein
            case .carbs: carbs
            case .fat: fat
            case .fiber: fiber
            case .sugar: sugar
            case .sodium: sodium
            }
        }
        set {
            switch kind {
            case .calories: calories = newValue
            case .protein: protein = newValue
            case .carbs: carbs = newValue
            case .fat: fat = newValue
            case .fiber: fiber = newValue
            case .sugar: sugar = newValue
            case .sodium: sodium = newValue
            }
        }
    }
}

enum NutrientKind: String, CaseIterable, Identifiable {
    case calories, protein, carbs, fat, fiber, sugar, sodium
    var id: String { rawValue }

    static let macros: [NutrientKind] = [.protein, .carbs, .fat]
    static let micros: [NutrientKind] = [.fiber, .sugar, .sodium]

    var title: String { rawValue.capitalized }
    var unit: String {
        switch self {
        case .calories: "kcal"
        case .sodium: "mg"
        default: "g"
        }
    }
    var shortUnit: String { self == .calories ? "" : unit }
    var icon: String {
        switch self {
        case .calories: "flame.fill"
        case .protein: "bolt.fill"
        case .carbs: "laurel.leading"
        case .fat: "drop.fill"
        case .fiber: "leaf.fill"
        case .sugar: "cube.fill"
        case .sodium: "sparkles"
        }
    }
    var color: Color {
        switch self {
        case .calories: Theme.ink
        case .protein: Theme.protein
        case .carbs: Theme.carbs
        case .fat: Theme.fat
        case .fiber: Theme.fiber
        case .sugar: Theme.sugar
        case .sodium: Theme.sodium
        }
    }
    /// Sugar and sodium are limits, the others are targets.
    var isLimit: Bool { self == .sugar || self == .sodium }

    func format(_ value: Double) -> String {
        "\(Int(value.rounded()))\(shortUnit)"
    }
}
