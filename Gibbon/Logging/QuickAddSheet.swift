import SwiftUI
import SwiftData

/// A compact "log this snack" card shown right after a barcode, QR code or remembered product is found.
/// It works on an unsaved draft: nothing is written until Log or Edit details is tapped.
struct QuickAddSheet: View {
    @State var draft: SnackDraft
    let date: Date
    /// Called with the saved entry (nil when cancelled); `openDetails` asks to show the full meal screen.
    var onFinish: (_ entry: FoodEntry?, _ openDetails: Bool) -> Void

    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<FoodEntry> { $0.isTemplate }) private var templates: [FoodEntry]
    @State private var saveForLater = false
    @State private var gramsText = ""
    @FocusState private var gramsFocused: Bool

    private var servingLabel: String {
        let p = (draft.ingredients.first?.portion ?? "").trimmingCharacters(in: .whitespaces)
        let grams = "\(draft.servingGrams.int) g"
        if p.isEmpty || p.replacingOccurrences(of: " ", with: "") == grams.replacingOccurrences(of: " ", with: "") {
            return grams
        }
        return "\(p) (\(grams))"
    }

    var body: some View {
        let t = draft.totals
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                FoodThumbnail(data: draft.imageData, source: .barcode, size: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(draft.name).font(.title3.weight(.bold)).lineLimit(2)
                    Text("1 serving = \(servingLabel)").font(.caption).foregroundStyle(.secondary)
                    Label(draft.sourceLabel, systemImage: "info.circle")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "flame.fill")
                Text("\(t.calories.int)").font(.system(size: 40, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text("cal").foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 10) {
                    ForEach(NutrientKind.macros) { k in
                        VStack(spacing: 2) {
                            NutrientIcon(kind: k, size: 11)
                            Text(k.format(t[k])).font(.caption.weight(.semibold))
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("How much?").font(.subheadline.weight(.semibold))
                HStack(spacing: 8) {
                    ForEach([(0.5, "½"), (1.0, "1"), (1.5, "1½"), (2.0, "2")], id: \.1) { s, label in
                        Button(label) { setServings(s) }
                            .buttonStyle(PillButtonStyle(filled: abs(draft.servings - s) < 0.001))
                    }
                    Spacer()
                    HStack(spacing: 2) {
                        TextField("g", text: $gramsText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .focused($gramsFocused)
                            .frame(width: 52)
                            .onChange(of: gramsText) { _, v in
                                guard gramsFocused, let g = Double(v), draft.servingGrams > 0 else { return }
                                draft.servings = max(0.01, g / draft.servingGrams)
                            }
                        Text("g").foregroundStyle(.secondary).fixedSize()
                    }
                    .fixedSize()
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(Theme.card, in: Capsule())
                    .overlay(Capsule().stroke(Theme.border))
                }
                .font(.subheadline)
            }

            HStack(spacing: 6) {
                ForEach(MealType.allCases) { m in
                    Button { draft.meal = m; Haptics.tap() } label: {
                        Text(m.title)
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .foregroundStyle(draft.meal == m ? Theme.inkInverse : Theme.ink)
                            .background(draft.meal == m ? Theme.ink : Theme.card, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            Toggle("Save to Saved foods", isOn: $saveForLater)
                .font(.subheadline)
                .disabled(alreadySaved)

            HStack(spacing: 12) {
                Button("Edit details") { finish(log: true, openDetails: true) }
                    .buttonStyle(SecondaryButtonStyle())
                Button("Log \(draft.meal.title.lowercased())") { finish(log: true, openDetails: false) }
                    .buttonStyle(PrimaryButtonStyle())
            }
            Button("Cancel", role: .cancel) { finish(log: false, openDetails: false) }
                .font(.subheadline)
                .frame(maxWidth: .infinity)
        }
        .padding(20)
        .presentationBackground(Theme.background)
        .presentationDetents([.height(570), .large])
        .interactiveDismissDisabled()
        .onAppear {
            gramsText = String((draft.servingGrams * draft.servings).int)
            saveForLater = alreadySaved
        }
        .onChange(of: draft.servings) { _, s in
            if !gramsFocused { gramsText = String((draft.servingGrams * s).int) }
        }
    }

    private var alreadySaved: Bool {
        guard let code = draft.barcode else { return false }
        return templates.contains { $0.barcode == code }
    }

    private func setServings(_ s: Double) {
        Haptics.tap()
        gramsFocused = false
        withAnimation(.snappy) { draft.servings = s }
    }

    private func finish(log: Bool, openDetails: Bool) {
        gramsFocused = false
        guard log else {
            onFinish(nil, false)
            return
        }
        let entry = draft.makeEntry(date: date, source: .barcode, context: context)
        if saveForLater && !alreadySaved {
            let template = entry.duplicate(into: context, date: .now, asTemplate: true)
            template.servings = 1
        }
        try? context.save()
        Haptics.success()
        onFinish(entry, openDetails)
    }
}
