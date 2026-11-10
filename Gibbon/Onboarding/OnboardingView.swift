import SwiftUI
import SwiftData

private struct OnboardingDraft {
    var sex: Sex?
    var birthDate = Calendar.current.date(byAdding: .year, value: -25, to: .now) ?? .now
    var units: UnitSystem = Locale.current.measurementSystem == .us ? .imperial : .metric
    var heightCm: Double = 172.7
    var weightKg: Double = 72.6
    var activity: ActivityLevel?
    var goal: WeightGoal?
    var goalWeightKg: Double = 68
    var weeklyRateKg: Double = 0.45
    var apiKey = ""
}

private enum Step: Int, CaseIterable {
    case welcome, sex, birthday, body, workouts, goal, goalWeight, pace, ai, plan
}

struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @State private var draft = OnboardingDraft()
    @State private var step: Step = .welcome
    @State private var plan: Planner.Plan?
    @State private var forward = true

    private var steps: [Step] {
        Step.allCases.filter { s in
            if draft.goal == .maintain, s == .goalWeight || s == .pace { return false }
            return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if step != .welcome {
                header
            }
            ZStack {
                content
                    .id(step)
                    .transition(.asymmetric(
                        insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                        removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
            }
            .frame(maxHeight: .infinity, alignment: .top)

            Button(step == .welcome ? "Get started" : (step == .plan ? "Let's get started" : "Continue")) {
                advance()
            }
            .buttonStyle(PrimaryButtonStyle(enabled: canContinue))
            .disabled(!canContinue)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .background(Theme.background.ignoresSafeArea())
    }

    // MARK: Header

    private var header: some View {
        let index = steps.firstIndex(of: step) ?? 0
        return HStack(spacing: 14) {
            Button { back() } label: {
                Image(systemName: "arrow.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 40, height: 40)
                    .background(Theme.card, in: Circle())
            }
            ProgressBar(value: Double(index) / Double(steps.count - 1), color: Theme.ink, height: 4)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome: WelcomeStep()
        case .sex:
            StepScaffold(title: "Choose your gender", subtitle: "Used to calculate your metabolism.") {
                VStack(spacing: 12) {
                    ForEach(Sex.allCases) { s in
                        Button { draft.sex = s; Haptics.tap() } label: {
                            ChoiceRow(title: s.title, selected: draft.sex == s)
                        }.buttonStyle(.plain)
                    }
                }
            }
        case .birthday:
            StepScaffold(title: "When were you born?", subtitle: "Age changes how many calories you burn.") {
                DatePicker("", selection: $draft.birthDate,
                           in: (Calendar.current.date(byAdding: .year, value: -100, to: .now) ?? .distantPast)...(Calendar.current.date(byAdding: .year, value: -10, to: .now) ?? .now),
                           displayedComponents: .date)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
            }
        case .body:
            StepScaffold(title: "Height & weight", subtitle: "We'll use this to calibrate your plan.") {
                BodyPickers(units: $draft.units, heightCm: $draft.heightCm, weightKg: $draft.weightKg)
            }
        case .workouts:
            StepScaffold(title: "How many workouts do you do per week?", subtitle: "This sets your activity level.") {
                VStack(spacing: 12) {
                    ForEach(ActivityLevel.allCases) { a in
                        Button { draft.activity = a; Haptics.tap() } label: {
                            ChoiceRow(title: a.title, subtitle: a.subtitle, icon: a.icon, selected: draft.activity == a)
                        }.buttonStyle(.plain)
                    }
                }
            }
        case .goal:
            StepScaffold(title: "What is your goal?", subtitle: "We'll build your calorie target around it.") {
                VStack(spacing: 12) {
                    ForEach(WeightGoal.allCases) { g in
                        Button { selectGoal(g) } label: {
                            ChoiceRow(title: g.title, icon: g.icon, selected: draft.goal == g)
                        }.buttonStyle(.plain)
                    }
                }
            }
        case .goalWeight:
            StepScaffold(title: "What is your desired weight?", subtitle: draft.goal?.title ?? "") {
                GoalWeightPicker(units: draft.units, current: draft.weightKg, goalKg: $draft.goalWeightKg)
            }
        case .pace:
            StepScaffold(title: "How fast do you want to reach your goal?", subtitle: "\(draft.goal == .gain ? "Gain" : "Loss") speed per week") {
                PacePicker(units: draft.units, rateKg: $draft.weeklyRateKg)
            }
        case .ai:
            StepScaffold(title: "Connect the AI scanner", subtitle: "Photo scanning uses your own Anthropic API key, so there's no subscription. You can add or change it later in Profile.") {
                APIKeyStep(apiKey: $draft.apiKey)
            }
        case .plan:
            if let binding = Binding($plan) {
                PlanStep(plan: binding, draft: draft)
            }
        }
    }

    // MARK: Navigation

    private var canContinue: Bool {
        switch step {
        case .sex: draft.sex != nil
        case .workouts: draft.activity != nil
        case .goal: draft.goal != nil
        case .goalWeight:
            switch draft.goal {
            case .lose: draft.goalWeightKg < draft.weightKg
            case .gain: draft.goalWeightKg > draft.weightKg
            default: true
            }
        default: true
        }
    }

    private func selectGoal(_ g: WeightGoal) {
        Haptics.tap()
        draft.goal = g
        let factor: Double = g == .lose ? 0.92 : (g == .gain ? 1.06 : 1)
        draft.goalWeightKg = snapped(draft.weightKg * factor)
    }

    /// Round a weight to what the pickers show: whole pounds, or half kilograms.
    private func snapped(_ kg: Double) -> Double {
        let step = draft.units == .imperial ? 1.0 : 0.5
        return Fmt.kg(from: (Fmt.weightValue(kg, draft.units) / step).rounded() * step, draft.units)
    }

    private func advance() {
        Haptics.tap()
        if step == .plan { finish(); return }
        if step == .body {
            // The wheel shows whole numbers, so store exactly what was displayed.
            draft.weightKg = Fmt.kg(from: Fmt.weightValue(draft.weightKg, draft.units).rounded(), draft.units)
            draft.heightCm = draft.units == .imperial ? (draft.heightCm / 2.54).rounded() * 2.54 : draft.heightCm.rounded()
        }
        guard let i = steps.firstIndex(of: step), i + 1 < steps.count else { return }
        let next = steps[i + 1]
        if next == .plan {
            plan = Planner.makePlan(sex: draft.sex ?? .other, birthDate: draft.birthDate, heightCm: draft.heightCm,
                                    weightKg: draft.weightKg, activity: draft.activity ?? .moderate,
                                    goal: draft.goal ?? .maintain, weeklyRateKg: draft.weeklyRateKg)
        }
        forward = true
        withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) { step = next }
    }

    private func back() {
        guard let i = steps.firstIndex(of: step), i > 0 else { return }
        forward = false
        withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) { step = steps[i - 1] }
    }

    private func finish() {
        guard let plan else { return }
        let p = Profile()
        p.sex = draft.sex ?? .other
        p.birthDate = draft.birthDate
        p.heightCm = draft.heightCm
        p.startWeightKg = draft.weightKg
        p.currentWeightKg = draft.weightKg
        p.goal = draft.goal ?? .maintain
        p.goalWeightKg = p.goal == .maintain ? draft.weightKg : draft.goalWeightKg
        p.weeklyRateKg = draft.weeklyRateKg
        p.activity = draft.activity ?? .moderate
        p.units = draft.units
        p.apply(plan)
        p.onboarded = true
        context.insert(p)
        context.insert(WeightEntry(date: .now, kg: draft.weightKg))
        if !draft.apiKey.trimmingCharacters(in: .whitespaces).isEmpty {
            AISettings.apiKey = draft.apiKey
        }
        try? context.save()
        Haptics.success()
    }
}

// MARK: - Steps

private struct StepScaffold<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 30, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.body).foregroundStyle(.secondary)
                }
                content()
                    .padding(.top, 28)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

