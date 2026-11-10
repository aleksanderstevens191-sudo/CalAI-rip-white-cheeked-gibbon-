import SwiftUI
import SwiftData

struct Badge: Identifiable {
    let id: String
    let title: String
    let detail: String
    let icon: String
    let earned: Bool
}

enum Badges {
    static func all(foods: [FoodEntry], waters: [WaterEntry], weights: [WeightEntry],
                    exercises: [ExerciseEntry], profile: Profile) -> [Badge] {
        let logged = foods.filter { !$0.isTemplate && $0.status == .ready }
        let longest = Stats.longestStreak(logged)
        let photoScans = logged.filter { $0.source == .photo }.count
        let byDay = Stats.nutrientsByDay(logged)
        let onTargetDays = byDay.values.filter { RingStatus.forDay(eaten: $0.calories, goal: profile.calorieGoal) == .onTrack }.count
        let proteinDays = byDay.values.filter { $0.protein >= profile.proteinGoal }.count
        var waterByDay: [Date: Double] = [:]
        for w in waters { waterByDay[Calendar.current.startOfDay(for: w.date), default: 0] += w.ml }
        let hydratedDays = waterByDay.values.filter { $0 >= profile.waterGoalMl }.count
        let healthyMeals = logged.filter { ($0.healthScore ?? 0) >= 8 }.count
        let latest = weights.max(by: { $0.date < $1.date })?.kg ?? profile.currentWeightKg
        let progressKg = profile.goal == .gain ? latest - profile.startWeightKg : profile.startWeightKg - latest
        let reachedGoal = profile.goal != .maintain && (profile.goal == .lose ? latest <= profile.goalWeightKg : latest >= profile.goalWeightKg)

        return [
            Badge(id: "first", title: "First Bite", detail: "Log your first meal", icon: "fork.knife", earned: !logged.isEmpty),
            Badge(id: "streak3", title: "Warming Up", detail: "Reach a 3-day streak", icon: "flame", earned: longest >= 3),
            Badge(id: "streak7", title: "One Week Strong", detail: "Reach a 7-day streak", icon: "flame.fill", earned: longest >= 7),
            Badge(id: "streak30", title: "Habit Formed", detail: "Reach a 30-day streak", icon: "calendar", earned: longest >= 30),
            Badge(id: "streak100", title: "Unstoppable", detail: "Reach a 100-day streak", icon: "crown.fill", earned: longest >= 100),
            Badge(id: "meals50", title: "Half Century", detail: "Log 50 meals", icon: "50.circle.fill", earned: logged.count >= 50),
            Badge(id: "meals250", title: "Food Historian", detail: "Log 250 meals", icon: "books.vertical.fill", earned: logged.count >= 250),
            Badge(id: "photo25", title: "Food Photographer", detail: "Scan 25 meals with the camera", icon: "camera.fill", earned: photoScans >= 25),
            Badge(id: "target7", title: "Bullseye", detail: "Hit your calorie target on 7 days", icon: "target", earned: onTargetDays >= 7),
            Badge(id: "protein", title: "Protein Pro", detail: "Hit your protein goal on 5 days", icon: "bolt.fill", earned: proteinDays >= 5),
            Badge(id: "hydrated", title: "Hydrated", detail: "Hit your water goal on 5 days", icon: "drop.fill", earned: hydratedDays >= 5),
            Badge(id: "healthy", title: "Clean Plate", detail: "Log 10 meals with a health score of 8+", icon: "leaf.fill", earned: healthyMeals >= 10),
            Badge(id: "mover", title: "Mover", detail: "Log 10 workouts", icon: "figure.run", earned: exercises.count >= 10),
            Badge(id: "weighin", title: "Weigh-in Regular", detail: "Log your weight 10 times", icon: "scalemass.fill", earned: weights.count >= 10),
            Badge(id: "progress", title: "First Milestone", detail: "Move 2.5 kg / 5 lb toward your goal", icon: "chart.line.uptrend.xyaxis", earned: profile.goal != .maintain && progressKg >= 2.27),
            Badge(id: "goal", title: "Goal Crusher", detail: "Reach your goal weight", icon: "trophy.fill", earned: reachedGoal),
        ]
    }
}

struct BadgesSheet: View {
    let profile: Profile
    @Environment(\.dismiss) private var dismiss
    @Query private var foods: [FoodEntry]
    @Query private var waters: [WaterEntry]
    @Query private var weights: [WeightEntry]
    @Query private var exercises: [ExerciseEntry]

    var body: some View {
        let badges = Badges.all(foods: foods, waters: waters, weights: weights, exercises: exercises, profile: profile)
        NavigationStack {
            ScrollView {
                Text("\(badges.filter(\.earned).count) of \(badges.count) earned")
                    .font(.subheadline).foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 16) {
                    ForEach(badges) { b in
                        VStack(spacing: 8) {
                            Image(systemName: b.icon)
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundStyle(b.earned ? .white : Color.secondary.opacity(0.5))
                                .frame(width: 70, height: 70)
                                .background(b.earned
                                            ? AnyShapeStyle(LinearGradient(colors: [Theme.warn, Theme.burn], startPoint: .top, endPoint: .bottom))
                                            : AnyShapeStyle(Theme.cardMuted), in: Circle())
                            Text(b.title).font(.caption.weight(.semibold)).multilineTextAlignment(.center)
                            Text(b.detail).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }
                        .opacity(b.earned ? 1 : 0.7)
                    }
                }
                .padding(20)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Badges")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}
