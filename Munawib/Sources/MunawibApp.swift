import SwiftUI

@main
struct MunawibApp: App {
    @State private var store = AppStore()
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "ar"))
                .tint(Theme.primary)
        }
    }
}

enum Screen: String, CaseIterable, Identifiable {
    case home, roster, hours, employees, events, alerts, portal, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: return "الرئيسية"
        case .roster: return "جداول المناوبات"
        case .hours: return "الحضور والساعات"
        case .employees: return "الموظفون"
        case .events: return "الدورات والفعاليات"
        case .alerts: return "الإرسال والتنبيهات"
        case .portal: return "بوابة الموظف"
        case .settings: return "الإعدادات"
        }
    }
    var symbol: String {
        switch self {
        case .home: return "square.grid.2x2"
        case .roster: return "calendar"
        case .hours: return "clock"
        case .employees: return "person.2"
        case .events: return "book.pages"
        case .alerts: return "paperplane"
        case .portal: return "person.crop.circle.badge.checkmark"
        case .settings: return "gearshape"
        }
    }
}

enum ActiveSheet: Identifiable {
    case addEmployee, importRoster, addHours, addEvent
    var id: Int { hashValue }
}
