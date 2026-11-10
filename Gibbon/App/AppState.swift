import SwiftUI
import SwiftData

enum MainTab: Hashable { case home, progress, profile }

enum ScanMode: String, CaseIterable, Identifiable {
    case food, barcode, label
    var id: String { rawValue }
    var title: String {
        switch self {
        case .food: "Scan food"
        case .barcode: "Barcode / QR"
        case .label: "Food label"
        }
    }
    var icon: String {
        switch self {
        case .food: "camera.viewfinder"
        case .barcode: "barcode.viewfinder"
        case .label: "doc.text.viewfinder"
        }
    }
}

enum SheetRoute: Identifiable {
    case foodDetail(FoodEntry)
    case water, weight, exercise, describe, search, saved, streak, badges

    var id: String {
        switch self {
        case .foodDetail(let e): "food-\(e.uuid)"
        case .water: "water"
        case .weight: "weight"
        case .exercise: "exercise"
        case .describe: "describe"
        case .search: "search"
        case .saved: "saved"
        case .streak: "streak"
        case .badges: "badges"
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var tab: MainTab = .home
    @Published var selectedDay = Calendar.current.startOfDay(for: .now)
    @Published var sheet: SheetRoute?
    @Published var scanner: ScanMode?
    @Published var toast: String?

    /// Present a sheet, dismissing whatever is currently up first.
    func present(_ route: SheetRoute) {
        if sheet != nil || scanner != nil {
            sheet = nil
            scanner = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.sheet = route }
        } else {
            sheet = route
        }
    }

    func openScanner(_ mode: ScanMode) {
        if sheet != nil {
            sheet = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.scanner = mode }
        } else {
            scanner = mode
        }
    }

    /// Timestamp for new logs: now if today is selected, otherwise the selected day at the current time.
    var logTimestamp: Date {
        let cal = Calendar.current
        if cal.isDateInToday(selectedDay) { return .now }
        let c = cal.dateComponents([.hour, .minute], from: .now)
        return cal.date(bySettingHour: c.hour ?? 12, minute: c.minute ?? 0, second: 0, of: selectedDay) ?? selectedDay
    }

    func showToast(_ text: String) {
        withAnimation(.spring) { toast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            if self.toast == text { withAnimation(.easeOut) { self.toast = nil } }
        }
    }
}

/// Runs AI analyses in the background and tracks a progress estimate for each entry.
@MainActor
final class AnalysisManager: ObservableObject {
    enum Kind {
        case photo, label
        case text(String)
        case fix(String)
    }

    @Published var progress: [UUID: Double] = [:]
    private var tickers: [UUID: Timer] = [:]

    func run(_ entry: FoodEntry, kind: Kind, context: ModelContext) {
        let id = entry.uuid
        let previousStatus = entry.status
        let snapshot = AIFoodResult(entry: entry)
        let image = entry.imageData
        let hint = entry.userHint
        entry.status = .analyzing
        entry.errorMessage = nil
        try? context.save()
        startTicker(id)

        Task {
            // Every paid request for this meal (including ones that end in an error) is added to its AI cost.
            let costs = CostBox()
            do {
                let result: AIFoodResult = try await CostSink.$current.withValue(costs) {
                    switch kind {
                    case .photo:
                        guard let image else { throw AIError.badResponse("missing photo") }
                        return try await FoodAI.analyzePhoto(image, hint: hint)
                    case .label:
                        guard let image else { throw AIError.badResponse("missing photo") }
                        return try await FoodAI.analyzeLabel(image)
                    case .text(let description):
                        return try await FoodAI.analyzeText(description)
                    case .fix(let correction):
                        return try await FoodAI.fix(snapshot, image: image, correction: correction)
                    }
                }
                stopTicker(id)
                guard !entry.isDeleted, entry.modelContext != nil else { return }
                entry.apply(result, context: context)
                entry.aiCostUSD += costs.total
                if case .label = kind, entry.barcode != nil, entry.productSnapshot == nil {
                    // Remember this product's label exactly as read, for future scans of its barcode.
                    entry.productSnapshot = try? JSONEncoder().encode(result.ingredients)
                }
                entry.status = .ready
                try? context.save()
                Haptics.success()
            } catch {
                stopTicker(id)
                guard !entry.isDeleted, entry.modelContext != nil else { return }
                entry.aiCostUSD += costs.total
                if case .fix = kind, previousStatus == .ready {
                    entry.status = .ready
                } else {
                    entry.status = .failed
                }
                entry.errorMessage = error.localizedDescription
                try? context.save()
                Haptics.error()
            }
        }
    }

    private func startTicker(_ id: UUID) {
        progress[id] = 0.03
        tickers[id]?.invalidate()
        tickers[id] = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let p = self.progress[id] else { return }
                // Ease toward 95% so the bar keeps moving without ever claiming to be done.
                self.progress[id] = p + (0.95 - p) * 0.02
            }
        }
    }

    private func stopTicker(_ id: UUID) {
        tickers[id]?.invalidate()
        tickers[id] = nil
        progress[id] = nil
    }
}
