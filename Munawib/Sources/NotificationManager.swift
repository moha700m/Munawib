import Foundation
import UserNotifications

final class NotificationManager {
    static let shared = NotificationManager()
    private let center = UNUserNotificationCenter.current()

    func requestPermission() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func status() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func notifyNow(title: String, body: String) async {
        let c = UNMutableNotificationContent()
        c.title = title; c.body = body; c.sound = .default
        let trig = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: trig))
    }

    func notify(after seconds: TimeInterval, title: String, body: String) async {
        let c = UNMutableNotificationContent()
        c.title = title; c.body = body; c.sound = .default
        let trig = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: trig))
    }

    /// iOS keeps max 64 pending local notifications; schedule the nearest ones.
    @MainActor
    func reschedule(store: AppStore) async {
        center.removeAllPendingNotificationRequests()
        let cal = Calendar.current
        let s = store.data.settings
        let now = Date()
        var items: [(Date, String, String)] = []
        let me = s.loggedInEmployeeNumber
        for roster in store.data.rosters where roster.status == .approved {
            for entry in roster.entries {
                guard let emp = store.employee(entry.employeeID) else { continue }
                if let me, emp.employeeNumber != me { continue }
                for (dayKey, code) in entry.codes where code.isWorking {
                    guard let day = Int(dayKey), let hour = s.startHour(code) else { continue }
                    var comps = DateComponents(year: roster.year, month: roster.month, day: day)
                    comps.hour = hour
                    guard let start = cal.date(from: comps) else { continue }
                    let fire = start.addingTimeInterval(TimeInterval(-s.reminderMinutesBefore * 60))
                    if fire > now {
                        let who = me == nil ? "\(emp.name): " : ""
                        items.append((fire, L("تذكير بالمناوبة"), L("%1$@الشفت ال%2$@ يبدأ الساعة %3$@:00 (%4$@ ساعة)", "\(who)", "\(code.title)", "\(comps.hour!)", "\(s.shiftLength)")))
                    }
                }
            }
        }
        for ev in store.data.events {
            let fire = ev.date.addingTimeInterval(-3600)
            if fire > now { items.append((fire, L("فعالية قادمة"), "\(ev.title) — \(ev.location)")) }
        }
        items.sort { $0.0 < $1.0 }
        for (date, title, body) in items.prefix(60) {
            let c = UNMutableNotificationContent()
            c.title = title; c.body = body; c.sound = .default
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let trig = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: trig))
        }
        store.log(L("جدولة التنبيهات"), L("تمت جدولة %@ تنبيه على هذا الجهاز", "\(min(items.count, 60))"))
    }
}
