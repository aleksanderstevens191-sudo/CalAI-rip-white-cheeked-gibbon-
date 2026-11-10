import SwiftUI
import SwiftData

// MARK: - Describe food

struct DescribeFoodSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var analysis: AnalysisManager
    @State private var text = ""
    @FocusState private var focused: Bool

    var initialText: String = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Describe what you ate, including amounts and how it was cooked. The more detail, the more accurate.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $text)
                        .focused($focused)
                        .scrollContentBackground(.hidden)
                        .padding(10)
                    if text.isEmpty {
                        Text("e.g. 2 scrambled eggs cooked in butter, 1 slice of sourdough toast with avocado, and a latte with oat milk")
                            .foregroundStyle(.tertiary)
                            .padding(16)
                            .allowsHitTesting(false)
                    }
                }
                .frame(minHeight: 160)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(["Chipotle chicken bowl", "Big Mac and medium fries", "Greek yogurt with honey and granola", "Protein shake with banana"], id: \.self) { s in
                            Button(s) { text = s }.buttonStyle(PillButtonStyle())
                        }
                    }
                }
                .scrollIndicators(.hidden)

                Spacer()
            }
            .padding(20)
            .background(Theme.background.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                Button("Analyze") { submit() }
                    .buttonStyle(PrimaryButtonStyle(enabled: !trimmed.isEmpty))
                    .disabled(trimmed.isEmpty)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Theme.background)
            }
            .navigationTitle("Describe food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear {
                if text.isEmpty { text = initialText }
                focused = true
            }
        }
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func submit() {
        let entry = FoodEntry(date: app.logTimestamp, name: trimmed, source: .text, status: .analyzing)
        entry.userHint = trimmed
        context.insert(entry)
        try? context.save()
        analysis.run(entry, kind: .text(trimmed), context: context)
        app.tab = .home
        dismiss()
    }
}

// MARK: - Food database

