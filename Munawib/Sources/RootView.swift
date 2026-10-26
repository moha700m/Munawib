import SwiftUI

struct RootView: View {
    @Environment(AppStore.self) private var store
    @State private var screen: Screen = .home
    @State private var drawerOpen = false
    @State private var sheet: ActiveSheet?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .leading) {
            NavigationStack {
                VStack(spacing: 0) {
                    HeaderBar(drawerOpen: $drawerOpen, screen: $screen)
                    ScrollView {
                        VStack(alignment: .leading, spacing: Bento.gap) {
                            PageHeader(screen: screen, subtitle: subtitle, sheet: $sheet)
                            content
                        }
                        .id(screen)
                        .transition(.opacity.combined(with: .offset(y: 8)))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .frame(maxWidth: 900)
                        .frame(maxWidth: .infinity)
                    }
                    .refreshable { try? await Session.shared.refresh() }
                    .keyboardDone()
                    .background(Theme.background.onTapGesture { KeyboardHelper.dismiss() })
                    BentoTabBar(screen: $screen, tabs: tabs)
                }
                .background(Theme.background.ignoresSafeArea())
                .toolbar(.hidden, for: .navigationBar)
            }
            if drawerOpen {
                Color.black.opacity(0.35).ignoresSafeArea()
                    .onTapGesture { toggle(false) }
                    .accessibilityLabel(L("إغلاق القائمة"))
                SideDrawer(screen: $screen, close: { toggle(false) })
                    .transition(.move(edge: .leading))
            }
        }
        .sheet(item: $sheet) { s in
            switch s {
            case .addEmployee: EmployeeForm(employee: nil)
            case .importRoster: PhotoImportSheet()
            case .addHours: HoursForm()
            case .addEvent: EventForm()
            case .autoFill: AutoFillSheet()
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: screen)
        .sensoryFeedback(.selection, trigger: screen)
        .task {
            if let s = UserDefaults.standard.string(forKey: "screen"), let sc = Screen(rawValue: s) { screen = sc }
            else if Session.shared.me?.role == "head_nurse" { screen = .dashboard }
            await store.rescheduleNotifications()
        }
    }

    private func toggle(_ v: Bool) {
        withAnimation(Motion.entry(reduceMotion)) { drawerOpen = v }
    }

    /// Bottom tabs by role; everything else stays reachable from the side menu.
    private var tabs: [Screen] {
        let s = Session.shared
        if s.isHead && !s.offlineMode { return [.dashboard, .myShifts, .roster, .employees, .settings] }
        if s.isManager { return [.home, .myShifts, .roster, .employees, .settings] }
        return [.home, .myShifts, .roster, .requests, .settings]
    }

    /// Small context line beside the page title ("Pediatrics · 19 October", "16 shifts · 192 h").
    private var subtitle: String {
        if screen == .myShifts, let me = store.myEmployee {
            return L("%1$@ مناوبة · %2$@ ساعة", "\(store.rosterShiftCount(for: me.id))", "\(store.rosterHours(for: me.id))")
        }
        return "\(Dept.display(store.data.selectedDepartment)) · \(Fmt.date(Date(), "d MMMM"))"
    }

    @ViewBuilder private var content: some View {
        switch screen {
        case .dashboard: HeadNurseDashboard(screen: $screen, sheet: $sheet)
        case .home: HomeView(screen: $screen, sheet: $sheet)
        case .roster: RosterView(); CoverageWarnings()
        case .myShifts: MyShiftsView(screen: $screen)
        case .requests: RequestsView()
        case .announcements: AnnouncementsView()
        case .reports: ReportsView()
        case .hours: HoursView(sheet: $sheet)
        case .employees: EmployeesView(sheet: $sheet)
        case .events: EventsView(sheet: $sheet)
        case .alerts: AlertsView()
        case .settings: SettingsView()
        }
    }
}

struct HeaderBar: View {
    @Environment(AppStore.self) private var store
    @Binding var drawerOpen: Bool
    @Binding var screen: Screen

    var body: some View {
        HStack(spacing: 8) {
            Button { withAnimation(Motion.entry) { drawerOpen = true } } label: {
                Image(systemName: "line.3.horizontal").font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.border, lineWidth: 1))
            }
            .accessibilityLabel(L("القائمة"))
            Spacer(minLength: 4)
            Menu {
                ForEach(Session.shared.me?.role == "admin" || Session.shared.offlineMode ? store.data.settings.departments : [store.data.selectedDepartment], id: \.self) { d in
                    Button(Dept.display(d)) { store.selectDepartment(d) }
                }
            } label: {
                HStack(spacing: 6) {
                    RoleBadge(title: Session.shared.roleShortTitle)
                    Text(Dept.display(store.data.selectedDepartment))
                        .font(.subheadline.bold())
                        .lineLimit(1).truncationMode(.tail).minimumScaleFactor(0.8)
                    Image(systemName: "chevron.down").font(.caption.weight(.bold)).foregroundStyle(Theme.muted)
                }
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Theme.card, in: Capsule())
                .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
            }
            .layoutPriority(-1)
            Spacer(minLength: 4)
            Button { screen = .alerts } label: {
                Image(systemName: "bell").font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.border, lineWidth: 1))
                    .overlay(alignment: .topTrailing) {
                        if !store.data.settings.notificationsEnabled {
                            Circle().fill(Theme.coral).frame(width: 8, height: 8).padding(8)
                        }
                    }
            }
            .accessibilityLabel(L("التنبيهات"))
        }
        .tint(Theme.ink)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Theme.background)
    }
}

