import Foundation

enum AIModel: String, CaseIterable, Identifiable {
    case opus = "claude-opus-5-5"
    case sonnet = "claude-sonnet-5-5"
    case haiku = "claude-haiku-5-5"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .opus: "Claude Opus 5.5"
        case .sonnet: "Claude Sonnet 5.5"
        case .haiku: "Claude Haiku 5.5"
        }
    }
    var subtitle: String {
        switch self {
        case .opus: "Most accurate · ~6¢ per scan · ~$5–6/mo"
        case .sonnet: "Balanced · ~2–3¢ per scan · ~$2–3/mo"
        case .haiku: "Default · cheapest · ~0.2¢ per scan · ~$0.15/mo"
        }
    }

    /// Price per million tokens (input, output), standard rates.
    static func price(forModelID id: String) -> (input: Double, output: Double) {
        if id.contains("haiku") { return (0.10, 0.50) }
        if id.contains("sonnet") { return (2, 10) }
        if id.contains("fable") || id.contains("mythos") { return (10, 50) }
        if id.contains("opus-5-5") { return (4, 20) }
        return (5, 25) // other Opus versions (e.g. a refusal fallback model)
    }
    /// Server-side refusal fallback is available on Opus 5.5 and Sonnet 5.5, not Haiku.
    var supportsFallback: Bool { self != .haiku }
}

enum AIEffort: String, CaseIterable, Identifiable {
    case low, medium, high, xhigh
    var id: String { rawValue }
    var title: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        case .xhigh: "Extra high"
        }
    }
}

enum AISettings {
    private static let keyAccount = "anthropic-api-key"

    static var apiKey: String? {
        get {
            let k = Keychain.get(keyAccount)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (k?.isEmpty ?? true) ? nil : k
        }
        set {
            if let v = newValue?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
                Keychain.set(v, for: keyAccount)
            } else {
                Keychain.delete(keyAccount)
            }
        }
    }

    static var model: AIModel {
        // Haiku is the default because running cost is the point of this app; Opus/Sonnet are opt-in in AI settings.
        get { AIModel(rawValue: UserDefaults.standard.string(forKey: "ai.model") ?? "") ?? .haiku }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "ai.model") }
    }

    static var effort: AIEffort {
        get { AIEffort(rawValue: UserDefaults.standard.string(forKey: "ai.effort") ?? "") ?? .high }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "ai.effort") }
    }
}

enum AIError: LocalizedError {
    case missingKey
    case http(Int, String)
    case refusal
    case truncated
    case badResponse(String)
    case notFood(String)

    var errorDescription: String? {
        switch self {
        case .missingKey:
            "Add your Anthropic API key in Profile → AI settings to analyze food."
        case .http(let code, let message):
            code == 401 ? "Your API key was rejected. Check it in Profile → AI settings." : "AI request failed (\(code)): \(message)"
        case .refusal:
            "The AI declined to analyze this. Try another photo or describe the food instead."
        case .truncated:
            "The AI response was cut off. Please try again."
        case .badResponse(let s):
            "Unexpected AI response: \(s)"
        case .notFood(let s):
            s.isEmpty ? "No food was detected in this photo." : s
        }
    }
}

/// Tracks what the AI actually costs, from the token usage the API reports.
enum Spend {
    private static var monthKey: String {
        let c = Calendar.current.dateComponents([.year, .month], from: .now)
        return "\(c.year ?? 0)-\(c.month ?? 0)"
    }

    static func record(_ usd: Double) {
        let d = UserDefaults.standard
        d.set(d.double(forKey: "ai.spend.\(monthKey)") + usd, forKey: "ai.spend.\(monthKey)")
        d.set(d.integer(forKey: "ai.calls.\(monthKey)") + 1, forKey: "ai.calls.\(monthKey)")
    }

    static var thisMonth: (usd: Double, calls: Int) {
        let d = UserDefaults.standard
        return (d.double(forKey: "ai.spend.\(monthKey)"), d.integer(forKey: "ai.calls.\(monthKey)"))
    }

    static func format(_ usd: Double) -> String {
        usd < 0.10 ? String(format: "%.2f¢", usd * 100) : String(format: "$%.2f", usd)
    }
}

/// Collects the cost of every Claude request made inside `CostSink.$current.withValue(box) { … }`,
/// including requests that later fail, so a meal's AI cost covers retries and add-with-AI lookups.
final class CostBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Double = 0
    func add(_ usd: Double) { lock.lock(); value += usd; lock.unlock() }
    var total: Double { lock.lock(); defer { lock.unlock() }; return value }
}

