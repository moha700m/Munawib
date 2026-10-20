import SwiftUI

@main
struct MunawibApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = AppStore()
    @State private var session = Session.shared
    @State private var language = LanguageManager.shared
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
                .environment(\.layoutDirection, language.direction)
                .environment(\.locale, language.locale)
                .id(language.lang)
                .tint(Theme.primary)
        }
    }
}

enum Screen: String, CaseIterable, Identifiable {
    case dashboard, home, roster, myShifts, requests, announcements, reports, hours, employees, events, alerts, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .dashboard: return L("لوحة رئيسة التمريض")
        case .home: return L("الرئيسية")
        case .roster: return L("جداول المناوبات")
        case .myShifts: return L("مناوباتي")
        case .requests: return L("الإجازات والتبديل")
        case .announcements: return L("الإعلانات")
        case .reports: return L("التقارير")
        case .hours: return L("الحضور والساعات")
        case .employees: return L("الموظفون")
        case .events: return L("الدورات والفعاليات")
        case .alerts: return L("الإرسال والتنبيهات")
        case .settings: return L("الإعدادات")
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
