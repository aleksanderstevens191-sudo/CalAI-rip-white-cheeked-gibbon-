import Foundation

// MARK: - Result types

struct AIPer100: Codable, Equatable {
    var kcal: Double
    var protein_g: Double
    var carbs_g: Double
    var fat_g: Double
    var fiber_g: Double
    var sugar_g: Double
    var sodium_mg: Double

    var nutrients: Nutrients {
        Nutrients(calories: kcal, protein: protein_g, carbs: carbs_g, fat: fat_g,
                  fiber: fiber_g, sugar: sugar_g, sodium: sodium_mg)
    }

    init(_ n: Nutrients) {
        kcal = n.calories; protein_g = n.protein; carbs_g = n.carbs; fat_g = n.fat
        fiber_g = n.fiber; sugar_g = n.sugar; sodium_mg = n.sodium
    }
}

struct AIIngredient: Codable, Equatable {
    var name: String
    var portion: String
    var grams: Double
    var usdaQuery: String
    var per100g: AIPer100
    /// Where the per-100 g values came from. Set by the app after USDA grounding, never by the model.
    var source: String?
}

struct AIFoodResult: Codable, Equatable {
    var isFood: Bool
    var mealName: String
    var summary: String
    var confidence: Double
    var healthScore: Int
    var healthNotes: String
    var ingredients: [AIIngredient]
    /// What this request cost, from reported token usage. Set by the app, never by the model.
    var costUSD: Double?
}

extension AIFoodResult {
    /// Snapshot of an entry, used as the starting point for "Fix results".
    init(entry: FoodEntry) {
        isFood = true
        mealName = entry.name
        summary = entry.aiNotes
        confidence = entry.confidence ?? 0.7
        healthScore = entry.healthScore ?? 5
        healthNotes = entry.healthNotes
        ingredients = entry.sortedIngredients.map {
            AIIngredient(name: $0.name, portion: $0.portion, grams: $0.grams, usdaQuery: $0.usdaQuery,
                         per100g: AIPer100($0.per100), source: $0.source.isEmpty ? nil : $0.source)
        }
    }
}

struct AIExerciseEstimate: Codable {
    var name: String
    var minutes: Double
    var calories: Double
}

// MARK: - Schemas

private enum Schema {
    static let number: [String: Any] = ["type": "number"]
    static let string: [String: Any] = ["type": "string"]

    static func object(_ props: [String: Any]) -> [String: Any] {
        ["type": "object", "properties": props, "required": Array(props.keys).sorted(), "additionalProperties": false]
    }

    static let per100 = object([
        "kcal": number, "protein_g": number, "carbs_g": number, "fat_g": number,
        "fiber_g": number, "sugar_g": number, "sodium_mg": number,
    ])

    static let ingredient = object([
        "name": string,
        "portion": string,
        "grams": number,
        "usdaQuery": string,
        "per100g": per100,
    ])

    static let result = object([
        "isFood": ["type": "boolean"],
        "mealName": string,
        "summary": string,
        "confidence": number,
        "healthScore": ["type": "integer"],
        "healthNotes": string,
        "ingredients": ["type": "array", "items": ingredient],
    ])

    static let exercise = object([
        "name": string,
        "minutes": number,
        "calories": number,
    ])
}

// MARK: - Prompts

