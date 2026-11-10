import SwiftUI
import SwiftData
import PhotosUI

// MARK: - Water

struct WaterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var app: AppState
    let profile: Profile
    @State private var amount: Double = 0
    @State private var unitsMl = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 24) {
            SheetHeader(title: "Log Water") { dismiss() }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                TextField("0", value: $amount, format: .number)
                    .keyboardType(.decimalPad)
                    .focused($focused)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .fixedSize()
                Button {
                    amount = unitsMl ? (amount / Fmt.mlPerOz).rounded() : (amount * Fmt.mlPerOz).rounded()
                    unitsMl.toggle()
                } label: {
                    HStack(spacing: 2) {
                        Text(unitsMl ? "ml" : "oz")
                        Image(systemName: "chevron.up.chevron.down").font(.caption2)
                    }
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 10) {
                quick("+1 Glass", unitsMl ? "250 ml" : "8 oz", icon: "cup.and.saucer.fill", unitsMl ? 250 : 8)
                quick("+1 Bottle", unitsMl ? "500 ml" : "16 oz", icon: "waterbottle.fill", unitsMl ? 500 : 16)
                quick("+1 Large", unitsMl ? "750 ml" : "24 oz", icon: "waterbottle", unitsMl ? 750 : 24)
            }
            .padding(.horizontal, 20)

            Text("Today: \(Fmt.water(todayMl, profile.units)) of \(Fmt.water(profile.waterGoalMl, profile.units))")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()
            Button("Log") {
                let ml = unitsMl ? amount : amount * Fmt.mlPerOz
                context.insert(WaterEntry(date: app.logTimestamp, ml: ml))
                Haptics.success()
                dismiss()
            }
            .buttonStyle(PrimaryButtonStyle(enabled: amount > 0))
            .disabled(amount <= 0)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .background(Theme.background.ignoresSafeArea())
        .onAppear {
            unitsMl = profile.units == .metric
            focused = true
        }
    }

    @Query(sort: \WaterEntry.date, order: .reverse) private var waters: [WaterEntry]
    private var todayMl: Double {
        waters.filter { Calendar.current.isDate($0.date, inSameDayAs: app.selectedDay) }.reduce(0) { $0 + $1.ml }
    }

    private func quick(_ title: String, _ detail: String, icon: String, _ value: Double) -> some View {
        Button {
            Haptics.tap()
            amount += value
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: icon).font(.title3).foregroundStyle(Theme.water)
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - Weight

struct LogWeightSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var app: AppState
    @Bindable var profile: Profile
    @Query(sort: \WeightEntry.date, order: .reverse) private var weights: [WeightEntry]

    @State private var value: Double = 0
    @State private var date = Date.now
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let last = weights.first {
                        Text("Last weigh-in: \(Fmt.shortDate(last.date)) · \(Fmt.weight(last.kg, profile.units))")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 18) {
                        stepper("minus") { value = max(0, ((value - 0.1) * 10).rounded() / 10) }
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            TextField("0", value: $value, format: .number.precision(.fractionLength(1)))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.center)
                                .font(.system(size: 58, weight: .bold, design: .rounded))
                                .frame(width: 170)
                            Text(profile.units.weightUnit).font(.title3.weight(.semibold)).foregroundStyle(.secondary)
                        }
                        stepper("plus") { value = ((value + 0.1) * 10).rounded() / 10 }
                    }
                    DatePicker("Date", selection: $date, in: ...Date.now)
                        .card(padding: 14)

                    PhotosPicker(selection: $photoItem, matching: .images) {
                        HStack {
                            if let photoData, let img = UIImage(data: photoData) {
                                Image(uiImage: img).resizable().scaledToFill().frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 10))
                                Text("Progress photo added").foregroundStyle(Theme.ink)
                            } else {
                                Image(systemName: "camera.fill").frame(width: 44, height: 44).background(Theme.cardMuted, in: RoundedRectangle(cornerRadius: 10))
                                Text("Add a progress photo (optional)").foregroundStyle(Theme.ink)
                            }
                            Spacer()
                        }
                        .card(padding: 12)
                    }
                    .onChange(of: photoItem) { _, item in
                        Task {
                            if let d = try? await item?.loadTransferable(type: Data.self), let img = UIImage(data: d) {
                                photoData = img.jpegForStorage()
                            }
                        }
                    }

                    if !weights.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("History").font(.headline)
                            ForEach(weights.prefix(30)) { w in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(Fmt.weight(w.kg, profile.units)).font(.subheadline.weight(.semibold))
                                        Text(Fmt.longDate(w.date)).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button(role: .destructive) { delete(w) } label: {
                                        Image(systemName: "trash").font(.footnote)
                                    }
                                    .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                                Divider()
                            }
                        }
                        .card()
                    }
                }
                .padding(20)
            }
            .background(Theme.background.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                Button("Save weight") { save() }
                    .buttonStyle(PrimaryButtonStyle(enabled: value > 0))
                    .disabled(value <= 0)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                    .background(Theme.background)
            }
            .navigationTitle("Log weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear {
                value = (Fmt.weightValue(Stats.latestWeight(weights, profile: profile), profile.units) * 10).rounded() / 10
            }
        }
    }

    private func stepper(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button { Haptics.tap(); action() } label: {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.ink)
                .frame(width: 44, height: 44)
                .background(Theme.card, in: Circle())
        }
    }

    private func save() {
        let kg = Fmt.kg(from: value, profile.units)
        context.insert(WeightEntry(date: date, kg: kg))
        if let photoData {
            context.insert(ProgressPhoto(date: date, imageData: photoData, weightKg: kg))
        }
        updateCurrentWeight(newest: weights.first.map { $0.date > date ? $0.kg : kg } ?? kg)
        try? context.save()
        Haptics.success()
        app.showToast("Weight logged")
        dismiss()
    }

    private func delete(_ w: WeightEntry) {
        context.delete(w)
        let remaining = weights.filter { $0.uuid != w.uuid }
        updateCurrentWeight(newest: remaining.first?.kg ?? profile.startWeightKg)
    }

    private func updateCurrentWeight(newest: Double) {
        profile.currentWeightKg = newest
    }
}

