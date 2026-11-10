import SwiftUI
import SwiftData

/// Edit one ingredient. Changing grams rescales all nutrients; editing a nutrient total updates that nutrient's density.
struct IngredientEditor: View {
    @Bindable var ingredient: Ingredient
    var onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showUSDA = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $ingredient.name)
                    TextField("Portion (e.g. 1 cup)", text: $ingredient.portion)
                }

                Section {
                    HStack {
                        Text("Amount")
                        Spacer()
                        DecimalField(title: "0", value: $ingredient.grams, decimals: 0, suffix: "g")
                            .frame(width: 110)
                    }
                    HStack(spacing: 8) {
                        ForEach([("−10g", -10.0), ("+10g", 10.0)], id: \.0) { label, d in
                            Button(label) { ingredient.grams = max(0, ingredient.grams + d) }
                                .buttonStyle(PillButtonStyle())
                        }
                        Spacer()
                        ForEach([("½×", 0.5), ("1.5×", 1.5), ("2×", 2.0)], id: \.0) { label, f in
                            Button(label) { ingredient.grams = (ingredient.grams * f).rounded() }
                                .buttonStyle(PillButtonStyle())
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                } header: {
                    Text("Amount")
                } footer: {
                    Text("Changing the amount rescales every nutrient below.")
                }

                Section {
                    ForEach(NutrientKind.allCases) { k in
                        HStack {
                            NutrientIcon(kind: k, size: 13).frame(width: 20)
                            Text(k.title)
                            Spacer()
                            DecimalField(title: "0", value: total(k), decimals: k == .calories || k == .sodium ? 0 : 1, suffix: k.unit)
                                .frame(width: 120)
                        }
                    }
                } header: {
                    Text("Nutrition for \(ingredient.grams.int) g")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Per 100 g: \(ingredient.kcal100.int) cal · P \(Fmt.number(ingredient.protein100)) g · C \(Fmt.number(ingredient.carbs100)) g · F \(Fmt.number(ingredient.fat100)) g")
                        Text("Source: \(ingredient.source.isEmpty ? "AI estimate" : ingredient.source)")
                    }
                }

                Section {
                    Button {
                        showUSDA = true
                    } label: {
                        Label("Match to USDA lab data", systemImage: "checkmark.seal")
                    }
                } footer: {
                    Text("Pick the exact USDA food (e.g. cooked vs raw) to use lab-measured nutrition for this ingredient.")
                }

                Section {
                    Button("Remove ingredient", role: .destructive) {
                        dismiss()
                        onDelete()
                    }
                }
            }
            .navigationTitle("Edit ingredient")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onChange(of: ingredient.grams) { _, new in
                // Keep a purely gram-based portion label in sync with the amount.
                if ingredient.portion.isEmpty || ingredient.portion.range(of: #"^\s*\d+(\.\d+)?\s*g\s*$"#, options: .regularExpression) != nil {
                    ingredient.portion = "\(Int(new.rounded())) g"
                }
            }
            .sheet(isPresented: $showUSDA) {
                USDAPickerSheet(initialQuery: ingredient.usdaQuery.isEmpty ? ingredient.name : ingredient.usdaQuery) { food in
                    ingredient.per100 = food.per100(fallback: ingredient.per100)
                    ingredient.source = "\(food.label): \(food.description)\(USDA.chosenByUserSuffix)"
                }
            }
        }
        .presentationDetents([.large])
    }

    private func total(_ k: NutrientKind) -> Binding<Double> {
        Binding(get: { ingredient.totals[k] },
                set: { newValue in
                    guard abs(newValue - ingredient.totals[k]) > 0.05 else { return }
                    ingredient.setTotal(k, newValue)
                    ingredient.source = "Edited by you"
                })
    }
}

/// Search USDA FoodData Central and pick the exact generic food.
struct USDAPickerSheet: View {
    let initialQuery: String
    var onPick: (FDCFood) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [FDCFood] = []
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                if loading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if let error {
                    Text(error).foregroundStyle(.secondary)
                }
                ForEach(results) { f in
                    Button {
                        onPick(f)
                        Haptics.success()
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(f.description).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                            Text("Per 100 g: \((f.calories ?? 0).int) cal · P \(Fmt.number(f.protein ?? 0)) · C \(Fmt.number(f.carbs ?? 0)) · F \(Fmt.number(f.fat ?? 0))")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(f.label).font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search USDA foods")
            .onSubmit(of: .search) { Task { await run() } }
            .navigationTitle("USDA match")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task {
                query = initialQuery
                await run()
            }
        }
    }