private enum Prompt {
    static let core = """
    You are a registered dietitian and food-portion estimation expert working inside a calorie-tracking app. \
    People rely on your numbers to hit precise daily targets, so accuracy matters more than speed.

    How to estimate:
    1. Identify every distinct food and drink component. Include the ones people forget: cooking oil or butter, \
    dressings, sauces, gravies, cheese, toppings, spreads, breading, glazes, sugar or milk in drinks. When cooking fat \
    is likely but not visible (sautéed or roasted vegetables, fried eggs, stir-fries, most restaurant dishes), add a \
    realistic amount as its own ingredient.
    2. Estimate the edible weight in grams of each component as served: cooked weight for cooked foods, without bones, \
    shells, pits, peels or packaging. Use scale cues: a dinner plate is about 26–27 cm across, a side plate about 20 cm, \
    a cereal bowl about 15 cm, a fork about 19 cm, a teaspoon about 15 cm, a standard can 12 cm tall, an adult hand \
    about 18–19 cm long. Think in three dimensions — mounds, deep bowls and stacked foods hold more than their top area \
    suggests; thin layers hold less.
    3. For each component give nutrition per 100 g for that exact preparation (for example "chicken breast, grilled, \
    skinless" or "white rice, cooked"), using USDA FoodData Central reference values, or the published nutrition for \
    recognizable branded, packaged or chain-restaurant items. The app multiplies per-100 g values by grams, so never \
    pre-multiply. Sodium is in milligrams.
    4. Split mixed dishes into their main components (a burrito into tortilla, rice, beans, meat, cheese, salsa, sour \
    cream; a sandwich into bread, fillings and spreads) unless it is a single packaged product.
    5. Anything the user tells you is ground truth and overrides what you infer from a photo.

    Output fields:
    - mealName: a short, natural name for the whole meal (2–5 words).
    - ingredients: name is short and specific; portion is a friendly household amount ("1 cup", "2 slices", \
    "1 tbsp", "1 medium fillet").
    - usdaQuery: a search phrase written the way USDA FoodData Central names generic foods, matching the exact \
    preparation, e.g. "Chicken, broilers or fryers, breast, meat only, cooked, roasted", "Rice, white, long-grain, \
    regular, enriched, cooked", "Oil, olive, salad or cooking", "Broccoli, cooked, boiled, drained, without salt". \
    The app looks this up and replaces your per-100 g values with USDA lab data when it matches, so be precise about \
    cut, fat level, raw vs cooked and cooking method. Use an empty string for branded products, chain-restaurant items \
    and anything USDA wouldn't list as a generic food.
    - summary: one or two sentences on the key assumptions (portion sizes, cooking method, hidden fats) so the user \
    knows what to correct.
    - confidence: 0–1 for how sure you are about identification and portions.
    - healthScore: integer 1–10. 10 = whole, minimally processed, rich in fiber, protein and micronutrients, low in \
    added sugar and sodium. 1 = ultra-processed, high in added sugar, refined starch, saturated fat or sodium with \
    little nutritional value. healthNotes: one sentence explaining the score.
    - isFood: false only if there is no food or drink at all; then explain briefly in summary and return no ingredients.
    """

    static let photo = core + """


    You will receive a photo of a meal or drink, possibly with a note from the user.
    """

    static let label = core + """


    You will receive a photo of a nutrition facts label (possibly with the package). Read it exactly rather than \
    estimating. Return exactly one ingredient that represents ONE serving as printed: grams = the serving size in grams \
    (for drinks given only in ml, use ~1 g per ml unless the product is clearly denser; if no weight is printed, estimate \
    it), portion = the printed serving size text, and per100g = each per-serving label value ÷ serving grams × 100. \
    Use the product name if it is visible, otherwise "Packaged food". Set usdaQuery to an empty string. Base the health \
    score on the label values and the ingredient list if it is visible.
    """

    static let text = core + """


    You will receive a written description of what the user ate. Use the quantities they state; where they don't state \
    one, assume a typical single adult portion and say so in summary.
    """

    static let lookup = core + """


    You will receive a short description of one or more foods to ADD to an existing meal. Return only the item(s) \
    described — do not add cooking oils or extras the user did not mention. Use the stated amount, or a typical single \
    portion if none is given. mealName can simply name the item(s).
    """

    static let fix = core + """


    You will receive a previous analysis of a meal (as JSON), the original photo if there was one, and the user's \
    correction. Apply the correction and return the complete, updated analysis — every ingredient, not just the changed \
    ones. Keep ingredients the user did not mention unless the correction implies they are wrong, and keep their names \
    exactly as given. Some ingredients have a "source": values from a nutrition label, Open Food Facts, a USDA food the \
    user chose, or the user's own edits are exact — keep their per100g unchanged and only change grams or portion if the \
    correction calls for it. Re-check portions, and re-check per-100 g values only for ingredients without a source. \
    Update mealName, summary and healthScore to match.
    """

    static let exercise = """
    You estimate calories burned for a workout described in text. Use the Compendium of Physical Activities MET values: \
    calories = MET × body weight (kg) × hours. If the duration isn't given, assume a typical session and include it in \
    minutes. Return a short activity name (2–4 words), the minutes, and total calories burned (not net of resting burn).
    """
}

// MARK: - API

