import Foundation

/// USDA FoodData Central: lab-analyzed nutrition for generic foods (Foundation Foods and SR Legacy), public domain.
struct FDCFood: Identifiable, Hashable {
    let id: Int
    let description: String
    let dataType: String
    /// Per 100 g. Nil fields were not reported by USDA for this food.
    let calories: Double?
    let protein: Double?
    let carbs: Double?
    let fat: Double?
    let fiber: Double?
    let sugar: Double?
    let sodium: Double?

    /// Fill any nutrient USDA didn't report from a fallback (usually the AI's estimate).
    func per100(fallback: Nutrients = .zero) -> Nutrients {
        Nutrients(calories: calories ?? fallback.calories,
                  protein: protein ?? fallback.protein,
                  carbs: carbs ?? fallback.carbs,
                  fat: fat ?? fallback.fat,
                  fiber: fiber ?? fallback.fiber,
                  sugar: sugar ?? fallback.sugar,
                  sodium: sodium ?? fallback.sodium)
    }

    var label: String { "USDA \(dataType) #\(id)" }
}

enum USDA {
    static let demoKey = "DEMO_KEY"
    /// Appended to an ingredient's source when the user picked the USDA food by hand (never auto-replaced).
    static let chosenByUserSuffix = " · chosen by you"

    /// A free personal key from api.data.gov allows 1,000 requests/hour; DEMO_KEY is heavily rate-limited.
    static var apiKey: String {
        get {
            let k = Keychain.get("usda-api-key")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return k.isEmpty ? demoKey : k
        }
        set {
            let v = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if v.isEmpty || v == demoKey { Keychain.delete("usda-api-key") } else { Keychain.set(v, for: "usda-api-key") }
        }
    }

    static var hasPersonalKey: Bool { apiKey != demoKey }

