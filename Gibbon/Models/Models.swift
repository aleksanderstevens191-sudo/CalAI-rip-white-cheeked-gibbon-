import Foundation
import SwiftData

// MARK: - Profile

@Model
final class Profile {
    var name: String = ""
    var username: String = ""
    var sexRaw: String = Sex.male.rawValue
    var birthDate: Date = Calendar.current.date(byAdding: .year, value: -25, to: .now) ?? .now
    var heightCm: Double = 175
    var startWeightKg: Double = 70
    var currentWeightKg: Double = 70
    var goalWeightKg: Double = 70
    var goalRaw: String = WeightGoal.maintain.rawValue
    var weeklyRateKg: Double = 0.45
    var activityRaw: String = ActivityLevel.moderate.rawValue
    var unitsRaw: String = UnitSystem.imperial.rawValue
    var appearanceRaw: String = Appearance.system.rawValue

    var calorieGoal: Double = 2000
    var proteinGoal: Double = 150
    var carbsGoal: Double = 200
    var fatGoal: Double = 65
    var fiberGoal: Double = 30
    var sugarGoal: Double = 75
    var sodiumGoal: Double = 2300
    var waterGoalMl: Double = 2400

    var addBurnedCalories: Bool = false
    var rolloverCalories: Bool = false
    var onboarded: Bool = false
    var createdAt: Date = Date.now

    init() {}

    var sex: Sex {
        get { Sex(rawValue: sexRaw) ?? .male }
        set { sexRaw = newValue.rawValue }
    }
    var goal: WeightGoal {
        get { WeightGoal(rawValue: goalRaw) ?? .maintain }
        set { goalRaw = newValue.rawValue }
    }
    var activity: ActivityLevel {
        get { ActivityLevel(rawValue: activityRaw) ?? .moderate }
        set { activityRaw = newValue.rawValue }
    }
    var units: UnitSystem {
        get { UnitSystem(rawValue: unitsRaw) ?? .imperial }
        set { unitsRaw = newValue.rawValue }
    }
    var appearance: Appearance {
        get { Appearance(rawValue: appearanceRaw) ?? .system }
        set { appearanceRaw = newValue.rawValue }
    }

    var goals: Nutrients {
        Nutrients(calories: calorieGoal, protein: proteinGoal, carbs: carbsGoal, fat: fatGoal,
                  fiber: fiberGoal, sugar: sugarGoal, sodium: sodiumGoal)
    }

    func apply(_ plan: Planner.Plan) {
        calorieGoal = plan.calories
        proteinGoal = plan.protein
        carbsGoal = plan.carbs
        fatGoal = plan.fat
        fiberGoal = plan.fiber
        sugarGoal = plan.sugar
        sodiumGoal = plan.sodium
        waterGoalMl = plan.waterMl
    }

    func setGoal(_ kind: NutrientKind, _ value: Double) {
        switch kind {
        case .calories: calorieGoal = value
        case .protein: proteinGoal = value
        case .carbs: carbsGoal = value
        case .fat: fatGoal = value
        case .fiber: fiberGoal = value
        case .sugar: sugarGoal = value
        case .sodium: sodiumGoal = value
        }
    }
}

// MARK: - Food

@Model
final class FoodEntry {
    var uuid: UUID = UUID()
    var date: Date = Date.now
    var name: String = ""
    var mealRaw: String = MealType.snack.rawValue
    var sourceRaw: String = EntrySource.photo.rawValue
    var statusRaw: String = EntryStatus.ready.rawValue
    @Attribute(.externalStorage) var imageData: Data?
    var servings: Double = 1
    var healthScore: Int?
    var healthNotes: String = ""
    var confidence: Double?
    var aiNotes: String = ""
    var errorMessage: String?
    var userHint: String = ""
    var barcode: String?
    /// Saved foods are stored as templates and never count toward a day.
    var isTemplate: Bool = false
    /// For templates: the entry they were saved from.
    var sourceEntryID: UUID?
    /// Total AI spend on this meal (first scan, retries, fixes and add-with-AI), in US dollars.
    var aiCostUSD: Double = 0
    /// For products with a barcode: the per-serving ingredients exactly as first read from the label or database.
    /// Later scans of the same barcode rebuild from this, so edits to one day's log never leak into the next.
    var productSnapshot: Data?
    /// True once the user has typed their own meal name, so AI results no longer rename the meal.
    var nameEdited: Bool = false
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \Ingredient.entry)
    var ingredients: [Ingredient] = []

    init(date: Date, name: String, source: EntrySource, meal: MealType? = nil, status: EntryStatus = .ready) {
        self.date = date
        self.name = name
        self.sourceRaw = source.rawValue
        self.mealRaw = (meal ?? MealType.guess(for: date)).rawValue
        self.statusRaw = status.rawValue
    }

    var meal: MealType {
        get { MealType(rawValue: mealRaw) ?? .snack }
        set { mealRaw = newValue.rawValue }
    }
    var source: EntrySource {
        get { EntrySource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }
    var status: EntryStatus {
        get { EntryStatus(rawValue: statusRaw) ?? .ready }
        set { statusRaw = newValue.rawValue }
    }

    var sortedIngredients: [Ingredient] {
        ingredients.sorted { $0.order < $1.order }
    }

    /// Nutrients for a single serving (sum of all ingredients).
    var perServing: Nutrients {
        ingredients.reduce(.zero) { $0 + $1.totals }
    }

    /// Nutrients actually eaten (per serving × servings).
    var totals: Nutrients {
        status == .ready ? perServing.scaled(servings) : .zero
    }

    var totalGrams: Double {
        ingredients.reduce(0) { $0 + $1.grams } * servings
    }
}

