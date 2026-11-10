import SwiftUI
import SwiftData

private enum ProfileRoute: Hashable {
    case name, ai, personal, preferences, nutrition, goals, reminders, weightHistory, rings
}

struct ProfileTab: View {
    @Bindable var profile: Profile
    @Environment(\.modelContext) private var context
    @State private var shareItems: [Any]?
    @State private var confirmReset = false
    @State private var exporting = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Profile").font(.system(size: 32, weight: .bold)).padding(.top, 8)

                    NavigationLink(value: ProfileRoute.name) {
                        HStack(spacing: 14) {
                            Image(systemName: "person.fill")
                                .font(.title3)
                                .frame(width: 52, height: 52)
                                .background(Theme.cardMuted, in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.name.isEmpty ? "Tap to set name" : profile.name).font(.title3.weight(.semibold))
                                Text(profile.username.isEmpty ? "and username" : "@\(profile.username)")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                        .foregroundStyle(Theme.ink)
                        .card()
                    }

                    SettingsGroup(title: "AI scanner") {
                        NavigationLink(value: ProfileRoute.ai) {
                            SettingsRow(icon: "sparkles", title: "AI settings & API key",
                                        detail: AISettings.apiKey == nil ? "Not set" : AISettings.model.title)
                        }
                    }

                    SettingsGroup(title: "Account") {
                        NavigationLink(value: ProfileRoute.personal) { SettingsRow(icon: "person.text.rectangle", title: "Personal details") }
                        RowDivider()
                        NavigationLink(value: ProfileRoute.preferences) { SettingsRow(icon: "gearshape", title: "Preferences") }
                    }

                    SettingsGroup(title: "Goals & Tracking") {
                        NavigationLink(value: ProfileRoute.nutrition) { SettingsRow(icon: "scope", title: "Edit nutrition goals") }
                        RowDivider()
                        NavigationLink(value: ProfileRoute.goals) { SettingsRow(icon: "flag", title: "Goals & current weight") }
                        RowDivider()
                        NavigationLink(value: ProfileRoute.reminders) { SettingsRow(icon: "bell", title: "Tracking reminders") }
                        RowDivider()
                        NavigationLink(value: ProfileRoute.weightHistory) { SettingsRow(icon: "clock.arrow.circlepath", title: "Weight history") }
                        RowDivider()
                        NavigationLink(value: ProfileRoute.rings) { SettingsRow(icon: "circle.dashed", title: "Ring colors explained") }
                    }

                    SettingsGroup(title: "Data") {
                        Button { exportPDF() } label: {
                            SettingsRow(icon: "square.and.arrow.up", title: "Export PDF summary report", detail: exporting ? "Preparing…" : nil)
                        }
                        RowDivider()
                        Button { exportCSV() } label: { SettingsRow(icon: "tablecells", title: "Export meals as CSV") }
                        RowDivider()
                        Button { confirmReset = true } label: {
                            SettingsRow(icon: "trash", title: "Delete all data", tint: Theme.bad, showsChevron: false)
                        }
                    }

                    Text("White Cheeked Gibbon 1.0 · Your data stays on this iPhone.")
                        .font(.caption).foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
            .background(AppBackground())
            .navigationDestination(for: ProfileRoute.self) { route in
                Group {
                    switch route {
                    case .name: NameEditor(profile: profile)
                    case .ai: AISettingsView()
                    case .personal: PersonalDetailsView(profile: profile)
                    case .preferences: PreferencesView(profile: profile)
                    case .nutrition: NutritionGoalsView(profile: profile)
                    case .goals: GoalsWeightView(profile: profile)
                    case .reminders: RemindersView()
                    case .weightHistory: WeightHistoryView(profile: profile)
                    case .rings: RingColorsView()
                    }
                }
                // Leave room for the floating tab bar.
                .contentMargins(.bottom, 110, for: .scrollContent)
            }
            .sheet(isPresented: Binding(get: { shareItems != nil }, set: { if !$0 { shareItems = nil } })) {
                ActivityView(items: shareItems ?? [])
            }
            .confirmationDialog("Delete everything?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Delete all data", role: .destructive) { resetAll() }
            } message: {
                Text("This permanently removes your profile, meals, weights, photos and workouts from this phone. Your API key stays in the Keychain.")
            }
        }
    }

    private func exportPDF() {
        exporting = true
        let foods = (try? context.fetch(FetchDescriptor<FoodEntry>())) ?? []
        let weights = (try? context.fetch(FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\.date)]))) ?? []
        let exercises = (try? context.fetch(FetchDescriptor<ExerciseEntry>())) ?? []
        if let url = Report.makePDF(profile: profile, foods: foods.filter { !$0.isTemplate }, weights: weights, exercises: exercises) {
            shareItems = [url]
        }
        exporting = false
    }

    private func exportCSV() {
        let foods = (try? context.fetch(FetchDescriptor<FoodEntry>(sortBy: [SortDescriptor(\.date)]))) ?? []
        if let url = Report.makeCSV(foods: foods.filter { !$0.isTemplate && $0.status == .ready }) {
            shareItems = [url]
        }
    }

    private func resetAll() {
        try? context.delete(model: Ingredient.self)
        try? context.delete(model: FoodEntry.self)
        try? context.delete(model: WaterEntry.self)
        try? context.delete(model: ExerciseEntry.self)
        try? context.delete(model: WeightEntry.self)
        try? context.delete(model: ProgressPhoto.self)
        try? context.delete(model: Profile.self)
        try? context.save()
    }
}