enum CostSink {
    @TaskLocal static var current: CostBox?
}

/// Minimal Messages API client over raw HTTP (there is no official Swift SDK).
enum ClaudeClient {
    struct Reply {
        let data: Data
        let costUSD: Double
    }

    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    /// Sends one user turn and returns the model's JSON text, constrained to `schema` via structured outputs.
    static func structured(system: String,
                           content: [[String: Any]],
                           schema: [String: Any],
                           model: AIModel = AISettings.model,
                           effort: AIEffort = AISettings.effort,
                           maxTokens: Int = 16000) async throws -> Reply {
        guard let key = AISettings.apiKey else { throw AIError.missingKey }

        var body: [String: Any] = [
            "model": model.rawValue,
            "max_tokens": maxTokens,
            "system": system,
            "messages": [["role": "user", "content": content]],
            "output_config": [
                "effort": effort.rawValue,
                "format": ["type": "json_schema", "schema": schema],
            ],
        ]
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        if model.supportsFallback {
            // If a safety classifier declines, the API retries on Anthropic's recommended fallback model.
            body["fallbacks"] = "default"
            request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        var attempt = 0
        while true {
            attempt += 1
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200 {
                return try extractText(data, requestedModel: model)
            }
            let retryable = status == 429 || status == 529 || status >= 500
            if retryable && attempt < 3 {
                try await Task.sleep(nanoseconds: UInt64(attempt) * 2_000_000_000)
                continue
            }
            throw AIError.http(status, errorMessage(data))
        }
    }

    /// Dollar cost of one usage record at a model's rates.
    private static func cost(of usage: [String: Any], modelID: String) -> Double {
        let price = AIModel.price(forModelID: modelID)
        let input = Double((usage["input_tokens"] as? Int ?? 0)
                           + (usage["cache_creation_input_tokens"] as? Int ?? 0))
            + Double(usage["cache_read_input_tokens"] as? Int ?? 0) * 0.1
        let output = Double(usage["output_tokens"] as? Int ?? 0)
        return (input * price.input + output * price.output) / 1_000_000
    }

    private static func extractText(_ data: Data, requestedModel: AIModel) throws -> Reply {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIError.badResponse("not JSON")
        }
        // Bill from the usage the API reports. When a server-side fallback ran, top-level usage covers only the
        // served attempt; usage.iterations lists every attempt (declined ones are "message", the served one
        // "fallback_message"), each priced at the model that ran it.
        let usage = json["usage"] as? [String: Any] ?? [:]
        let servedModel = json["model"] as? String ?? requestedModel.rawValue
        let cost: Double
        if let iterations = usage["iterations"] as? [[String: Any]], !iterations.isEmpty {
            cost = iterations.reduce(0) { sum, it in
                let type = it["type"] as? String ?? "message"
                let model = it["model"] as? String ?? (type == "fallback_message" ? servedModel : requestedModel.rawValue)
                return sum + Self.cost(of: it, modelID: model)
            }
        } else {
            cost = Self.cost(of: usage, modelID: servedModel)
        }
        Spend.record(cost)
        CostSink.current?.add(cost)

        let stop = json["stop_reason"] as? String
        if stop == "refusal" { throw AIError.refusal }
        if stop == "max_tokens" { throw AIError.truncated }
        let blocks = json["content"] as? [[String: Any]] ?? []
        let text = blocks.filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .joined()
        guard !text.isEmpty else { throw AIError.badResponse("no text content") }
        return Reply(data: Data(text.utf8), costUSD: cost)
    }

    private static func errorMessage(_ data: Data) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let err = json["error"] as? [String: Any],
           let msg = err["message"] as? String {
            return msg
        }
        return String(data: data, encoding: .utf8)?.prefix(200).description ?? "unknown error"
    }

    /// Cheap request used by the "Test connection" button.
    static func ping() async throws {
        let schema: [String: Any] = [
            "type": "object",
            "properties": ["ok": ["type": "boolean"]],
            "required": ["ok"],
            "additionalProperties": false,
        ]
        _ = try await structured(system: "Reply with ok = true.",
                                 content: [["type": "text", "text": "ping"]],
                                 schema: schema,
                                 effort: .low,
                                 maxTokens: 2000)
    }
}