struct TrailingIconLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) { configuration.title; configuration.icon.font(.caption).foregroundStyle(.secondary) }
    }
}

struct PageHeader: View {
    let screen: Screen
    let subtitle: String
    @Binding var sheet: ActiveSheet?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(screen.title).font(.title.weight(.heavy)).foregroundStyle(Theme.ink)
                    .lineLimit(2).minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                Text(subtitle).font(.caption).foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.trailing).lineLimit(2)
            }
            if let err = Session.shared.lastError { Label(err, systemImage: "wifi.exclamationmark").font(.caption).foregroundStyle(Theme.coral) }
            if Session.shared.isHead && [Screen.roster, .employees].contains(screen) { HStack(spacing: 10) {
                Button { sheet = .addEmployee } label: { Label(L("إضافة موظف"), systemImage: "person.badge.plus").lineLimit(1).minimumScaleFactor(0.7) }
                    .buttonStyle(OutlineButtonStyle())
                Button { sheet = .importRoster } label: { Label(L("رفع جدول"), systemImage: "square.and.arrow.up").lineLimit(1).minimumScaleFactor(0.7) }
                    .buttonStyle(PrimaryButtonStyle())
                if screen == .roster {
                    Button { sheet = .autoFill } label: { Label(L("تعبئة"), systemImage: "wand.and.stars").lineLimit(1).minimumScaleFactor(0.7) }.buttonStyle(OutlineButtonStyle())
                }
            }
            .padding(.top, 2) }
        }
        .padding(.bottom, 2)
    }
}

/// Bottom tab bar: dark surface, hairline top border, amber active tab.
struct BentoTabBar: View {
    @Binding var screen: Screen
    let tabs: [Screen]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var selected: Screen? { tabs.first { screen.tabFamily.contains($0) } }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                let on = selected == tab
                Button {
                    Haptics.tap()
                    withAnimation(Motion.quick(reduceMotion)) { screen = tab }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: on ? tab.tabSymbolFilled : tab.tabSymbol)
                            .font(.system(size: 21, weight: on ? .semibold : .regular))
                            .frame(height: 24)
                        Text(tab.tabTitle).font(.caption2.weight(on ? .bold : .medium)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .foregroundStyle(on ? Theme.primary : Theme.muted)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.tabTitle)
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
        }
        .padding(.top, 8)
        .padding(.horizontal, 6)
        .background(Theme.card.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
    }
}

struct SideDrawer: View {
    @Environment(AppStore.self) private var store
    @Binding var screen: Screen
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                IconTile(symbol: "circle.circle", tint: Theme.onPrimary, size: 48)
                    .background(Theme.primary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading) {
                    Text(L("مِناوب")).font(.title2.bold())
                    Text(L("إدارة المناوبات")).font(.caption).opacity(0.7)
                }
                Spacer()
                Button(action: close) { Image(systemName: "xmark").font(.title3).frame(width: 44, height: 44) }
                    .accessibilityLabel(L("إغلاق"))
            }
            HStack {
                Image(systemName: "building.2").foregroundStyle(Theme.primary)
                VStack(alignment: .leading) {
                    Text(L("المستشفى")).font(.caption2).opacity(0.6)
                    Text(store.data.settings.hospital).font(.subheadline.bold())
                }
                Spacer()
            }
            .padding(12)
            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.vertical, 8)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Session.shared.isHead && !Session.shared.offlineMode ? [Screen.dashboard, .home, .roster, .myShifts, .requests, .announcements, .reports, .hours, .employees, .events, .alerts] : Session.shared.isManager ? [Screen.home, .roster, .myShifts, .requests, .announcements, .reports, .hours, .employees, .events, .alerts] : [Screen.myShifts, .roster, .requests, .announcements, .events]) { item(for: $0) }
                }
            }
            item(for: .settings)
        }
        .foregroundStyle(Theme.ink)
        .padding()
        .frame(width: 310)
        .frame(maxHeight: .infinity)
        .background(Theme.card.ignoresSafeArea())
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.border).frame(width: 1).ignoresSafeArea() }
    }

    private func item(for s: Screen) -> some View {
        Button { UISelectionFeedbackGenerator().selectionChanged(); screen = s; close() } label: {
            Label(s.title, systemImage: s.symbol)
                .font(.body.weight(screen == s ? .bold : .regular))
                .foregroundStyle(screen == s ? Theme.primary : Theme.ink)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .padding(.horizontal, 12)
                .background(screen == s ? Theme.primary.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(alignment: .leading) {
                    if screen == s { Capsule().fill(Theme.primary).frame(width: 4, height: 30) }
                }
        }
        .accessibilityAddTraits(screen == s ? .isSelected : [])
    }
}
