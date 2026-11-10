import SwiftUI
import SwiftData

struct FoodDetailView: View {
    @Bindable var entry: FoodEntry
    let profile: Profile

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var analysis: AnalysisManager
    @Query(filter: #Predicate<FoodEntry> { $0.isTemplate }) private var templates: [FoodEntry]

    @State private var editingIngredient: Ingredient?
    @State private var showFix = false
    @State private var showAddIngredient = false
    @State private var confirmDelete = false
    @State private var showServingsEditor = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    hero
                    VStack(alignment: .leading, spacing: 16) {
                        topRow
                        mealPicker
                        TextField("Meal name", text: Binding(get: { entry.name }, set: { new in
                            if new != entry.name { entry.nameEdited = true }
                            entry.name = new
                        }), axis: .vertical)
                            .font(.system(size: 26, weight: .bold))
                            .lineLimit(1...3)
                        servingsRow

                        if entry.status == .analyzing {
                            analyzingCard
                        } else {
                            if let err = entry.errorMessage {
                                errorBanner(err)
                            }
                            nutritionCards
                            if let score = entry.healthScore {
                                HealthScoreCard(score: Double(score), notes: entry.healthNotes.isEmpty ? nil : entry.healthNotes)
                            }
                            if !entry.aiNotes.isEmpty || entry.confidence != nil {
                                notesCard
                            }
                            ingredientsSection
                        }
                    }
                    .padding(20)
                    .background(Theme.background, in: UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28))
                    .offset(y: entry.imageData == nil ? 0 : -28)
                }
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: entry.imageData == nil ? [] : .top)
            .background(Theme.background.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) { bottomBar }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { toolbarIcon("chevron.down") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { logAgain() } label: { Label("Log again today", systemImage: "plus.square.on.square") }
                        Button { toggleSaved() } label: {
                            Label(isSaved ? "Remove from saved" : "Save food", systemImage: isSaved ? "bookmark.slash" : "bookmark")
                        }
                        Divider()
                        Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
                    } label: { toolbarIcon("ellipsis") }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .confirmationDialog("Delete this meal?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    context.delete(entry)
                    try? context.save()
                    dismiss()
                }
            }
            .sheet(item: $editingIngredient) { ing in
                IngredientEditor(ingredient: ing, onDelete: { delete(ing) })
            }
            .sheet(isPresented: $showFix) {
                FixResultsSheet(entry: entry)
            }
            .sheet(isPresented: $showAddIngredient) {
                AddIngredientSheet(entry: entry) { ing in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { editingIngredient = ing }
                }
            }
            .onDisappear { try? context.save() }
        }
    }

    // MARK: Header

    @ViewBuilder
    private var hero: some View {
        if let data = entry.imageData, let img = UIImage(data: data) {
            Color.clear
                .frame(height: 340)
                .overlay(Image(uiImage: img).resizable().scaledToFill())
                .clipped()
                .overlay(alignment: .top) {
                    LinearGradient(colors: [.black.opacity(0.45), .clear], startPoint: .top, endPoint: .bottom).frame(height: 120)
                }
        }
    }

    @ViewBuilder
    private func toolbarIcon(_ name: String) -> some View {
        let icon = Image(systemName: name).font(.system(size: 15, weight: .bold))
        if #available(iOS 26, *) {
            // iOS 26+ draws its own glass circle around toolbar items.
            icon.foregroundStyle(Theme.ink)
        } else {
            icon
                .foregroundStyle(entry.imageData == nil ? Theme.ink : .white)
                .frame(width: 34, height: 34)
                .background(entry.imageData == nil ? AnyShapeStyle(Theme.card) : AnyShapeStyle(.black.opacity(0.35)), in: Circle())
        }
    }

    private var isSaved: Bool { templates.contains { $0.sourceEntryID == entry.uuid } }

    private var topRow: some View {
        HStack(spacing: 8) {
            Button { toggleSaved() } label: {
                Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 36, height: 36)
                    .background(Theme.card, in: Circle())
            }
            .accessibilityLabel(isSaved ? "Remove from saved foods" : "Save food")
            DatePicker("", selection: $entry.date, displayedComponents: [.date, .hourAndMinute])
                .labelsHidden()
                .fixedSize()
            Spacer(minLength: 0)
        }
    }

    /// Segmented meal-type chips so every meal is filed under breakfast, lunch, dinner or snack.
    private var mealPicker: some View {
        HStack(spacing: 6) {
            ForEach(MealType.allCases) { m in
                Button {
                    Haptics.tap()
                    entry.meal = m
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: m.icon).font(.caption)
                        Text(m.title).font(.caption.weight(.semibold)).lineLimit(1)
                    }
                    .fixedSize()
                    .foregroundStyle(entry.meal == m ? Theme.inkInverse : Theme.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(entry.meal == m ? Theme.ink : Theme.card, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var servingsRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Servings").font(.subheadline.weight(.semibold))
                Text("\(entry.totalGrams.int) g total").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 0) {
                Button { adjustServings(-0.5) } label: { Image(systemName: "minus").frame(width: 40, height: 36) }
                Button { showServingsEditor = true } label: {
                    Text(Fmt.number(entry.servings, decimals: 2)).font(.headline).frame(minWidth: 44)
                }
                Button { adjustServings(0.5) } label: { Image(systemName: "plus").frame(width: 40, height: 36) }
            }
            .foregroundStyle(Theme.ink)
            .background(Theme.card, in: Capsule())
            .overlay(Capsule().stroke(Theme.border))
        }
        .alert("Servings", isPresented: $showServingsEditor) {
            TextField("Servings", value: $entry.servings, format: .number).keyboardType(.decimalPad)
            Button("Done") { entry.servings = max(0.05, entry.servings) }
        } message: {
            Text("How many servings of this did you eat? e.g. 0.5 if you ate half.")
        }
    }

    private func adjustServings(_ d: Double) {
        Haptics.tap()
        entry.servings = max(0.5, ((entry.servings + d) * 2).rounded() / 2)
    }

    // MARK: Nutrition

    private var nutritionCards: some View {
        let t = entry.totals
        return VStack(spacing: 10) {
            HStack(spacing: 14) {
                IconBadge(systemName: "flame.fill", size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Calories").font(.subheadline).foregroundStyle(.secondary)
                    Text("\(t.calories.int)").font(.system(size: 34, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                }
                Spacer()
                let pct = profile.calorieGoal > 0 ? t.calories / profile.calorieGoal : 0
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int((pct * 100).rounded()))%").font(.headline)
                    Text("of daily goal").font(.caption).foregroundStyle(.secondary)
                }
            }
            .card()

            HStack(spacing: 10) {
                ForEach(NutrientKind.macros) { k in miniCard(k, t[k]) }
            }
            HStack(spacing: 10) {
                ForEach(NutrientKind.micros) { k in miniCard(k, t[k]) }
            }
        }
    }

    private func miniCard(_ k: NutrientKind, _ v: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                NutrientIcon(kind: k, size: 11)
                Text(k.title).font(.caption).foregroundStyle(.secondary)
            }
            Text(k.format(v)).font(.system(size: 19, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 12)
    }

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "sparkles")
                Text("AI notes").font(.headline)
                Spacer()
                if let c = entry.confidence {
                    Text("\(Int((c * 100).rounded()))% confident")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background((c >= 0.75 ? Theme.good : (c >= 0.5 ? Theme.warn : Theme.bad)).opacity(0.18), in: Capsule())
                }
            }
            if !entry.aiNotes.isEmpty {
                Text(entry.aiNotes).font(.subheadline).foregroundStyle(.secondary)
            }
            let usdaCount = entry.ingredients.filter(\.isUSDA).count
            if entry.source != .label, entry.source != .barcode, !entry.ingredients.isEmpty {
                Label(usdaCount == entry.ingredients.count
                      ? "All \(usdaCount) ingredients use USDA lab data."
                      : "\(usdaCount) of \(entry.ingredients.count) ingredients use USDA lab data; the rest are AI estimates.",
                      systemImage: "checkmark.seal")
                    .font(.caption)
                    .foregroundStyle(usdaCount > 0 ? Theme.good : .secondary)
            }
            if !entry.userHint.isEmpty, entry.source != .text {
                Text("Your note: \(entry.userHint)").font(.caption).foregroundStyle(.secondary)
            }
            if entry.aiCostUSD > 0 {
                Label("AI cost for this meal: \(Spend.format(entry.aiCostUSD))", systemImage: "dollarsign.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: Ingredients

    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Ingredients").font(.title3.weight(.semibold))
                Spacer()
                Button { showAddIngredient = true } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(PillButtonStyle())
            }
            if entry.servings != 1 {
                Text("Amounts below are for 1 serving; totals above include \(Fmt.number(entry.servings, decimals: 2)) servings.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                let items = entry.sortedIngredients
                ForEach(Array(items.enumerated()), id: \.element.uuid) { i, ing in
                    Button { editingIngredient = ing } label: { ingredientRow(ing) }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button { editingIngredient = ing } label: { Label("Edit", systemImage: "pencil") }
                            Button(role: .destructive) { delete(ing) } label: { Label("Remove", systemImage: "trash") }
                        }
                    if i < items.count - 1 { Divider().padding(.leading, 16) }
                }
                if items.isEmpty {
                    Text("No ingredients yet. Tap Add to build this meal.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .padding(16)
                }
            }
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        }
    }

    private func ingredientRow(_ ing: Ingredient) -> some View {
        let t = ing.totals
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(ing.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                    if ing.isUSDA {
                        Text("USDA")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Theme.good.opacity(0.18), in: Capsule())
                            .foregroundStyle(Theme.good)
                    }
                }
                Text(portionLabel(ing))
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    ForEach(NutrientKind.macros) { k in
                        HStack(spacing: 2) {
                            NutrientIcon(kind: k, size: 9)
                            Text(k.format(t[k])).font(.caption2)
                        }
                    }
                }
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(t.calories.int) cal").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func portionLabel(_ ing: Ingredient) -> String {
        let grams = "\(ing.grams.int) g"
        let p = ing.portion.trimmingCharacters(in: .whitespaces)
        if p.isEmpty || p.replacingOccurrences(of: " ", with: "") == grams.replacingOccurrences(of: " ", with: "") {
            return grams
        }
        return "\(p) · \(grams)"
    }

    // MARK: States

    private var analyzingCard: some View {
        let p = analysis.progress[entry.uuid] ?? 0.05
        return VStack(spacing: 14) {
            RingView(progress: p, color: Theme.ink, lineWidth: 8) {
                Text("\(Int((p * 100).rounded()))%").font(.title3.bold())
            }
            .frame(width: 90, height: 90)
            Text("Analyzing your food…").font(.headline)
            Text("Identifying ingredients, estimating portions and looking up nutrition.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .card(padding: 24)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.bad)
            Text(message).font(.subheadline)
            Spacer()
            if entry.status == .failed {
                Button("Retry") { retry() }.buttonStyle(PillButtonStyle(filled: true))
            } else {
                Button { entry.errorMessage = nil } label: { Image(systemName: "xmark").foregroundStyle(.secondary) }
            }
        }
        .card(padding: 14)
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button { showFix = true } label: {
                Label("Fix results", systemImage: "sparkles")
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(entry.status == .analyzing)
            Button("Done") {
                try? context.save()
                dismiss()
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(Theme.background.opacity(0.95))
    }

    // MARK: Actions

    private func delete(_ ing: Ingredient) {
        entry.ingredients.removeAll { $0.uuid == ing.uuid }
        context.delete(ing)
        try? context.save()
    }

    private func toggleSaved() {
        Haptics.tap()
        if let t = templates.first(where: { $0.sourceEntryID == entry.uuid }) {
            context.delete(t)
            app.showToast("Removed from saved foods")
        } else {
            entry.duplicate(into: context, date: .now, asTemplate: true)
            app.showToast("Saved")
        }
        try? context.save()
    }

    private func logAgain() {
        entry.duplicate(into: context, date: .now, asTemplate: false)
        try? context.save()
        app.showToast("Logged again today")
    }

    private func retry() {
        let kind: AnalysisManager.Kind
        switch entry.source {
        case .label: kind = .label
        case .text: kind = .text(entry.userHint)
        default: kind = .photo
        }
        analysis.run(entry, kind: kind, context: context)
    }
}