private struct WelcomeStep: View {
    private let mascot: CGFloat = 150

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 10)
            ZStack(alignment: .top) {
                // The gibbon peeks over the top edge of the card…
                Image("Gibbon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: mascot, height: mascot)
                card.padding(.top, mascot * 0.6)
                // …and grips it with both hands.
                HStack(spacing: 92) { hand(-12); hand(12) }
                    .padding(.top, mascot * 0.6 - 16)
            }
            VStack(spacing: 10) {
                Text("White Cheeked Gibbon")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("Calorie tracking\nmade easy")
                    .font(.system(size: 34, weight: .bold))
                    .multilineTextAlignment(.center)
                Text("Snap a photo of your meal and get calories, macros and every ingredient in seconds.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func hand(_ tilt: Double) -> some View {
        VStack(spacing: 0) {
            Capsule().fill(Color(white: 0.09)).frame(width: 30, height: 38)
        }
        .overlay(alignment: .bottom) {
            HStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { _ in Capsule().fill(Color(white: 0.16)).frame(width: 7, height: 14) }
            }
            .padding(.bottom, 3)
        }
        .rotationEffect(.degrees(tilt))
    }

    private var card: some View {
        ZStack {
                RoundedRectangle(cornerRadius: 40, style: .continuous)
                    .fill(Theme.card)
                    .frame(width: 260, height: 260)
                    .shadow(color: .black.opacity(0.08), radius: 30, y: 12)
                VStack(spacing: 16) {
                    RingView(progress: 0.68, color: Theme.ink, lineWidth: 12) {
                        VStack(spacing: 0) {
                            Text("1,240").font(.system(size: 30, weight: .bold, design: .rounded))
                            Text("Calories left").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 150, height: 150)
                    HStack(spacing: 16) {
                        ForEach(NutrientKind.macros) { k in
                            VStack(spacing: 6) {
                                RingView(progress: k == .protein ? 0.7 : (k == .carbs ? 0.5 : 0.4), color: k.color, lineWidth: 5) {
                                    NutrientIcon(kind: k, size: 11)
                                }
                                .frame(width: 40, height: 40)
                                Text(k.title).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(.top, 10)
        }
    }
}

private struct BodyPickers: View {
    @Binding var units: UnitSystem
    @Binding var heightCm: Double
    @Binding var weightKg: Double

    var body: some View {
        VStack(spacing: 24) {
            Picker("Units", selection: $units) {
                ForEach(UnitSystem.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 4) {
                    Text("Height").font(.headline)
                    if units == .imperial {
                        HStack(spacing: 0) {
                            Picker("Feet", selection: feet) {
                                ForEach(3...8, id: \.self) { Text("\($0) ft").tag($0) }
                            }
                            Picker("Inches", selection: inches) {
                                ForEach(0...11, id: \.self) { Text("\($0) in").tag($0) }
                            }
                        }
                    } else {
                        Picker("Centimeters", selection: centimeters) {
                            ForEach(120...230, id: \.self) { Text("\($0) cm").tag($0) }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                VStack(spacing: 4) {
                    Text("Weight").font(.headline)
                    Picker("Weight", selection: wholeWeight) {
                        if units == .imperial {
                            ForEach(70...500, id: \.self) { Text("\($0) lb").tag($0) }
                        } else {
                            ForEach(30...250, id: \.self) { Text("\($0) kg").tag($0) }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .pickerStyle(.wheel)
            .frame(height: 220)
        }
    }

    private var totalInches: Int { Int((heightCm / 2.54).rounded()) }
    private var feet: Binding<Int> {
        Binding(get: { totalInches / 12 }, set: { heightCm = Double($0 * 12 + totalInches % 12) * 2.54 })
    }
    private var inches: Binding<Int> {
        Binding(get: { totalInches % 12 }, set: { heightCm = Double((totalInches / 12) * 12 + $0) * 2.54 })
    }
    private var centimeters: Binding<Int> {
        Binding(get: { Int(heightCm.rounded()) }, set: { heightCm = Double($0) })
    }
    private var wholeWeight: Binding<Int> {
        Binding(get: { Int(Fmt.weightValue(weightKg, units).rounded()) },
                set: { weightKg = Fmt.kg(from: Double($0), units) })
    }
}

struct GoalWeightPicker: View {
    let units: UnitSystem
    let current: Double
    @Binding var goalKg: Double

    var body: some View {
        VStack(spacing: 28) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Fmt.number(Fmt.weightValue(goalKg, units), decimals: 1))
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text(units.weightUnit).font(.title2.weight(.semibold)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 16) {
                stepButton("minus") { nudge(-1) }
                Slider(value: displayValue, in: range, step: units == .imperial ? 1 : 0.5)
                stepButton("plus") { nudge(1) }
            }

            let diff = Fmt.weightValue(goalKg - current, units)
            Text(abs(diff) < 0.1 ? "Same as your current weight" :
                    "\(diff < 0 ? "Lose" : "Gain") \(Fmt.number(abs(diff), decimals: 1)) \(units.weightUnit)")
                .font(.headline)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Theme.cardMuted, in: Capsule())
                .frame(maxWidth: .infinity)
        }
    }

    private var range: ClosedRange<Double> { units == .imperial ? 70...450 : 30...200 }
    private var displayValue: Binding<Double> {
        Binding(get: { min(max(Fmt.weightValue(goalKg, units), range.lowerBound), range.upperBound) },
                set: { goalKg = Fmt.kg(from: $0, units) })
    }
    private func nudge(_ dir: Double) {
        let step = units == .imperial ? 1.0 : 0.5
        let v = (Fmt.weightValue(goalKg, units) / step).rounded() * step + dir * step
        goalKg = Fmt.kg(from: min(max(v, range.lowerBound), range.upperBound), units)
        Haptics.tap()
    }
    private func stepButton(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.ink)
                .frame(width: 44, height: 44)
                .background(Theme.card, in: Circle())
        }
    }
}

struct PacePicker: View {
    let units: UnitSystem
    @Binding var rateKg: Double

    var body: some View {
        VStack(spacing: 28) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Fmt.number(display.wrappedValue, decimals: units == .imperial ? 1 : 2))
                    .font(.system(size: 60, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text("\(units.weightUnit)/week").font(.title3.weight(.semibold)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            HStack {
                paceIcon("tortoise.fill", active: tier == 0)
                Spacer()
                paceIcon("hare.fill", active: tier == 1)
                Spacer()
                paceIcon("bolt.fill", active: tier == 2)
            }
            .padding(.horizontal, 8)

            Slider(value: display, in: units == .imperial ? 0.2...3.0 : 0.1...1.4,
                   step: units == .imperial ? 0.1 : 0.05)

            Text(tier == 1 ? "Recommended pace" : (tier == 0 ? "Slow and steady" : "Aggressive – harder to sustain"))
                .font(.headline)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Theme.cardMuted, in: Capsule())
                .frame(maxWidth: .infinity)
        }
    }

    private var tier: Int {
        let lb = rateKg * Fmt.lbPerKg
        if lb < 0.75 { return 0 }
        if lb <= 1.6 { return 1 }
        return 2
    }
    private var display: Binding<Double> {
        Binding(get: { (Fmt.weightValue(rateKg, units) * 100).rounded() / 100 },
                set: { rateKg = Fmt.kg(from: $0, units) })
    }
    private func paceIcon(_ name: String, active: Bool) -> some View {
        Image(systemName: name)
            .font(.system(size: 26, weight: .semibold))
            .foregroundStyle(active ? Theme.ink : Color.secondary.opacity(0.4))
            .scaleEffect(active ? 1.1 : 1)
            .animation(.spring, value: active)
    }
}

private struct APIKeyStep: View {
    @Binding var apiKey: String
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SecureField("sk-ant-…", text: $apiKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.body.monospaced())
                .padding(16)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            Button {
                if let s = UIPasteboard.general.string { apiKey = s.trimmingCharacters(in: .whitespacesAndNewlines) }
            } label: {
                Label("Paste from clipboard", systemImage: "doc.on.clipboard")
            }
            .buttonStyle(PillButtonStyle())

            VStack(alignment: .leading, spacing: 10) {
                Label("Create a key at console.anthropic.com → API Keys.", systemImage: "key.fill")
                Label("Stored only in this phone's Keychain.", systemImage: "lock.fill")
                Label("You pay Anthropic per scan: about 0.2¢ on the default model.", systemImage: "dollarsign.circle.fill")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.top, 8)

            Text("Skip this if you want — you can still log with barcodes and the food database.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
    }
}

private struct PlanStep: View {
    @Binding var plan: Planner.Plan
    let draft: OnboardingDraft
    @State private var editing: NutrientKind?
    @State private var editText = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image("Gibbon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 84, height: 84)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(Theme.good)
                            .background(Circle().fill(Theme.background))
                    }
                Text("Your custom plan is ready!")
                    .font(.system(size: 28, weight: .bold))
                    .multilineTextAlignment(.center)
                if let goal = draft.goal, goal != .maintain,
                   let date = Planner.goalDate(current: draft.weightKg, goal: draft.goalWeightKg, weeklyRateKg: draft.weeklyRateKg) {
                    Text("You should \(goal == .lose ? "lose" : "gain") \(Fmt.number(abs(Fmt.weightValue(draft.goalWeightKg - draft.weightKg, draft.units)), decimals: 1)) \(draft.units.weightUnit) by \(Fmt.longDate(date))")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Theme.card, in: Capsule())
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text("Daily recommendation").font(.headline)
                    Text("Tap any number to edit it.").font(.subheadline).foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        tile(.calories, plan.calories)
                        tile(.carbs, plan.carbs)
                        tile(.protein, plan.protein)
                        tile(.fat, plan.fat)
                    }
                }
                .card()

                VStack(alignment: .leading, spacing: 12) {
                    Text("How to reach your goals").font(.headline)
                    tip("camera.viewfinder", "Snap every meal — the AI breaks it into ingredients you can adjust.")
                    tip("flame.fill", "Stay within your daily calorie target.")
                    tip("chart.line.uptrend.xyaxis", "Weigh in weekly to track your trend.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .alert("Edit \(editing?.title.lowercased() ?? "")", isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            TextField("Value", text: $editText).keyboardType(.numberPad)
            Button("Save") {
                if let k = editing, let v = Double(editText) { set(k, v) }
                editing = nil
            }
            Button("Cancel", role: .cancel) { editing = nil }
        }
    }

    private func set(_ k: NutrientKind, _ v: Double) {
        switch k {
        case .calories: plan.calories = v
        case .protein: plan.protein = v
        case .carbs: plan.carbs = v
        case .fat: plan.fat = v
        default: break
        }
    }

    private func tile(_ k: NutrientKind, _ value: Double) -> some View {
        Button {
            editing = k
            editText = String(Int(value))
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    NutrientIcon(kind: k, size: 12)
                    Text(k.title).font(.subheadline.weight(.medium))
                }
                HStack {
                    RingView(progress: 0.75, color: k.color, lineWidth: 6) {
                        Text("\(Int(value))\(k.shortUnit)")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .minimumScaleFactor(0.6)
                    }
                    .frame(width: 70, height: 70)
                    Spacer()
                    Image(systemName: "pencil").foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(Theme.ink)
            .padding(14)
            .background(Theme.cardMuted, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func tip(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            IconBadge(systemName: icon, size: 32)
            Text(text).font(.subheadline)
        }
    }
}
