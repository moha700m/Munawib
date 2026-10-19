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
                    Divider()
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            PageHeader(screen: screen, sheet: $sheet)
                            content
                        }
                        .id(screen)
                        .transition(.opacity.combined(with: .offset(y: 8)))
                        .padding()
                        .frame(maxWidth: 900)
                        .frame(maxWidth: .infinity)
                    }
                    .refreshable { try? await Session.shared.refresh() }
                    .keyboardDone()
                    .background(Theme.background.onTapGesture { KeyboardHelper.dismiss() })
                }
                .toolbar(.hidden, for: .navigationBar)
            }
            if drawerOpen {
                Color.black.opacity(0.35).ignoresSafeArea()
                    .onTapGesture { toggle(false) }
                    .accessibilityLabel("إغلاق القائمة")
                SideDrawer(screen: $screen, close: { toggle(false) })
                    .transition(.move(edge: .leading))
            }
        }
        .sheet(item: $sheet) { s in
            switch s {
            case .addEmployee: EmployeeForm(employee: nil)
            case .importRoster: ImportRosterSheet()
            case .addHours: HoursForm()
            case .addEvent: EventForm()
            case .autoFill: AutoFillSheet()
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: screen)
        .sensoryFeedback(.selection, trigger: screen)
        .task {
            if let s = UserDefaults.standard.string(forKey: "screen"), let sc = Screen(rawValue: s) { screen = sc }
            else if Session.shared.me?.role == "head_nurse" { screen = .dashboard } else if Session.shared.online && !Session.shared.isManager { screen = .myShifts }
            await store.rescheduleNotifications()
        }
    }

    private func toggle(_ v: Bool) {
        withAnimation(reduceMotion ? nil : .snappy) { drawerOpen = v }
    }

    @ViewBuilder private var content: some View {
        switch screen {
        case .dashboard: HeadNurseDashboard(screen: $screen, sheet: $sheet)
        case .home: HomeView(screen: $screen, sheet: $sheet)
        case .roster: RosterView(); CoverageWarnings()
        case .myShifts: MyShiftsView()
        case .requests: RequestsView()
        case .announcements: AnnouncementsView()
        case .reports: ReportsView()
        case .hours: HoursView(sheet: $sheet)
        case .employees: EmployeesView(sheet: $sheet)
        case .events: EventsView(sheet: $sheet)
        case .alerts: AlertsView()
        case .portal: PortalView()
        case .settings: SettingsView()
        }
    }
}

struct HeaderBar: View {
    @Environment(AppStore.self) private var store
    @Binding var drawerOpen: Bool
    @Binding var screen: Screen

    var body: some View {
        HStack(spacing: 12) {
            Button { withAnimation(.snappy) { drawerOpen = true } } label: {
                Image(systemName: "line.3.horizontal").font(.title3)
                    .frame(width: 44, height: 44)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
            }
            .accessibilityLabel("القائمة")
            RoleBadge(title: Session.shared.roleTitle)
            Spacer()
            Menu {
                ForEach(Session.shared.me?.role == "admin" || Session.shared.offlineMode ? store.data.settings.departments : [store.data.selectedDepartment], id: \.self) { d in
                    Button(d) { store.selectDepartment(d) }
                }
            } label: {
                Label(store.data.selectedDepartment, systemImage: "chevron.down")
                    .labelStyle(TrailingIconLabel())
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
            }
            Spacer()
            Button { screen = .alerts } label: {
                Image(systemName: "bell").font(.title3)
                    .frame(width: 44, height: 44)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
                    .overlay(alignment: .topLeading) {
                        if !store.data.settings.notificationsEnabled {
                            Circle().fill(.red).frame(width: 8, height: 8).offset(x: 9, y: 9)
                        }
                    }
            }
            .accessibilityLabel("التنبيهات")
            Button { screen = .portal } label: {
                Text(store.data.settings.loggedInEmployeeNumber == nil ? "تسجيل دخول" : "حسابي")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 14).frame(minHeight: 44)
                    .foregroundStyle(.white)
                    .background(Theme.primary, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .tint(.primary)
        .padding(.horizontal).padding(.vertical, 8)
        .background(Theme.card)
    }
}

struct TrailingIconLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) { configuration.title; configuration.icon.font(.caption).foregroundStyle(.secondary) }
    }
}

