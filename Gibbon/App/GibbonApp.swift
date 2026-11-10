import SwiftUI
import SwiftData
import CryptoKit

@main
struct GibbonApp: App {
    @StateObject private var app = AppState()
    @StateObject private var analysis = AnalysisManager()

    init() {
        // Keys written in Config/Secrets.plist are saved on first launch, so they never need pasting.
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let dict = NSDictionary(contentsOf: url) as? [String: Any] else { return }
        // Accept keys whether they were pasted as values or in place of the labels.
        let labels: Set<String> = ["ANTHROPIC_API_KEY", "USDA_API_KEY"]
        let candidates = (Array(dict.keys) + dict.values.compactMap { $0 as? String })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !labels.contains($0) }
        let anthropic = candidates.first { $0.hasPrefix("sk-ant-") }
        let usda = candidates.first { !$0.hasPrefix("sk-ant-") && $0.count >= 20 && $0.allSatisfy { $0.isLetter || $0.isNumber } }
        // A key in the file replaces the saved one only when it changed, so a new key takes effect on the next build.
        if let anthropic, UserDefaults.standard.string(forKey: "secrets.anthropic.applied") != fingerprint(anthropic) {
            AISettings.apiKey = anthropic
            UserDefaults.standard.set(fingerprint(anthropic), forKey: "secrets.anthropic.applied")
        }
        if let usda, UserDefaults.standard.string(forKey: "secrets.usda.applied") != fingerprint(usda) {
            USDA.apiKey = usda
            UserDefaults.standard.set(fingerprint(usda), forKey: "secrets.usda.applied")
        }
    }

    let container: ModelContainer = {
        let schema = Schema([Profile.self, FoodEntry.self, Ingredient.self, WaterEntry.self,
                             ExerciseEntry.self, WeightEntry.self, ProgressPhoto.self])
        do {
            return try ModelContainer(for: schema)
        } catch {
            fatalError("Could not open the database: \(error)")
        }
    }()

    /// One-way hash, so the app can tell the key changed without storing it in plain text.
    private func fingerprint(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .environmentObject(analysis)
                .tint(Theme.ink)
        }
        .modelContainer(container)
    }
}

struct RootView: View {
    @Query(sort: \Profile.createdAt) private var profiles: [Profile]

    var body: some View {
        Group {
            if let profile = profiles.first(where: \.onboarded) {
                MainView(profile: profile)
                    .preferredColorScheme(profile.appearance.colorScheme)
            } else {
                OnboardingView()
            }
        }
        .animation(.easeInOut, value: profiles.first(where: \.onboarded) != nil)
    }
}
