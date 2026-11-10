import SwiftUI
import SwiftData

struct HomeView: View {
    @Bindable var profile: Profile
    @EnvironmentObject private var app: AppState
    @Query(sort: \FoodEntry.date, order: .reverse) private var allFoods: [FoodEntry]
    @Query(sort: \WaterEntry.date, order: .reverse) private var waters: [WaterEntry]
    @Query(sort: \ExerciseEntry.date, order: .reverse) private var exercises: [ExerciseEntry]
    @Query(sort: \WeightEntry.date, order: .reverse) private var weights: [WeightEntry]

    private var foods: [FoodEntry] { allFoods.filter { !$0.isTemplate } }

    var body: some View {
        let stats = DayStats(day: app.selectedDay, profile: profile, foods: foods, waters: waters, exercises: exercises)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                WeekStrip(foods: foods, profile: profile)
                SummaryPager(stats: stats, profile: profile, latestWeightKg: Stats.latestWeight(weights, profile: profile))
                DayLogList(stats: stats, profile: profile)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
    }

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                Image("Gibbon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 38, height: 38)
                Text("White Cheeked Gibbon")
                    .font(.system(size: 22, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer()
            Button { app.present(.streak) } label: {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill").foregroundStyle(Theme.burn)
                    Text("\(Stats.streak(foods))").font(.headline).foregroundStyle(Theme.ink)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Theme.card, in: Capsule())
                .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
            }
            .accessibilityLabel("Streak")
        }
        .padding(.top, 8)
    }
}

// MARK: - Week strip

struct WeekStrip: View {
    @EnvironmentObject private var app: AppState
    let foods: [FoodEntry]
    let profile: Profile
    @State private var page = 0

    var body: some View {
        let byDay = Stats.caloriesByDay(foods)
        TabView(selection: $page) {
            ForEach(-52...0, id: \.self) { offset in
                HStack(spacing: 4) {
                    ForEach(days(offset), id: \.self) { d in
                        DayCell(day: d,
                                selected: Calendar.current.isDate(d, inSameDayAs: app.selectedDay),
                                status: status(for: d, eaten: byDay[d] ?? 0),
                                logged: byDay[d] != nil)
                            .onTapGesture {
                                Haptics.tap()
                                withAnimation(.snappy) { app.selectedDay = d }
                            }
                    }
                }
                .tag(offset)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: 74)
    }

    /// Today stays neutral while you're still under goal; the color is decided once the day is over.
    private func status(for day: Date, eaten: Double) -> RingStatus {
        let s = RingStatus.forDay(eaten: eaten, goal: profile.calorieGoal)
        if Calendar.current.isDateInToday(day), eaten > 0, eaten < profile.calorieGoal * 1.1, s != .onTrack {
            return .inProgress
        }
        return s
    }

    /// Seven days ending today, shifted by whole weeks.
    private func days(_ offset: Int) -> [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        return (0..<7).compactMap { cal.date(byAdding: .day, value: offset * 7 - 6 + $0, to: today) }
    }
}

private struct DayCell: View {
    let day: Date
    let selected: Bool
    let status: RingStatus
    let logged: Bool

    var body: some View {
        VStack(spacing: 6) {
            Text(day.formatted(.dateTime.weekday(.abbreviated)))
                .font(.caption.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? Theme.ink : .secondary)
            ZStack {
                Circle()
                    .stroke(logged ? status.color : Color.secondary.opacity(0.45),
                            style: StrokeStyle(lineWidth: logged ? 2.5 : 1.2, dash: logged ? [] : [2.5, 3]))
                Text(day.formatted(.dateTime.day()))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.ink)
            }
            .frame(width: 34, height: 34)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.card)
                    .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Streak sheet

struct StreakSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \FoodEntry.date, order: .reverse) private var foods: [FoodEntry]

    var body: some View {
        let days = Stats.loggedDays(foods)
        let streak = Stats.streak(foods)
        VStack(spacing: 20) {
            SheetHeader(title: "Streak") { dismiss() }
            ZStack {
                Image(systemName: "flame.fill")
                    .font(.system(size: 110))
                    .foregroundStyle(LinearGradient(colors: [Theme.warn, Theme.burn], startPoint: .top, endPoint: .bottom))
                Text("\(streak)")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .offset(y: 18)
            }
            Text(streak == 1 ? "1 day streak" : "\(streak) day streak").font(.title2.bold())
            HStack(spacing: 8) {
                ForEach(Calendar.current.days(back: 7), id: \.self) { d in
                    VStack(spacing: 6) {
                        Text(d.formatted(.dateTime.weekday(.narrow))).font(.caption).foregroundStyle(.secondary)
                        Image(systemName: days.contains(d) ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(days.contains(d) ? Theme.burn : Color.secondary.opacity(0.4))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .card()
            .padding(.horizontal, 20)
            Text("Log at least one meal every day to keep your streak alive. Longest streak: \(Stats.longestStreak(foods)) days.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            Spacer()
        }
        .background(Theme.background.ignoresSafeArea())
        .presentationDetents([.medium])
    }
}