enum FoodAI {
    static func analyzePhoto(_ jpeg: Data, hint: String) async throws -> AIFoodResult {
        var text = "Analyze this meal and estimate its nutrition."
        if !hint.trimmingCharacters(in: .whitespaces).isEmpty {
            text += "\n\nNote from the user: \(hint)"
        }
        return try await run(system: Prompt.photo, content: [imageBlock(jpeg), ["type": "text", "text": text]])
    }

    static func analyzeLabel(_ jpeg: Data) async throws -> AIFoodResult {
        // Label values are exact, so they are never replaced with USDA data.
        try await run(system: Prompt.label, content: [imageBlock(jpeg), ["type": "text", "text": "Read this nutrition label."]],
                      grounded: false)
    }

    static func analyzeText(_ description: String) async throws -> AIFoodResult {
        try await run(system: Prompt.text, content: [["type": "text", "text": "What I ate: \(description)"]])
    }

    static func lookupIngredients(_ description: String) async throws -> [AIIngredient] {
        let r = try await run(system: Prompt.lookup, content: [["type": "text", "text": "Item(s) to add: \(description)"]])
        return r.ingredients
    }

    static func fix(_ current: AIFoodResult, image: Data?, correction: String) async throws -> AIFoodResult {
        var snapshot = current
        snapshot.costUSD = nil
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let json = String(data: try encoder.encode(snapshot), encoding: .utf8) ?? "{}"
        var content: [[String: Any]] = []
        if let image { content.append(imageBlock(image)) }
        content.append(["type": "text", "text": "Previous analysis:\n\(json)\n\nUser's correction: \(correction)"])
        var result = try await run(system: Prompt.fix, content: content, grounded: false)

        // Exact values (label, Open Food Facts, a USDA food the user chose, the user's edits) are never re-estimated
        // or re-grounded: carry them over and take only the new amount. Everything else is grounded as usual.
        var toGround: [Int] = []
        for i in result.ingredients.indices {
            let name = result.ingredients[i].name
            if let old = current.ingredients.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }),
               let source = old.source, isExact(source) {
                result.ingredients[i].per100g = old.per100g
                result.ingredients[i].source = source
                result.ingredients[i].usdaQuery = old.usdaQuery
            } else {
                toGround.append(i)
            }
        }
        let grounded = await USDA.ground(toGround.map { result.ingredients[$0] })
        for (k, i) in toGround.enumerated() { result.ingredients[i] = grounded[k] }
        return result
    }

    /// Automatic generic-food USDA matches may be redone; every other recorded source (labels, branded products,
    /// Open Food Facts, USDA foods you picked, your own edits) is treated as exact.
    static func isExact(_ source: String) -> Bool {
        guard !source.isEmpty else { return false }
        let automatic = (source.hasPrefix("USDA Foundation") || source.hasPrefix("USDA SR Legacy"))
            && !source.hasSuffix(USDA.chosenByUserSuffix)
        return !automatic
    }

    static func estimateExercise(_ description: String, weightKg: Double) async throws -> AIExerciseEstimate {
        let text = "Body weight: \(Int(weightKg.rounded())) kg.\nWorkout: \(description)"
        let reply = try await ClaudeClient.structured(system: Prompt.exercise,
                                                      content: [["type": "text", "text": text]],
                                                      schema: Schema.exercise,
                                                      effort: .medium)
        return try JSONDecoder().decode(AIExerciseEstimate.self, from: reply.data)
    }

    // MARK: Helpers

    private static func imageBlock(_ jpeg: Data) -> [String: Any] {
        ["type": "image",
         "source": ["type": "base64", "media_type": "image/jpeg", "data": jpeg.base64EncodedString()]]
    }

    private static func run(system: String, content: [[String: Any]], grounded: Bool = true) async throws -> AIFoodResult {
        let reply = try await ClaudeClient.structured(system: system, content: content, schema: Schema.result)
        var result: AIFoodResult
        do {
            result = try JSONDecoder().decode(AIFoodResult.self, from: reply.data)
        } catch {
            throw AIError.badResponse(error.localizedDescription)
        }
        result.costUSD = reply.costUSD
        if !result.isFood || result.ingredients.isEmpty {
            throw AIError.notFood(result.summary)
        }
        if grounded {
            // The model estimates portions; USDA supplies lab-measured nutrition per gram where it has a match.
            result.ingredients = await USDA.ground(result.ingredients)
        }
        return result
    }
}