    private func run() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        loading = true
        error = nil
        do {
            results = try await USDA.search(q, pageSize: 25)
            if results.isEmpty { error = "No USDA matches. Try a simpler name, e.g. \"rice cooked\"." }
        } catch {
            self.error = USDA.hasPersonalKey
                ? "USDA search failed. Check your connection and try again."
                : "USDA search failed. The shared demo key is limited to a few searches per hour — add your free key in Profile → AI settings."
        }
        loading = false
    }
}

/// Add an ingredient to a meal, either by describing it to the AI or entering it by hand.
struct AddIngredientSheet: View {
    let entry: FoodEntry
    var onManual: (Ingredient) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var text = ""
    @State private var working = false
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Describe what to add, with the amount.").foregroundStyle(.secondary)
                TextField("e.g. 1 tbsp olive oil, 30 g parmesan", text: $text, axis: .vertical)
                    .lineLimit(2...4)
                    .focused($focused)
                    .card(padding: 14)
                if let error { Text(error).font(.footnote).foregroundStyle(Theme.bad) }
                Button {
                    Task { await addWithAI() }
                } label: {
                    if working { ProgressView().tint(Theme.inkInverse) } else { Label("Add with AI", systemImage: "sparkles") }
                }
                .buttonStyle(PrimaryButtonStyle(enabled: !text.isEmpty && !working))
                .disabled(text.isEmpty || working)

                Button("Enter nutrition manually") {
                    let ing = Ingredient(name: text.isEmpty ? "New ingredient" : text, portion: "", grams: 100, per100: .zero, order: 0)
                    entry.addIngredient(ing, context: context)
                    dismiss()
                    onManual(ing)
                }
                .buttonStyle(SecondaryButtonStyle())
                Spacer()
            }
            .padding(20)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Add ingredient")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
    }

    private func addWithAI() async {
        working = true
        error = nil
        let costs = CostBox()
        defer { entry.aiCostUSD += costs.total }
        do {
            let items = try await CostSink.$current.withValue(costs) { try await FoodAI.lookupIngredients(text) }
            for a in items {
                let ing = Ingredient(name: a.name, portion: a.portion, grams: max(0, a.grams), per100: a.per100g.nutrients, order: 0)
                ing.usdaQuery = a.usdaQuery
                ing.source = a.source ?? ""
                entry.addIngredient(ing, context: context)
            }
            try? context.save()
            Haptics.success()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        working = false
    }
}

/// Describe what's wrong and let the AI redo the analysis with that correction.
struct FixResultsSheet: View {
    let entry: FoodEntry
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var analysis: AnalysisManager
    @State private var text = ""
    @FocusState private var focused: Bool

    private let suggestions = [
        "It was cooked in butter",
        "Portion was about twice as big",
        "This is a half portion",
        "No sauce or dressing",
        "The drink is diet / zero sugar",
        "The meat is ground beef 80/20",
    ]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Tell the AI what it got wrong. It will re-check the photo and update every ingredient.")
                    .foregroundStyle(.secondary)
                TextField("e.g. that's brown rice not white, and there were 2 chicken thighs", text: $text, axis: .vertical)
                    .lineLimit(3...6)
                    .focused($focused)
                    .card(padding: 14)
                FlowLayout(spacing: 8) {
                    ForEach(suggestions, id: \.self) { s in
                        Button(s) { text = text.isEmpty ? s : text + ", " + s.lowercased() }
                            .buttonStyle(PillButtonStyle())
                    }
                }
                Spacer()
            }
            .padding(20)
            .background(Theme.background.ignoresSafeArea())
            // Pinned above the keyboard so it's always reachable.
            .safeAreaInset(edge: .bottom) {
                Button {
                    analysis.run(entry, kind: .fix(text), context: context)
                    dismiss()
                } label: {
                    Label("Update results", systemImage: "sparkles")
                }
                .buttonStyle(PrimaryButtonStyle(enabled: !text.trimmingCharacters(in: .whitespaces).isEmpty))
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Theme.background)
            }
            .navigationTitle("Fix results")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear { focused = true }
        }
    }
}

/// Simple wrapping layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0; y += rowH + spacing; rowH = 0
            }
            x += size.width + spacing
            rowH = max(rowH, size.height)
            maxX = max(maxX, x - spacing)
        }
        return CGSize(width: min(maxX, width), height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX; y += rowH + spacing; rowH = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
    }
}