    static func search(_ query: String, pageSize: Int = 6) async throws -> [FDCFood] {
        var c = URLComponents(string: "https://api.nal.usda.gov/fdc/v1/foods/search")!
        c.queryItems = [
            .init(name: "api_key", value: apiKey),
            .init(name: "query", value: query),
            .init(name: "dataType", value: "Foundation,SR Legacy"),
            .init(name: "pageSize", value: String(pageSize)),
        ]
        var request = URLRequest(url: c.url!)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw URLError(.badServerResponse) }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let foods = json["foods"] as? [[String: Any]] else { return [] }
        return foods.compactMap(parse)
    }

    private static func parse(_ f: [String: Any]) -> FDCFood? {
        guard let id = f["fdcId"] as? Int, let desc = f["description"] as? String else { return nil }
        var values: [Int: (Double, String)] = [:]
        for n in f["foodNutrients"] as? [[String: Any]] ?? [] {
            guard let nid = n["nutrientId"] as? Int, let v = n["value"] as? Double else { continue }
            values[nid] = (v, (n["unitName"] as? String ?? "").uppercased())
        }
        func g(_ ids: Int...) -> Double? {
            for i in ids { if let v = values[i] { return v.0 } }
            return nil
        }
        // Energy: 1008 is kcal; Foundation foods sometimes only report Atwater energy (2048 specific, 2047 general).
        var kcal: Double?
        if let e = values[1008] { kcal = e.1 == "KJ" ? e.0 / 4.184 : e.0 }
        kcal = kcal ?? g(2048, 2047)
        guard let kcal else { return nil }
        return FDCFood(id: id, description: desc, dataType: f["dataType"] as? String ?? "",
                       calories: kcal, protein: g(1003), carbs: g(1005, 1050), fat: g(1004, 1085),
                       fiber: g(1079), sugar: g(2000, 1063), sodium: g(1093))
    }

    /// A packaged product from USDA's Branded Foods data (manufacturer-supplied, matched by barcode).
    struct BrandedProduct {
        let fdcId: Int
        let gtin: String
        let name: String
        let brand: String
        let servingGrams: Double?
        let servingText: String?
        let per100: Nutrients
        let updated: String?
    }

    /// Look up a product by its barcode in USDA Branded Foods. Nil when not found or USDA is unavailable.
    static func branded(barcode code: String) async -> BrandedProduct? {
        // US products are usually stored as the 12-digit UPC; try that first, then the code as given.
        var queries: [String] = []
        if code.count == 13, code.hasPrefix("0") { queries.append(String(code.dropFirst())) }
        queries.append(code)
        for q in queries {
            guard let foods = try? await rawSearch(q, dataType: "Branded", pageSize: 10) else { return nil }
            for f in foods {
                guard let gtin = f["gtinUpc"] as? String, ProductCode.canonical(gtin) == code,
                      let id = f["fdcId"] as? Int, let food = parse(f) else { continue }
                let unit = (f["servingSizeUnit"] as? String ?? "").lowercased()
                let size = f["servingSize"] as? Double
                // Serving size is only a weight when the unit is grams (or ml, ≈ g for most drinks).
                let grams = (unit == "g" || unit == "grm" || unit == "ml" || unit == "mlt") ? size : nil
                let household = (f["householdServingFullText"] as? String)?.trimmingCharacters(in: .whitespaces)
                let description = (f["description"] as? String ?? food.description).localizedCapitalized
                return BrandedProduct(fdcId: id, gtin: code, name: description,
                                      brand: (f["brandName"] as? String) ?? (f["brandOwner"] as? String) ?? "",
                                      servingGrams: grams.flatMap { $0 > 0 ? $0 : nil },
                                      servingText: (household?.isEmpty ?? true) ? nil : household,
                                      per100: food.per100(),
                                      updated: (f["modifiedDate"] as? String) ?? (f["publishedDate"] as? String))
            }
            if !foods.isEmpty { break }   // results came back but none matched this barcode
        }
        return nil
    }

    private static func rawSearch(_ query: String, dataType: String, pageSize: Int) async throws -> [[String: Any]] {
        var c = URLComponents(string: "https://api.nal.usda.gov/fdc/v1/foods/search")!
        c.queryItems = [
            .init(name: "api_key", value: apiKey),
            .init(name: "query", value: query),
            .init(name: "dataType", value: dataType),
            .init(name: "pageSize", value: String(pageSize)),
        ]
        var request = URLRequest(url: c.url!)
        request.timeoutInterval = 12
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let foods = json["foods"] as? [[String: Any]] else { throw URLError(.badServerResponse) }
        return foods
    }

    /// Find the USDA entry that matches an AI-identified ingredient, or nil if nothing is close enough to trust.
    /// The AI's own per-100 g estimate is used as a sanity check so a bad text match can't wreck the numbers.
    static func bestMatch(query: String, estimate: Nutrients) async -> FDCFood? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, let results = try? await search(q) else { return nil }
        let tolerance = max(40, estimate.calories * 0.25)
        let candidates = results.prefix(5).filter { abs(($0.calories ?? 0) - estimate.calories) <= tolerance }
        // Prefer the highest-ranked result that passes; among near-ties prefer the closest calorie density.
        return candidates.min { a, b in
            let da = abs((a.calories ?? 0) - estimate.calories), db = abs((b.calories ?? 0) - estimate.calories)
            return da + Double(results.firstIndex(of: a) ?? 0) * 8 < db + Double(results.firstIndex(of: b) ?? 0) * 8
        }
    }

    /// Replace the AI's per-100 g values with USDA lab values wherever a trustworthy match exists.
    static func ground(_ ingredients: [AIIngredient]) async -> [AIIngredient] {
        await withTaskGroup(of: (Int, AIIngredient).self) { group in
            for (i, ing) in ingredients.enumerated() {
                group.addTask {
                    var out = ing
                    guard let match = await bestMatch(query: ing.usdaQuery, estimate: ing.per100g.nutrients) else { return (i, out) }
                    out.per100g = AIPer100(match.per100(fallback: ing.per100g.nutrients))
                    out.source = "\(match.label): \(match.description)"
                    return (i, out)
                }
            }
            var result = ingredients
            for await (i, ing) in group { result[i] = ing }
            return result
        }
    }
}