// MARK: - Exercise

struct ExerciseSheet: View {
    @Environment(\.dismiss) private var dismiss
    let profile: Profile

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(ExerciseKind.allCases) { kind in
                        NavigationLink(value: kind) {
                            HStack(spacing: 14) {
                                IconBadge(systemName: kind.icon, color: Theme.ink, size: 44)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(kind.title).font(.headline)
                                    Text(kind.subtitle).font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                            .foregroundStyle(Theme.ink)
                            .card()
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                .padding(20)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Log exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .navigationDestination(for: ExerciseKind.self) { kind in
                switch kind {
                case .run, .weights: IntensityExerciseView(kind: kind, profile: profile, onDone: { dismiss() })
                case .describe: DescribeExerciseView(profile: profile, onDone: { dismiss() })
                case .manual: ManualExerciseView(onDone: { dismiss() })
                }
            }
        }
    }
}

private struct IntensityExerciseView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var app: AppState
    let kind: ExerciseKind
    let profile: Profile
    let onDone: () -> Void
    @State private var intensity: Intensity = .medium
    @State private var minutes: Double = 30

    var body: some View {
        let kcal = intensity.met(for: kind) * profile.currentWeightKg * minutes / 60
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Set intensity").font(.headline)
                VStack(spacing: 10) {
                    ForEach(Intensity.allCases) { i in
                        Button { intensity = i; Haptics.tap() } label: {
                            ChoiceRow(title: i.title, subtitle: i.subtitle(for: kind), selected: intensity == i)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("Duration").font(.headline)
                HStack(spacing: 8) {
                    ForEach([15.0, 30, 60, 90], id: \.self) { m in
                        Button("\(Int(m)) mins") { minutes = m }
                            .buttonStyle(PillButtonStyle(filled: minutes == m))
                    }
                }
                HStack {
                    Text("Custom")
                    Spacer()
                    DecimalField(title: "Minutes", value: $minutes, decimals: 0, suffix: "min").frame(width: 120)
                }
                .card(padding: 14)

                HStack {
                    Image(systemName: "flame.fill").foregroundStyle(Theme.burn)
                    Text("Estimated burn").font(.headline)
                    Spacer()
                    Text("\(kcal.int) cal").font(.title3.bold())
                }
                .card()
            }
            .padding(20)
        }
        .background(Theme.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            Button("Add exercise") {
                context.insert(ExerciseEntry(date: app.logTimestamp, kind: kind, name: kind.title, minutes: minutes, intensity: intensity, calories: kcal.rounded()))
                Haptics.success()
                app.showToast("\(kcal.int) cal burned logged")
                onDone()
            }
            .buttonStyle(PrimaryButtonStyle(enabled: minutes > 0))
            .disabled(minutes <= 0)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .navigationTitle(kind.title)
    }
}

private struct DescribeExerciseView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var app: AppState
    let profile: Profile
    let onDone: () -> Void
    @State private var text = ""
    @State private var estimate: AIExerciseEstimate?
    @State private var working = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Describe your workout, including how long and how hard.").foregroundStyle(.secondary)
                TextField("e.g. 45 min hot yoga, or 5 mile bike ride at a moderate pace", text: $text, axis: .vertical)
                    .lineLimit(3...6)
                    .card(padding: 14)
                if let error { Text(error).font(.footnote).foregroundStyle(Theme.bad) }
                if let estimate {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(estimate.name).font(.headline)
                        Text("\(Int(estimate.minutes)) min").foregroundStyle(.secondary)
                        HStack {
                            Image(systemName: "flame.fill").foregroundStyle(Theme.burn)
                            Text("\(estimate.calories.int) cal").font(.title2.bold())
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
                }
            }
            .padding(20)
        }
        .background(Theme.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            Group {
                if let estimate {
                    Button("Add exercise") {
                        context.insert(ExerciseEntry(date: app.logTimestamp, kind: .describe, name: estimate.name,
                                                     minutes: estimate.minutes, intensity: .medium, calories: estimate.calories.rounded()))
                        Haptics.success()
                        onDone()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                } else {
                    Button {
                        Task { await run() }
                    } label: {
                        if working { ProgressView().tint(Theme.inkInverse) } else { Text("Estimate calories") }
                    }
                    .buttonStyle(PrimaryButtonStyle(enabled: !text.isEmpty && !working))
                    .disabled(text.isEmpty || working)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .navigationTitle("Describe exercise")
    }

    private func run() async {
        working = true
        error = nil
        do {
            estimate = try await FoodAI.estimateExercise(text, weightKg: profile.currentWeightKg)
        } catch {
            self.error = error.localizedDescription
        }
        working = false
    }
}

private struct ManualExerciseView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var app: AppState
    let onDone: () -> Void
    @State private var name = ""
    @State private var calories: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("Activity name (optional)", text: $name).card(padding: 14)
            HStack {
                Image(systemName: "flame.fill").foregroundStyle(Theme.burn)
                Text("Calories burned")
                Spacer()
                DecimalField(title: "0", value: $calories, decimals: 0, suffix: "cal").frame(width: 120)
            }
            .card(padding: 14)
            Spacer()
            Button("Add exercise") {
                context.insert(ExerciseEntry(date: app.logTimestamp, kind: .manual, name: name.isEmpty ? "Workout" : name,
                                             minutes: 0, intensity: .medium, calories: calories))
                Haptics.success()
                onDone()
            }
            .buttonStyle(PrimaryButtonStyle(enabled: calories > 0))
            .disabled(calories <= 0)
        }
        .padding(20)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Manual")
    }
}
