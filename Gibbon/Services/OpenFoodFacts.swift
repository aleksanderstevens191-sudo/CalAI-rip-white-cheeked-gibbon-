import Foundation
import SwiftData

/// Free barcode and product lookups from Open Food Facts (no API key required).
struct OFFProduct: Identifiable, Hashable {
    let id: String
    let name: String
    let brand: String
    let servingGrams: Double?
    let servingText: String?
    let per100: Nutrients
    let imageURL: URL?

    var displayName: String { brand.isEmpty ? name : "\(name) · \(brand)" }
    static func == (l: OFFProduct, r: OFFProduct) -> Bool { l.id == r.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

enum OpenFoodFacts {
    private static let fields = "code,product_name,brands,nutriments,serving_size,serving_quantity,image_front_small_url"

    private static func request(_ url: URL) -> URLRequest {
        var r = URLRequest(url: url)
        r.timeoutInterval = 20
        r.setValue("WhiteCheekedGibbon/1.0 (personal iOS calorie tracker)", forHTTPHeaderField: "User-Agent")
        return r
    }

    static func product(barcode: String) async throws -> OFFProduct? {
        let code = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(code).json?fields=\(fields)") else { return nil }
        let (data, _) = try await URLSession.shared.data(for: request(url))
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              (json["status"] as? Int) == 1 || (json["status"] as? String) == "success",
              let p = json["product"] as? [String: Any] else { return nil }
        // Key the product by Open Food Facts' own canonical code, normalized the same way scans are.
        let canonical = ProductCode.canonical((json["code"] as? String) ?? (p["code"] as? String) ?? code)
        return parse(p, code: canonical)
    }

    static func search(_ query: String) async throws -> [OFFProduct] {
        var c = URLComponents(string: "https://world.openfoodfacts.org/cgi/search.pl")!
        c.queryItems = [
            .init(name: "search_terms", value: query),
            .init(name: "search_simple", value: "1"),
            .init(name: "action", value: "process"),
            .init(name: "json", value: "1"),
            .init(name: "page_size", value: "30"),
            .init(name: "fields", value: fields),
        ]
        let (data, _) = try await URLSession.shared.data(for: request(c.url!))
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let products = json["products"] as? [[String: Any]] else { return [] }
        return products.compactMap { parse($0, code: $0["code"] as? String ?? UUID().uuidString) }
    }

    private static func num(_ any: Any?) -> Double? {
        switch any {
        case let d as Double: return d
        case let i as Int: return Double(i)
        case let s as String: return Double(s)
        case let n as NSNumber: return n.doubleValue
        default: return nil
        }
    }

    private static func parse(_ p: [String: Any], code: String) -> OFFProduct? {
        let n = p["nutriments"] as? [String: Any] ?? [:]
        var kcal = num(n["energy-kcal_100g"])
        if kcal == nil, let kj = num(n["energy_100g"]) { kcal = kj / 4.184 }
        guard let kcal else { return nil }
        let name = (p["product_name"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !name.isEmpty else { return nil }
        let brand = (p["brands"] as? String)?.split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
        var sodiumMg = (num(n["sodium_100g"]) ?? 0) * 1000
        if sodiumMg == 0, let salt = num(n["salt_100g"]) { sodiumMg = salt * 400 }
        let per100 = Nutrients(calories: kcal,
                               protein: num(n["proteins_100g"]) ?? 0,
                               carbs: num(n["carbohydrates_100g"]) ?? 0,
                               fat: num(n["fat_100g"]) ?? 0,
                               fiber: num(n["fiber_100g"]) ?? 0,
                               sugar: num(n["sugars_100g"]) ?? 0,
                               sodium: sodiumMg)
        let servingText = (p["serving_size"] as? String)?.trimmingCharacters(in: .whitespaces)
        // serving_quantity is often missing even when the text says e.g. "1 bar (40 g)"; read grams from the text then.
        let serving = num(p["serving_quantity"]).flatMap { $0 > 0 ? $0 : nil } ?? servingText.flatMap(gramsIn)
        return OFFProduct(id: code, name: name, brand: brand, servingGrams: serving,
                          servingText: (servingText?.isEmpty ?? true) ? nil : servingText,
                          per100: per100,
                          imageURL: (p["image_front_small_url"] as? String).flatMap(URL.init(string:)))
    }

    /// "1 bar (40 g)" → 40, "250ml" → 250 (≈ grams for most drinks). Nil when no weight is written.
    static func gramsIn(_ text: String) -> Double? {
        guard let r = text.range(of: #"(\d+(?:[.,]\d+)?)\s*(g|gr|grams?|ml)\b"#, options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }
        let number = text[r].prefix { $0.isNumber || $0 == "." || $0 == "," }.replacingOccurrences(of: ",", with: ".")
        return Double(number).flatMap { $0 > 0 ? $0 : nil }
    }
}

/// Pulls a product number (GTIN/EAN/UPC) out of whatever a barcode or QR code contains.
enum ProductCode {
    /// Returns nil when the code holds no product number (e.g. a QR code linking to a website).
    /// `isUPCE` is true when the scanner reported a UPC-E symbol (compressed 8-digit US code).
    static func gtin(from raw: String, isUPCE: Bool = false) -> String? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if isUPCE, let expanded = expandUPCE(s) { return normalize(expanded) }
        if isGTIN(s) { return normalize(s) }

        // GS1 element string, e.g. "(01)00012345678905(17)…" or "0100012345678905…"
        if let r = s.range(of: #"\(01\)(\d{14})"#, options: .regularExpression) {
            return normalize(String(s[r].dropFirst(4)))
        }
        if s.hasPrefix("01"), s.count >= 16 {
            let g = String(s.dropFirst(2).prefix(14))
            if isGTIN(g) { return normalize(g) }
        }

        // URLs: GS1 Digital Link ("…/01/{gtin}…"), Open Food Facts product pages, or ?gtin= / ?barcode=
        if let url = URL(string: s), url.scheme?.hasPrefix("http") == true {
            let parts = url.pathComponents
            for (i, p) in parts.enumerated() where i + 1 < parts.count {
                let next = parts[i + 1]
                if (p == "01" || p == "gtin" || p == "product") && isGTIN(next) { return normalize(next) }
            }
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            for item in items where ["gtin", "barcode", "ean", "upc", "code"].contains(item.name.lowercased()) {
                if let v = item.value, isGTIN(v) { return normalize(v) }
            }
        }
        return nil
    }

    private static func isGTIN(_ s: String) -> Bool {
        [8, 12, 13, 14].contains(s.count) && s.allSatisfy(\.isNumber)
    }

    /// One form for every code: GTIN-14 with a leading 0 → 13 digits, 12-digit UPC-A → 13 digits with a leading 0.
    /// Cameras report UPC-A as 13 digits while people type the printed 12, so both must map to the same key.
    private static func normalize(_ s: String) -> String {
        if s.count == 14, s.hasPrefix("0") { return String(s.dropFirst()) }
        if s.count == 12 { return "0" + s }
        return s
    }

    /// Normalizes an already-numeric code (e.g. the code Open Food Facts returns, or a stored barcode).
    static func canonical(_ code: String) -> String {
        let s = code.trimmingCharacters(in: .whitespacesAndNewlines)
        return isGTIN(s) ? normalize(s) : s
    }

    /// UPC-E (number system 0/1, 6 digits, check digit) → 12-digit UPC-A.
    static func expandUPCE(_ code: String) -> String? {
        guard code.allSatisfy(\.isNumber) else { return nil }
        let chars = Array(code)
        var ns: Character = "0"
        var check: Character?
        let core: ArraySlice<Character>
        switch chars.count {
        case 6: core = chars[0...5]                                   // bare digits, number system 0
        case 7: ns = chars[0]; core = chars[1...6]                    // no check digit
        case 8: ns = chars[0]; core = chars[1...6]; check = chars[7]
        default: return nil
        }
        guard ns == "0" || ns == "1" else { return nil }
        let d = core.map(String.init)
        let body: String
        switch d[5] {
        case "0", "1", "2": body = d[0] + d[1] + d[5] + "0000" + d[2] + d[3] + d[4]
        case "3": body = d[0] + d[1] + d[2] + "00000" + d[3] + d[4]
        case "4": body = d[0] + d[1] + d[2] + d[3] + "00000" + d[4]
        default: body = d[0] + d[1] + d[2] + d[3] + d[4] + "0000" + d[5]
        }
        let eleven = String(ns) + body
        let computed = checkDigit(eleven)
        if let check, String(check) != computed { return nil }
        return eleven + computed
    }

    /// GS1 mod-10 check digit for the given digits (without the check digit).
    static func checkDigit(_ digits: String) -> String {
        let nums = digits.compactMap(\.wholeNumberValue)
        var sum = 0
        for (i, n) in nums.reversed().enumerated() { sum += n * (i % 2 == 0 ? 3 : 1) }
        return String((10 - sum % 10) % 10)
    }
}

extension FoodEntry {
    /// Create a logged entry from a database product, one serving by default.
    static func from(product p: OFFProduct, date: Date, source: EntrySource, context: ModelContext) -> FoodEntry {
        var draft = SnackDraft(product: p)
        draft.meal = MealType.guess(for: date)
        return draft.makeEntry(date: date, source: source, context: context)
    }
}

/// A product waiting to be logged. Nothing is saved until `makeEntry` is called, so abandoning a scan
/// (closing the scanner, the app being killed) never leaves a stray entry in the day's totals.
struct SnackDraft: Identifiable {
    let id = UUID()
    var name: String
    var notes: String
    var barcode: String?
    var imageData: Data?
    var healthScore: Int?
    var healthNotes: String = ""
    /// One serving, exactly as read from the database or label.
    var ingredients: [AIIngredient]
    var servings: Double = 1
    var meal: MealType = .snack
    /// Shown on the card so you know how much to trust the numbers.
    var sourceLabel: String

    var servingGrams: Double { ingredients.reduce(0) { $0 + $1.grams } }
    var perServing: Nutrients {
        ingredients.reduce(.zero) { $0 + $1.per100g.nutrients.scaled($1.grams / 100) }
    }
    var totals: Nutrients { perServing.scaled(servings) }

    init(product p: OFFProduct) {
        name = p.name
        notes = p.brand.isEmpty ? "From Open Food Facts." : "\(p.brand) · from Open Food Facts."
        barcode = ProductCode.canonical(p.id)
        let portion = p.servingGrams == nil ? "100 g" : (p.servingText ?? "1 serving")
        ingredients = [AIIngredient(name: p.name, portion: portion, grams: p.servingGrams ?? 100, usdaQuery: "",
                                    per100g: AIPer100(p.per100), source: "Open Food Facts #\(p.id)")]
        sourceLabel = "Open Food Facts (community data)"
    }

    init(usda p: USDA.BrandedProduct) {
        name = p.name
        notes = p.brand.isEmpty ? "From USDA Branded Foods." : "\(p.brand) · from USDA Branded Foods."
        barcode = p.gtin
        let portion = p.servingGrams == nil ? "100 g" : (p.servingText ?? "1 serving")
        ingredients = [AIIngredient(name: p.name, portion: portion, grams: p.servingGrams ?? 100, usdaQuery: "",
                                    per100g: AIPer100(p.per100), source: "USDA Branded #\(p.fdcId) (manufacturer data)")]
        sourceLabel = "USDA Branded Foods (manufacturer data)"
    }

    /// Rebuild from a product remembered earlier; nil when that entry has no stored baseline.
    init?(remembered e: FoodEntry) {
        guard let data = e.productSnapshot,
              let ings = try? JSONDecoder().decode([AIIngredient].self, from: data), !ings.isEmpty else { return nil }
        name = e.name
        notes = e.aiNotes
        barcode = e.barcode
        imageData = e.imageData
        healthScore = e.healthScore
        healthNotes = e.healthNotes
        ingredients = ings
        sourceLabel = e.source == .label ? "Your earlier label scan" : "Remembered from your log"
    }

    @discardableResult
    func makeEntry(date: Date, source: EntrySource, context: ModelContext) -> FoodEntry {
        let entry = FoodEntry(date: date, name: name, source: source, meal: meal)
        entry.barcode = barcode
        entry.aiNotes = notes
        entry.imageData = imageData
        entry.healthScore = healthScore
        entry.healthNotes = healthNotes
        entry.servings = servings
        entry.productSnapshot = try? JSONEncoder().encode(ingredients)
        context.insert(entry)
        for (i, a) in ingredients.enumerated() {
            let ing = Ingredient(name: a.name, portion: a.portion, grams: a.grams, per100: a.per100g.nutrients, order: i)
            ing.usdaQuery = a.usdaQuery
            ing.source = a.source ?? ""
            context.insert(ing)
            entry.ingredients.append(ing)
        }
        return entry
    }
}
