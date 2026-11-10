import Foundation
import UserNotifications

enum Reminders {
    struct Item: Identifiable {
        let id: String
        let title: String
        let body: String
        let icon: String
        let defaultMinutes: Int // minutes after midnight
    }

    static let items: [Item] = [
        Item(id: "breakfast", title: "Breakfast", body: "Snap your breakfast to keep your streak going.", icon: "sunrise.fill", defaultMinutes: 8 * 60 + 30),
        Item(id: "lunch", title: "Lunch", body: "Time to log lunch.", icon: "sun.max.fill", defaultMinutes: 12 * 60 + 30),
        Item(id: "dinner", title: "Dinner", body: "Don't forget to log dinner.", icon: "moon.stars.fill", defaultMinutes: 18 * 60 + 30),
        Item(id: "water", title: "Water", body: "Have you hit your water goal today?", icon: "drop.fill", defaultMinutes: 15 * 60),
        Item(id: "weigh", title: "Weigh-in", body: "Step on the scale and log your weight.", icon: "scalemass.fill", defaultMinutes: 7 * 60 + 30),
        Item(id: "summary", title: "End of day", body: "Check your totals and log anything you missed.", icon: "checklist", defaultMinutes: 21 * 60),
    ]

    static func enabledKey(_ id: String) -> String { "reminder.\(id).on" }
    static func timeKey(_ id: String) -> String { "reminder.\(id).minutes" }

    static func isEnabled(_ id: String) -> Bool { UserDefaults.standard.bool(forKey: enabledKey(id)) }
    static func minutes(_ item: Item) -> Int {
        let v = UserDefaults.standard.object(forKey: timeKey(item.id)) as? Int
        return v ?? item.defaultMinutes
    }

    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func reschedule(_ item: Item) {
        let center = UNUserNotificationCenter.current()
        let id = "gibbon.reminder.\(item.id)"
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard isEnabled(item.id) else { return }
        let content = UNMutableNotificationContent()
        content.title = item.title
        content.body = item.body
        content.sound = .default
        let m = minutes(item)
        var comps = DateComponents()
        comps.hour = m / 60
        comps.minute = m % 60
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}
