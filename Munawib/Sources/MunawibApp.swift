import SwiftUI

@main
struct MunawibApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = AppStore()
    @State private var session = Session.shared
    init() {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-auth"), i + 1 < args.count {
            Demo.auth = args[i + 1]
            if Demo.auth == "created" { Session.shared.useOffline(); Demo.installRemote(); Session.shared.showHospitalCreated = true; let s = AppStore(); s.data = AppStore.seed(); _store = State(initialValue: s) }
            else { Session.shared.logout() }
        } else if args.contains("-demo") {
            Session.shared.useOffline()
            if args.contains("-hospitalInfo") { Demo.installRemote() }
            let s = AppStore(); s.data = AppStore.seed(); _store = State(initialValue: s)
        }
    }
    var body: some Scene {
        WindowGroup {
            ZStack {
                if session.isLoggedIn { RootView().transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 1.02)), removal: .opacity)) }
                else { AuthView().transition(.opacity) }
            }
            .animation(.easeInOut(duration: 0.35), value: session.isLoggedIn)
            .sheet(isPresented: Binding(get: { session.showHospitalCreated && session.isLoggedIn }, set: { session.showHospitalCreated = $0 })) { HospitalCreatedSheet() }
                .environment(store)
                .environment(session)
                .onAppear { session.store = store }
                .task { session.store = store; try? await session.refresh(); await session.uploadToken() }
                .onOpenURL { url in
                    if url.host == "server", let s = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "url" })?.value {
                        Task { if case .success = await APIClient.check(s) { ServerConfig.set(APIClient.normalize(s)); Haptics.success() } }
                    }
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
    case dashboard, home, roster, myShifts, requests, announcements, reports, hours, employees, events, alerts, settings
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
        case .settings: return "gearshape"
        }
    }
}

enum ActiveSheet: Identifiable {
    case addEmployee, importRoster, addHours, addEvent, autoFill
    var id: Int { hashValue }
}