struct FoodSearchSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var analysis: AnalysisManager
    @Query(filter: #Predicate<FoodEntry> { $0.isTemplate }, sort: \FoodEntry.createdAt, order: .reverse) private var saved: [FoodEntry]
    @Query(sort: \FoodEntry.date, order: .reverse) private var recent: [FoodEntry]

    @State private var query = ""
    @State private var results: [OFFProduct] = []
    @State private var usdaResults: [FDCFood] = []
    @State private var searching = false
    @State private var error: String?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            List {
                if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                    Section {
                        Button { estimateWithAI() } label: {
                            HStack(spacing: 12) {
                                IconBadge(systemName: "sparkles", size: 36)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Estimate “\(query)” with AI").font(.headline).foregroundStyle(Theme.ink)
                                    Text("Best for home-cooked or generic foods").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                if searching {
                    Section { HStack { Spacer(); ProgressView(); Spacer() } }
                } else if let error {
                    Section { Text(error).foregroundStyle(.secondary) }
                }

                if !usdaResults.isEmpty {
                    Section {
                        ForEach(usdaResults.prefix(8)) { f in
                            Button { logUSDA(f) } label: {
                                HStack(spacing: 12) {
                                    IconBadge(systemName: "checkmark.seal.fill", color: Theme.good, size: 36)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(f.description).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink).lineLimit(2)
                                        Text("\((f.calories ?? 0).int) cal · P \(Fmt.number(f.protein ?? 0))g · C \(Fmt.number(f.carbs ?? 0))g · F \(Fmt.number(f.fat ?? 0))g per 100 g")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "plus.circle.fill").foregroundStyle(Theme.ink)
                                }
                            }
                        }
                    } header: {
                        Text("Generic foods · USDA lab data")
                    }
                }
                if !results.isEmpty {
                    Section("Packaged products · Open Food Facts") {
                        ForEach(results) { p in
                            Button { log(p) } label: { ProductRow(product: p) }
                        }
                    }
                } else if query.isEmpty {
                    let recentFoods = uniqueRecent
                    if !saved.isEmpty {
                        Section("Saved") {
                            ForEach(saved.prefix(5)) { f in
                                Button { logCopy(f) } label: { simpleRow(f) }
                            }
                        }
                    }
                    if !recentFoods.isEmpty {
                        Section("Recent") {
                            ForEach(recentFoods) { f in
                                Button { logCopy(f) } label: { simpleRow(f) }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search foods and brands")
            .onSubmit(of: .search) { runSearch(immediate: true) }
            .onChange(of: query) { _, _ in runSearch(immediate: false) }
            .navigationTitle("Food database")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }

    private var uniqueRecent: [FoodEntry] {
        var seen = Set<String>()
        return recent.filter { f in
            guard !f.isTemplate, f.status == .ready else { return false }
            return seen.insert(f.name.lowercased()).inserted
        }
        .prefix(12).map { $0 }
    }

    private func simpleRow(_ f: FoodEntry) -> some View {
        HStack(spacing: 12) {
            FoodThumbnail(data: f.imageData, source: f.source, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(f.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                Text("\(f.totals.calories.int) cal · P \(f.totals.protein.int)g · C \(f.totals.carbs.int)g · F \(f.totals.fat.int)g")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "plus.circle.fill").foregroundStyle(Theme.ink)
        }
    }

    private func runSearch(immediate: Bool) {
        searchTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { results = []; usdaResults = []; error = nil; return }
        searchTask = Task {
            // Wait for typing to pause so the rate-limited USDA demo key isn't burned on every keystroke.
            if !immediate { try? await Task.sleep(nanoseconds: 900_000_000) }
            guard !Task.isCancelled else { return }
            searching = true
            error = nil
            async let usda = try? USDA.search(q, pageSize: 10)
            async let off = try? OpenFoodFacts.search(q)
            let (u, r) = await (usda, off)
            guard !Task.isCancelled else { return }
            usdaResults = u ?? []
            results = r ?? []
            if usdaResults.isEmpty && results.isEmpty {
                error = (u == nil && r == nil) ? "Search failed. Check your connection." : "Nothing found. Try the AI estimate above."
            }
            searching = false
        }
    }

    private func logUSDA(_ f: FDCFood) {
        let entry = FoodEntry(date: app.logTimestamp, name: f.description.components(separatedBy: ",").prefix(2).joined(separator: ","),
                              source: .database)
        entry.aiNotes = "USDA FoodData Central lab data. Set the amount you ate below."
        context.insert(entry)
        let ing = Ingredient(name: f.description, portion: "100 g", grams: 100, per100: f.per100(), order: 0)
        ing.source = "\(f.label): \(f.description)"
        context.insert(ing)
        entry.ingredients.append(ing)
        try? context.save()
        app.tab = .home
        app.present(.foodDetail(entry))
    }

    private func log(_ p: OFFProduct) {
        let entry = FoodEntry.from(product: p, date: app.logTimestamp, source: .database, context: context)
        try? context.save()
        app.tab = .home
        app.present(.foodDetail(entry))
    }

    private func logCopy(_ f: FoodEntry) {
        f.duplicate(into: context, date: app.logTimestamp, asTemplate: false)
        try? context.save()
        app.tab = .home
        app.showToast("Logged \(f.name)")
        dismiss()
    }

    private func estimateWithAI() {
        let q = query.trimmingCharacters(in: .whitespaces)
        let entry = FoodEntry(date: app.logTimestamp, name: q, source: .text, status: .analyzing)
        entry.userHint = q
        context.insert(entry)
        try? context.save()
        analysis.run(entry, kind: .text(q), context: context)
        app.tab = .home
        dismiss()
    }
}

private struct ProductRow: View {
    let product: OFFProduct
    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: product.imageURL) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                Theme.cardMuted.overlay(Image(systemName: "takeoutbag.and.cup.and.straw").foregroundStyle(.secondary))
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(product.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink).lineLimit(2)
                if !product.brand.isEmpty {
                    Text(product.brand).font(.caption).foregroundStyle(.secondary)
                }
                let grams = product.servingGrams ?? 100
                let n = product.per100.scaled(grams / 100)
                Text("\(n.calories.int) cal · \(product.servingGrams == nil ? "100 g" : (product.servingText ?? "1 serving"))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "plus.circle.fill").foregroundStyle(Theme.ink)
        }
    }
}

// MARK: - Saved foods

struct SavedFoodsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var app: AppState
    @Query(filter: #Predicate<FoodEntry> { $0.isTemplate }, sort: \FoodEntry.createdAt, order: .reverse) private var saved: [FoodEntry]

    var body: some View {
        NavigationStack {
            Group {
                if saved.isEmpty {
                    EmptyStateView(icon: "bookmark", title: "No saved foods",
                                   message: "Tap the bookmark on any logged meal to save it here for one-tap logging.")
                        .frame(maxHeight: .infinity, alignment: .top)
                        .padding(.top, 40)
                } else {
                    List {
                        ForEach(saved) { f in
                            Button {
                                f.duplicate(into: context, date: app.logTimestamp, asTemplate: false)
                                try? context.save()
                                app.tab = .home
                                app.showToast("Logged \(f.name)")
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    FoodThumbnail(data: f.imageData, source: f.source, size: 54)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(f.name).font(.headline).foregroundStyle(Theme.ink).lineLimit(2)
                                        Text("\(f.totals.calories.int) cal · P \(f.totals.protein.int)g · C \(f.totals.carbs.int)g · F \(f.totals.fat.int)g")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(Theme.ink)
                                }
                            }
                        }
                        .onDelete { idx in idx.map { saved[$0] }.forEach(context.delete) }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Saved foods")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}
