import SwiftUI

@main
struct MunawibApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = AppStore()
    @State private var session = Session.shared
    init() {
        if ProcessInfo.processInfo.arguments.contains("-demo") {
            Session.shared.useOffline()
            let s = AppStore(); s.data = AppStore.seed(); _store = State(initialValue: s)
        }
    }
    var body: some Scene {
        WindowGroup {
            Group {
                if session.isLoggedIn { RootView() } else { AuthView() }
            }
                .environment(store)
                .environment(session)
                .onAppear { session.store = store }
                .task { session.store = store; try? await session.refresh(); await session.uploadToken() }
                .onOpenURL { url in
                    if url.host == "join", let c = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "code" })?.value {
                        session.pendingInvite = c
                    }
                }
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "ar"))
                .tint(Theme.primary)
        }
    }
}

enum Screen: String, CaseIterable, Identifiable {
    case dashboard, home, roster, myShifts, requests, announcements, reports, hours, employees, events, alerts, portal, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .dashboard: return "لوحة رئيسة التمريض"
        case .home: return "الرئيسية"
        case .roster: return "جداول المناوبات"
        case .myShifts: return "مناوباتي"
        case .requests: return "الإجازات والتبديل"
        case .announcements: return "الإعلانات"
        case .reports: return "التقارير"
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
        case .dashboard: return "rectangle.3.group"
        case .home: return "square.grid.2x2"
        case .roster: return "calendar"
        case .myShifts: return "person.badge.clock"
        case .requests: return "arrow.left.arrow.right.circle"
        case .announcements: return "megaphone"
        case .reports: return "chart.bar.xaxis"
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
    case addEmployee, importRoster, addHours, addEvent, autoFill
    var id: Int { hashValue }
}