@Model
final class Ingredient {
    var uuid: UUID = UUID()
    var name: String = ""
    /// Human-friendly amount, e.g. "1 cup" or "2 slices".
    var portion: String = ""
    var grams: Double = 0
    // Nutrition density per 100 g. Totals are always derived from grams × density,
    // so changing the amount rescales every nutrient consistently.
    var kcal100: Double = 0
    var protein100: Double = 0
    var carbs100: Double = 0
    var fat100: Double = 0
    var fiber100: Double = 0
    var sugar100: Double = 0
    var sodium100: Double = 0
    var order: Int = 0
    /// USDA-style search name the AI gave this ingredient.
    var usdaQuery: String = ""
    /// Where the nutrition came from, e.g. "USDA SR Legacy #171477: Chicken, …" or "Open Food Facts". Empty = AI estimate.
    var source: String = ""
    var entry: FoodEntry?

    var isUSDA: Bool { source.hasPrefix("USDA") }

    init(name: String, portion: String, grams: Double, per100: Nutrients, order: Int) {
        self.name = name
        self.portion = portion
        self.grams = grams
        self.order = order
        self.per100 = per100
    }

    var per100: Nutrients {
        get {
            Nutrients(calories: kcal100, protein: protein100, carbs: carbs100, fat: fat100,
                      fiber: fiber100, sugar: sugar100, sodium: sodium100)
        }
        set {
            kcal100 = newValue.calories
            protein100 = newValue.protein
            carbs100 = newValue.carbs
            fat100 = newValue.fat
            fiber100 = newValue.fiber
            sugar100 = newValue.sugar
            sodium100 = newValue.sodium
        }
    }

    var totals: Nutrients { per100.scaled(grams / 100) }

    /// Set the total for one nutrient at the current amount by back-solving its density.
    func setTotal(_ kind: NutrientKind, _ value: Double) {
        guard grams > 0 else { return }
        var d = per100
        d[kind] = max(0, value) / grams * 100
        per100 = d
    }
}

// MARK: - Other logs

@Model
final class WaterEntry {
    var uuid: UUID = UUID()
    var date: Date = Date.now
    var ml: Double = 0
    init(date: Date, ml: Double) {
        self.date = date
        self.ml = ml
    }
}

@Model
final class ExerciseEntry {
    var uuid: UUID = UUID()
    var date: Date = Date.now
    var kindRaw: String = ExerciseKind.manual.rawValue
    var name: String = ""
    var minutes: Double = 0
    var intensityRaw: String = Intensity.medium.rawValue
    var calories: Double = 0
    init(date: Date, kind: ExerciseKind, name: String, minutes: Double, intensity: Intensity, calories: Double) {
        self.date = date
        self.kindRaw = kind.rawValue
        self.name = name
        self.minutes = minutes
        self.intensityRaw = intensity.rawValue
        self.calories = calories
    }
    var kind: ExerciseKind { ExerciseKind(rawValue: kindRaw) ?? .manual }
    var intensity: Intensity { Intensity(rawValue: intensityRaw) ?? .medium }
}

@Model
final class WeightEntry {
    var uuid: UUID = UUID()
    var date: Date = Date.now
    var kg: Double = 0
    init(date: Date, kg: Double) {
        self.date = date
        self.kg = kg
    }
}

@Model
final class ProgressPhoto {
    var uuid: UUID = UUID()
    var date: Date = Date.now
    var weightKg: Double?
    @Attribute(.externalStorage) var imageData: Data?
    init(date: Date, imageData: Data?, weightKg: Double?) {
        self.date = date
        self.imageData = imageData
        self.weightKg = weightKg
    }
}

// MARK: - Helpers

extension FoodEntry {
    /// Replace the ingredients and descriptive fields with an AI result.
    func apply(_ r: AIFoodResult, context: ModelContext) {
        let old = ingredients
        ingredients = []
        old.forEach { context.delete($0) }
        for (i, a) in r.ingredients.enumerated() {
            let ing = Ingredient(name: a.name, portion: a.portion, grams: max(0, a.grams), per100: a.per100g.nutrients, order: i)
            ing.usdaQuery = a.usdaQuery
            ing.source = a.source ?? ""
            context.insert(ing)
            ingredients.append(ing)
        }
        let trimmed = r.mealName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && !nameEdited { name = trimmed }
        healthScore = min(10, max(1, r.healthScore))
        healthNotes = r.healthNotes
        aiNotes = r.summary
        confidence = min(1, max(0, r.confidence))
        errorMessage = nil
    }

    /// Copy this entry (with its ingredients) into a new entry.
    @discardableResult
    func duplicate(into context: ModelContext, date: Date, asTemplate: Bool) -> FoodEntry {
        let copy = FoodEntry(date: date, name: name, source: asTemplate ? source : .saved,
                             meal: asTemplate ? meal : MealType.guess(for: date), status: .ready)
        copy.imageData = imageData
        copy.servings = servings
        copy.healthScore = healthScore
        copy.healthNotes = healthNotes
        copy.confidence = confidence
        copy.aiNotes = aiNotes
        copy.barcode = barcode
        copy.productSnapshot = productSnapshot
        copy.nameEdited = nameEdited
        copy.isTemplate = asTemplate
        copy.sourceEntryID = asTemplate ? uuid : nil
        context.insert(copy)
        for ing in sortedIngredients {
            let c = Ingredient(name: ing.name, portion: ing.portion, grams: ing.grams, per100: ing.per100, order: ing.order)
            c.usdaQuery = ing.usdaQuery
            c.source = ing.source
            context.insert(c)
            copy.ingredients.append(c)
        }
        return copy
    }

    func addIngredient(_ ing: Ingredient, context: ModelContext) {
        ing.order = (ingredients.map(\.order).max() ?? -1) + 1
        context.insert(ing)
        ingredients.append(ing)
    }
}