struct PageHeader: View {
    let screen: Screen
    @Binding var sheet: ActiveSheet?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Fmt.date(Date(), "EEEE، d MMMM yyyy")).font(.subheadline).foregroundStyle(.secondary)
            Text(screen.title).font(.largeTitle.bold())
            if let err = Session.shared.lastError { Label(err, systemImage: "wifi.exclamationmark").font(.caption).foregroundStyle(.orange) }
            Text(screen == .home ? "كل ما يخص مناوبات المستشفى في مكان واحد." : screen == .roster ? "عدّل أي خانة غير صحيحة قبل حفظ المراجعة أو الاعتماد." : "اسحب للأسفل للتحديث.")
                .font(.footnote).foregroundStyle(.secondary)
            if Session.shared.isHead && [Screen.home, .dashboard, .roster, .employees].contains(screen) { HStack(spacing: 12) {
                Button { sheet = .addEmployee } label: { Label("إضافة موظف", systemImage: "person.badge.plus") }
                    .buttonStyle(OutlineButtonStyle())
                Button { sheet = .importRoster } label: { Label("رفع جدول", systemImage: "square.and.arrow.up") }
                    .buttonStyle(PrimaryButtonStyle())
                if screen == .roster {
                    Button { sheet = .autoFill } label: { Label("تعبئة", systemImage: "wand.and.stars") }.buttonStyle(OutlineButtonStyle())
                }
            }
            .padding(.top, 4) }
        }
    }
}

struct SideDrawer: View {
    @Environment(AppStore.self) private var store
    @Binding var screen: Screen
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                IconTile(symbol: "waveform.path.ecg", tint: .white, size: 48)
                    .background(Theme.primaryLight, in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading) {
                    Text("مِناوب").font(.title2.bold())
                    Text("إدارة المناوبات").font(.caption).opacity(0.7)
                }
                Spacer()
                Button(action: close) { Image(systemName: "xmark").font(.title3).frame(width: 44, height: 44) }
                    .accessibilityLabel("إغلاق")
            }
            HStack {
                Image(systemName: "building.2").foregroundStyle(Theme.primaryLight)
                VStack(alignment: .leading) {
                    Text("المستشفى").font(.caption2).opacity(0.6)
                    Text(store.data.settings.hospital).font(.subheadline.bold())
                }
                Spacer()
            }
            .padding(12)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            .padding(.vertical, 8)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Session.shared.isHead && !Session.shared.offlineMode ? [Screen.dashboard, .home, .roster, .myShifts, .requests, .announcements, .reports, .hours, .employees, .events, .alerts] : Session.shared.isManager ? [Screen.home, .roster, .myShifts, .requests, .announcements, .reports, .hours, .employees, .events, .alerts] : [Screen.myShifts, .roster, .requests, .announcements, .events, .alerts]) { item(for: $0) }
                }
            }
            item(for: .portal)
            item(for: .settings)
        }
        .foregroundStyle(.white)
        .padding()
        .frame(width: 310)
        .frame(maxHeight: .infinity)
        .background(Theme.navy.ignoresSafeArea())
    }

    private func item(for s: Screen) -> some View {
        Button { UISelectionFeedbackGenerator().selectionChanged(); screen = s; close() } label: {
            Label(s.title, systemImage: s.symbol)
                .font(.body.weight(screen == s ? .bold : .regular))
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .padding(.horizontal, 12)
                .background(screen == s ? Theme.primary.opacity(0.45) : .clear, in: RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .leading) {
                    if screen == s { Capsule().fill(Theme.primaryLight).frame(width: 4, height: 30) }
                }
        }
        .accessibilityAddTraits(screen == s ? .isSelected : [])
    }
}