// MARK: - Name

private struct NameEditor: View {
    @Bindable var profile: Profile
    var body: some View {
        Form {
            TextField("Name", text: $profile.name).textContentType(.name)
            TextField("Username", text: $profile.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .navigationTitle("Name")
    }
}

// MARK: - AI

struct AISettingsView: View {
    @State private var key = AISettings.apiKey ?? ""
    @State private var usdaKey = USDA.hasPersonalKey ? USDA.apiKey : ""
    @State private var model = AISettings.model
    @State private var effort = AISettings.effort
    @State private var testing = false
    @State private var testResult: String?
    @State private var pasteProblem: String?

    var body: some View {
        Form {
            Section {
                // Saved the moment it changes, so it's written before the "Saved" row re-reads it.
                SecureField("sk-ant-…", text: Binding(get: { key }, set: { key = $0; AISettings.apiKey = $0 }))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
                Button("Paste from clipboard") {
                    if let s = clipboardText() { key = s; AISettings.apiKey = s }
                }
                savedRow(AISettings.apiKey, expectedPrefix: "sk-ant-")
                Link("Get a key at console.anthropic.com", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
            } header: {
                Text("Anthropic API key")
            } footer: {
                Text("Saved on this iPhone and remembered across app restarts and updates. Only sent to api.anthropic.com.")
            }

            Section {
                Picker("Model", selection: $model) {
                    ForEach(AIModel.allCases) { m in
                        VStack(alignment: .leading) {
                            Text(m.title)
                            Text(m.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                        .tag(m)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                .onChange(of: model) { _, v in AISettings.model = v }
            } header: {
                Text("Model")
            } footer: {
                Text("Haiku keeps scans nearly free, and USDA data supplies the nutrition numbers either way. If portion sizes look off, try Sonnet or Opus. Costs are rough per-photo estimates; your real spend is shown below.")
            }

            Section {
                SecureField("Free key (optional)", text: Binding(get: { usdaKey }, set: { usdaKey = $0; USDA.apiKey = $0 }))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
                Button("Paste from clipboard") {
                    if let s = clipboardText() { usdaKey = s; USDA.apiKey = s }
                }
                savedRow(USDA.hasPersonalKey ? USDA.apiKey : nil, expectedPrefix: nil)
                Link("Get a free key at api.data.gov", destination: URL(string: "https://api.data.gov/signup/")!)
            } header: {
                Text("USDA FoodData Central key")
            } footer: {
                Text("After the AI identifies ingredients and portions, the app swaps in USDA lab-measured nutrition for generic foods. Without a key it uses the shared demo key, which only allows a few lookups per hour; a free personal key allows 1,000 per hour.")
            }

            Section {
                Picker("Thinking effort", selection: $effort) {
                    ForEach(AIEffort.allCases) { Text($0.title).tag($0) }
                }
                .onChange(of: effort) { _, v in AISettings.effort = v }
            } footer: {
                Text("Higher effort lets the model reason longer about portions. High is the best balance; Extra high is slower and costs more.")
            }

            Section {
                let spend = Spend.thisMonth
                LabeledContent("This month", value: "\(Spend.format(spend.usd)) · \(spend.calls) AI requests")
            } header: {
                Text("Spending")
            } footer: {
                Text("Calculated from the token usage Anthropic reports for each request. Barcode, food database and USDA lookups are free.")
            }

            Section {
                Button {
                    Task { await test() }
                } label: {
                    HStack {
                        Text("Test connection")
                        Spacer()
                        if testing { ProgressView() }
                    }
                }
                .disabled(key.isEmpty || testing)
                if let testResult {
                    Text(testResult).font(.footnote).foregroundStyle(testResult.hasPrefix("✓") ? Theme.good : Theme.bad)
                }
            }
        }
        .navigationTitle("AI settings")
        .alert("Nothing to paste", isPresented: Binding(get: { pasteProblem != nil }, set: { if !$0 { pasteProblem = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(pasteProblem ?? "")
        }
    }

    /// The clipboard's text, or nil (with an explanation) when it's empty.
    private func clipboardText() -> String? {
        let s = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if s.isEmpty {
            pasteProblem = "The clipboard is empty. Copy your key first, then tap Paste again. In the Simulator, you can also long-press the key field and choose Paste."
            return nil
        }
        return s
    }

    /// Reads the stored value back so you can see the key really saved (only the last 4 characters are shown).
    @ViewBuilder
    private func savedRow(_ stored: String?, expectedPrefix: String?) -> some View {
        let _ = (key, usdaKey) // re-render when either field changes
        if let stored, !stored.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Label("Saved · ends in …\(stored.suffix(4))", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Theme.good)
                if let p = expectedPrefix, !stored.hasPrefix(p) {
                    Text("This doesn't look like an Anthropic key (they start with \(p)).")
                        .foregroundStyle(Theme.warn)
                }
            }
            .font(.footnote.weight(.medium))
        } else {
            Label("Not saved yet", systemImage: "circle.dashed")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func test() async {
        testing = true
        testResult = nil
        do {
            try await ClaudeClient.ping()
            testResult = "✓ Connected to \(model.title)"
        } catch {
            testResult = error.localizedDescription
        }
        testing = false
    }
}

// MARK: - Personal details

private struct PersonalDetailsView: View {
    @Bindable var profile: Profile
    @State private var showRegenerate = false

    var body: some View {
        Form {
            Section {
                Picker("Gender", selection: Binding(get: { profile.sex }, set: { profile.sex = $0; showRegenerate = true })) {
                    ForEach(Sex.allCases) { Text($0.title).tag($0) }
                }
                DatePicker("Date of birth", selection: Binding(get: { profile.birthDate }, set: { profile.birthDate = $0; showRegenerate = true }),
                           in: ...Date.now, displayedComponents: .date)
                HStack {
                    Text("Height")
                    Spacer()
                    if profile.units == .metric {
                        DecimalField(title: "cm", value: Binding(get: { profile.heightCm }, set: { profile.heightCm = $0; showRegenerate = true }), decimals: 0, suffix: "cm")
                            .frame(width: 100)
                    } else {
                        HeightImperialField(cm: Binding(get: { profile.heightCm }, set: { profile.heightCm = $0; showRegenerate = true }))
                    }
                }
                HStack {
                    Text("Current weight")
                    Spacer()
                    DecimalField(title: "0", value: weightBinding(\.currentWeightKg), decimals: 1, suffix: profile.units.weightUnit).frame(width: 120)
                }
                HStack {
                    Text("Goal weight")
                    Spacer()
                    DecimalField(title: "0", value: weightBinding(\.goalWeightKg), decimals: 1, suffix: profile.units.weightUnit).frame(width: 120)
                }
                Picker("Workouts per week", selection: Binding(get: { profile.activity }, set: { profile.activity = $0; showRegenerate = true })) {
                    ForEach(ActivityLevel.allCases) { Text($0.title).tag($0) }
                }
            }
            if showRegenerate {
                Section {
                    Button("Recalculate nutrition goals") {
                        profile.apply(Planner.makePlan(for: profile))
                        showRegenerate = false
                        Haptics.success()
                    }
                } footer: {
                    Text("Your details changed. Recalculate to update calories and macros.")
                }
            }
        }
        .navigationTitle("Personal details")
    }

    private func weightBinding(_ kp: ReferenceWritableKeyPath<Profile, Double>) -> Binding<Double> {
        Binding(get: { Fmt.weightValue(profile[keyPath: kp], profile.units) },
                set: { profile[keyPath: kp] = Fmt.kg(from: $0, profile.units); showRegenerate = true })
    }
}

private struct HeightImperialField: View {
    @Binding var cm: Double
    var body: some View {
        let total = Int((cm / 2.54).rounded())
        HStack(spacing: 4) {
            Picker("ft", selection: Binding(get: { total / 12 }, set: { cm = Double($0 * 12 + total % 12) * 2.54 })) {
                ForEach(3...8, id: \.self) { Text("\($0)′").tag($0) }
            }
            Picker("in", selection: Binding(get: { total % 12 }, set: { cm = Double((total / 12) * 12 + $0) * 2.54 })) {
                ForEach(0...11, id: \.self) { Text("\($0)″").tag($0) }
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
    }
}

// MARK: - Preferences

private struct PreferencesView: View {
    @Bindable var profile: Profile
    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: Binding(get: { profile.appearance }, set: { profile.appearance = $0 })) {
                    ForEach(Appearance.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section("Units") {
                Picker("Units", selection: Binding(get: { profile.units }, set: { profile.units = $0 })) {
                    ForEach(UnitSystem.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section {
                Toggle("Add burned calories", isOn: $profile.addBurnedCalories)
            } footer: {
                Text("Add calories from logged exercise back to your daily goal.")
            }
            Section {
                Toggle("Rollover calories", isOn: $profile.rolloverCalories)
            } footer: {
                Text("Carry up to 200 unused calories from yesterday into today's goal.")
            }
        }
        .navigationTitle("Preferences")
    }
}

// MARK: - Nutrition goals

private struct NutritionGoalsView: View {
    @Bindable var profile: Profile
    var body: some View {
        Form {
            Section {
                ForEach(NutrientKind.allCases) { k in
                    HStack {
                        NutrientIcon(kind: k).frame(width: 22)
                        Text(k == .calories ? "Calories" : "\(k.title)\(k.isLimit ? " limit" : "")")
                        Spacer()
                        DecimalField(title: "0", value: Binding(get: { profile.goals[k] }, set: { profile.setGoal(k, $0) }),
                                     decimals: 0, suffix: k.unit)
                            .frame(width: 120)
                    }
                }
                HStack {
                    Image(systemName: "drop.fill").foregroundStyle(Theme.water).frame(width: 22)
                    Text("Water")
                    Spacer()
                    DecimalField(title: "0", value: Binding(get: { Fmt.waterValue(profile.waterGoalMl, profile.units) },
                                                            set: { profile.waterGoalMl = profile.units == .imperial ? $0 * Fmt.mlPerOz : $0 }),
                                 decimals: 0, suffix: profile.units == .imperial ? "oz" : "ml")
                        .frame(width: 120)
                }
            } footer: {
                let macroKcal = profile.proteinGoal * 4 + profile.carbsGoal * 4 + profile.fatGoal * 9
                Text("Your macros add up to \(macroKcal.int) calories (protein 4, carbs 4, fat 9 cal per gram).")
            }
            Section {
                Button {
                    profile.apply(Planner.makePlan(for: profile))
                    Haptics.success()
                } label: {
                    Label("Auto-generate goals", systemImage: "sparkles")
                }
            } footer: {
                Text("Recalculates from your current weight, height, age, activity and goal.")
            }
        }
        .navigationTitle("Nutrition goals")
    }
}

// MARK: - Goals & weight

private struct GoalsWeightView: View {
    @Bindable var profile: Profile
    var body: some View {
        Form {
            Section("Goal") {
                Picker("Goal", selection: Binding(get: { profile.goal }, set: { profile.goal = $0 })) {
                    ForEach(WeightGoal.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section("Weight") {
                LabeledContent("Starting weight") {
                    DecimalField(title: "0", value: Binding(get: { Fmt.weightValue(profile.startWeightKg, profile.units) },
                                                            set: { profile.startWeightKg = Fmt.kg(from: $0, profile.units) }),
                                 decimals: 1, suffix: profile.units.weightUnit).frame(width: 120)
                }
                LabeledContent("Current weight", value: Fmt.weight(profile.currentWeightKg, profile.units))
                if profile.goal != .maintain {
                    LabeledContent("Goal weight") {
                        DecimalField(title: "0", value: Binding(get: { Fmt.weightValue(profile.goalWeightKg, profile.units) },
                                                                set: { profile.goalWeightKg = Fmt.kg(from: $0, profile.units) }),
                                     decimals: 1, suffix: profile.units.weightUnit).frame(width: 120)
                    }
                }
            }
            if profile.goal != .maintain {
                Section {
                    VStack(alignment: .leading) {
                        Text("\(Fmt.number(Fmt.weightValue(profile.weeklyRateKg, profile.units), decimals: 2)) \(profile.units.weightUnit) per week")
                            .font(.headline)
                        Slider(value: $profile.weeklyRateKg, in: 0.1...1.4, step: 0.05)
                    }
                    if let date = Planner.goalDate(current: profile.currentWeightKg, goal: profile.goalWeightKg, weeklyRateKg: profile.weeklyRateKg) {
                        LabeledContent("Projected goal date", value: Fmt.longDate(date))
                    }
                } header: { Text("Pace") }
            }
            Section {
                Button {
                    profile.apply(Planner.makePlan(for: profile))
                    Haptics.success()
                } label: { Label("Update calorie & macro goals to match", systemImage: "sparkles") }
            }
        }
        .navigationTitle("Goals & weight")
    }
}

// MARK: - Reminders

private struct RemindersView: View {
    @State private var enabled: [String: Bool] = [:]
    @State private var times: [String: Date] = [:]
    @State private var denied = false

    var body: some View {
        Form {
            if denied {
                Section {
                    Text("Notifications are turned off for White Cheeked Gibbon. Enable them in the Settings app.")
                        .foregroundStyle(Theme.bad)
                }
            }
            ForEach(Reminders.items) { item in
                Section {
                    Toggle(isOn: Binding(get: { enabled[item.id] ?? false }, set: { toggle(item, $0) })) {
                        Label(item.title, systemImage: item.icon)
                    }
                    if enabled[item.id] ?? false {
                        DatePicker("Time", selection: Binding(get: { times[item.id] ?? .now }, set: { setTime(item, $0) }),
                                   displayedComponents: .hourAndMinute)
                    }
                }
            }
        }
        .navigationTitle("Tracking reminders")
        .onAppear {
            for item in Reminders.items {
                enabled[item.id] = Reminders.isEnabled(item.id)
                let m = Reminders.minutes(item)
                times[item.id] = Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: .now)
            }
        }
    }

    private func toggle(_ item: Reminders.Item, _ on: Bool) {
        enabled[item.id] = on
        UserDefaults.standard.set(on, forKey: Reminders.enabledKey(item.id))
        Task {
            if on {
                let ok = await Reminders.requestAuthorization()
                denied = !ok
            }
            Reminders.reschedule(item)
        }
    }

    private func setTime(_ item: Reminders.Item, _ date: Date) {
        times[item.id] = date
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        UserDefaults.standard.set((c.hour ?? 0) * 60 + (c.minute ?? 0), forKey: Reminders.timeKey(item.id))
        Reminders.reschedule(item)
    }
}

// MARK: - Weight history

private struct WeightHistoryView: View {
    @Bindable var profile: Profile
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var app: AppState
    @Query(sort: \WeightEntry.date, order: .reverse) private var weights: [WeightEntry]

    var body: some View {
        List {
            ForEach(Array(weights.enumerated()), id: \.element.uuid) { i, w in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Fmt.weight(w.kg, profile.units)).font(.headline)
                        Text(Fmt.longDate(w.date)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if i + 1 < weights.count {
                        let diff = Fmt.weightValue(w.kg - weights[i + 1].kg, profile.units)
                        Text("\(Fmt.signed(diff)) \(profile.units.weightUnit)")
                            .font(.subheadline)
                            .foregroundStyle(abs(diff) < 0.05 ? Color.secondary : (diff < 0 ? Theme.good : Theme.fat))
                    }
                }
            }
            .onDelete { idx in
                idx.map { weights[$0] }.forEach(context.delete)
                let remaining = weights.enumerated().filter { !idx.contains($0.offset) }.map(\.element)
                profile.currentWeightKg = remaining.first?.kg ?? profile.startWeightKg
            }
        }
        .overlay {
            if weights.isEmpty { EmptyStateView(icon: "scalemass", title: "No weigh-ins", message: "Log your weight to start your history.") }
        }
        .navigationTitle("Weight history")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { app.present(.weight) } label: { Image(systemName: "plus") }
            }
        }
    }
}

// MARK: - Ring colors

private struct RingColorsView: View {
    var body: some View {
        List {
            Section {
                row(Theme.good, "Green", "You ate within 10% of your calorie goal.")
                row(Theme.warn, "Yellow", "You were 10–20% over or under your goal.")
                row(Theme.bad, "Red", "You were more than 20% over or under your goal.")
                HStack(spacing: 14) {
                    Circle().stroke(Color.secondary, style: StrokeStyle(lineWidth: 1.5, dash: [2.5, 3])).frame(width: 30, height: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Dashed").font(.headline)
                        Text("Nothing logged that day.").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Day rings on the Home screen")
            }
            Section {
                ForEach(NutrientKind.allCases) { k in
                    HStack(spacing: 14) {
                        RingView(progress: 0.7, color: k.color, lineWidth: 4) { NutrientIcon(kind: k, size: 10) }
                            .frame(width: 30, height: 30)
                        Text(k.title)
                        Spacer()
                        Text(k.isLimit ? "Stay under" : "Aim to reach").font(.caption).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Nutrient rings")
            } footer: {
                Text("Each ring fills as you eat toward that day's goal. The calorie ring turns red once you go over.")
            }
        }
        .navigationTitle("Ring colors")
    }

    private func row(_ color: Color, _ title: String, _ body: String) -> some View {
        HStack(spacing: 14) {
            Circle().stroke(color, lineWidth: 3).frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(body).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}
