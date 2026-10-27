import SwiftUI
import Charts
import EventKit
import PhotosUI
import UserNotifications

// MARK: - Notification test
struct NotificationTestPanel: View {
    @Environment(AppStore.self) private var store
    @State private var status: UNAuthorizationStatus = .notDetermined
    @State private var localResult: String?
    @State private var sending = false
    private var session: Session { Session.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L("اختبار التنبيهات"), systemImage: "bell.and.waves.left.and.right").font(.title3.bold())
            VStack(alignment: .leading, spacing: 8) {
                row(L("إذن الإشعارات"), statusText, status == .authorized)
                row(L("رمز الجهاز (APNs)"), session.deviceToken == nil ? L("غير متوفر") : L("تم الحصول عليه"), session.deviceToken != nil)
                row(L("مسجّل على الخادم"), session.tokenRegistered ? L("نعم") : L("لا"), session.tokenRegistered)
                if let r = session.lastPushResult { Text(L("آخر نتيجة Push: %@", "\(r)")).font(.caption).foregroundStyle(.secondary) }
                if let r = localResult { Text(r).font(.caption).foregroundStyle(.secondary) }
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.background, in: RoundedRectangle(cornerRadius: 12))

            if status != .authorized {
                Button { Task { await session.registerForPush(); await refreshStatus() } } label: { Label(L("السماح بالإشعارات"), systemImage: "bell.badge") }
                    .buttonStyle(PrimaryButtonStyle())
            }
            Button {
                Task { await NotificationManager.shared.notifyNow(title: L("اختبار محلي 🔔"), body: L("هذا تنبيه محلي من جهازك.")); localResult = L("تمت جدولة تنبيه محلي خلال ثانيتين"); haptic() }
            } label: { Label(L("تنبيه محلي الآن"), systemImage: "bell") }
                .buttonStyle(OutlineButtonStyle())
            Button {
                Task { await NotificationManager.shared.notify(after: 10, title: L("اختبار بعد 10 ثوانٍ ⏱️"), body: L("اقفل الشاشة أو اخرج من التطبيق لترى التنبيه.")); localResult = L("سيصلك تنبيه بعد 10 ثوانٍ — اخرج من التطبيق"); haptic() }
            } label: { Label(L("تنبيه محلي بعد 10 ثوانٍ"), systemImage: "timer") }
                .buttonStyle(OutlineButtonStyle())
            Button {
                Task { sending = true; await session.sendServerTestPush(); sending = false; haptic() }
            } label: { HStack { if sending { ProgressView() }; Label(L("Push حقيقي من الخادم لهذا الجهاز"), systemImage: "antenna.radiowaves.left.and.right") } }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(sending || !session.online)
            if !session.online { Text(L("Push من الخادم يحتاج تسجيل الدخول بحساب سحابي.")).font(.caption2).foregroundStyle(.secondary) }
        }
        .card()
        .task { await refreshStatus() }
    }

    private func refreshStatus() async {
        status = await NotificationManager.shared.status()
        if status == .authorized { await MainActor.run { UIApplication.shared.registerForRemoteNotifications() } }
    }
    private var statusText: String {
        switch status { case .authorized: return L("مسموح"); case .denied: return L("مرفوض — من إعدادات الجهاز"); case .provisional: return L("مؤقت"); default: return L("لم يُطلب") }
    }
    private func row(_ t: String, _ v: String, _ ok: Bool) -> some View {
        HStack { Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle").foregroundStyle(ok ? .green : .orange); Text(t); Spacer(); Text(v).foregroundStyle(.secondary) }.font(.subheadline)
    }
    private func haptic() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
}

// MARK: - Profile
struct ProfileCard: View {
    @State private var item: PhotosPickerItem?
    @State private var image: UIImage? = ProfileCard.load()
    private var session: Session { Session.shared }

    var body: some View {
        HStack(spacing: 14) {
            PhotosPicker(selection: $item, matching: .images) {
                Group {
                    if let image { Image(uiImage: image).resizable().scaledToFill() }
                    else { Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(Theme.primary.opacity(0.6)) }
                }
                .frame(width: 64, height: 64).clipShape(Circle())
                .overlay(alignment: .bottomTrailing) { Image(systemName: "camera.circle.fill").foregroundStyle(Theme.primary).background(Theme.card, in: Circle()) }
            }
            .accessibilityLabel(L("تغيير الصورة الشخصية"))
            VStack(alignment: .leading, spacing: 4) {
                Text(session.me?.name ?? L("مستخدم محلي")).font(.headline)
                Text(session.me.map { "\($0.roleTitle) · \(session.deptName($0.department_id))" } ?? L("وضع محلي")).font(.caption).foregroundStyle(.secondary)
                if let e = session.me?.email { Text(e).font(.caption2).foregroundStyle(.secondary) }
            }
            Spacer()
        }
        .card()
        .onChange(of: item) { _, new in
            Task {
                guard let d = try? await new?.loadTransferable(type: Data.self), let img = UIImage(data: d) else { return }
                let small = img.preparingThumbnail(of: CGSize(width: 256, height: 256)) ?? img
                image = small
                if let jpg = small.jpegData(compressionQuality: 0.7) { try? jpg.write(to: ProfileCard.url) }
            }
        }
    }
    static var url: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("profile.jpg") }
    static func load() -> UIImage? { UIImage(contentsOfFile: url.path) }
}

// MARK: - Helpers
extension AppStore {
    var myEmployee: Employee? {
        if let me = Session.shared.me, let id = UUID(uuidString: me.id), let e = employee(id) { return e }
        if Session.shared.online { guard let n = Session.shared.me?.employee_number, !n.isEmpty else { return nil }; return data.employees.first { $0.employeeNumber == n } }
        return data.employees.first { $0.employeeNumber == data.settings.loggedInEmployeeNumber }
    }
    func shiftStart(year: Int, month: Int, day: Int, code: ShiftCode) -> Date? {
        guard let hour = data.settings.startHour(code) else { return nil }
        return Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: hour))
    }
    /// All upcoming shifts for an employee across approved/any rosters.
    func upcomingShifts(for emp: UUID, includeDrafts: Bool = true) -> [(Date, ShiftCode)] {
        var out: [(Date, ShiftCode)] = []
        let cutoff = Date().addingTimeInterval(-Double(data.settings.shiftLength) * 3600)
        for r in data.rosters where includeDrafts || r.status == .approved {
            guard let e = r.entries.first(where: { $0.employeeID == emp }) else { continue }
            for (k, c) in e.codes { if let d = Int(k), let s = shiftStart(year: r.year, month: r.month, day: d, code: c), s > cutoff { out.append((s, c)) } }
        }
        return out.sorted { $0.0 < $1.0 }
    }
    func coverage(day: Int) -> (day: Int, night: Int) {
        var dc = 0, nc = 0
        for e in departmentEmployees { switch code(for: e.id, day: day) { case .day: dc += 1; case .night: nc += 1; default: break } }
        return (dc, nc)
    }
    /// Coverage of the selected department on an arbitrary date; nil when that month has no roster yet.
    func coverage(on date: Date) -> (day: Int, night: Int)? {
        let cal = Calendar.current
        let y = cal.component(.year, from: date), m = cal.component(.month, from: date), d = cal.component(.day, from: date)
        guard let r = data.rosters.first(where: { $0.year == y && $0.month == m && $0.department == data.selectedDepartment }) else { return nil }
        var dc = 0, nc = 0
        for e in r.entries { switch e.codes["\(d)"] { case .day?: dc += 1; case .night?: nc += 1; default: break } }
        return (dc, nc)
    }
    /// Days (starting today) where the department is under its minimum day/night staffing.
    func upcomingGaps(minDay: Int, minNight: Int, days: Int = 14) -> [CoverageGap] {
        let cal = Calendar.current
        return (0..<days).compactMap { i -> CoverageGap? in
            guard let d = cal.date(byAdding: .day, value: i, to: Date()) else { return nil }
            let c = coverage(on: d) ?? (day: 0, night: 0)
            guard c.day < minDay || c.night < minNight else { return nil }
            return CoverageGap(date: d, day: c.day, night: c.night, minDay: minDay, minNight: minNight)
        }
    }
    /// Shift code for an employee on any date, looking across all stored rosters.
    func code(for emp: UUID, on date: Date) -> ShiftCode {
        let cal = Calendar.current
        let y = cal.component(.year, from: date), m = cal.component(.month, from: date), d = cal.component(.day, from: date)
        for r in data.rosters where r.year == y && r.month == m {
            if let e = r.entries.first(where: { $0.employeeID == emp }) { return e.codes["\(d)"] ?? .empty }
        }
        return .empty
    }
    /// Number of day/night shifts rostered for an employee in the current month.
    func rosterShiftCount(for emp: UUID) -> Int {
        (1...daysInMonth).filter { code(for: emp, day: $0).isWorking }.count
    }
    /// Pending leave/swap requests that involve the signed-in user (nil when offline).
    var myPendingRequests: Int? {
        guard Session.shared.online, let me = Session.shared.me, let r = Session.shared.remote else { return nil }
        let leaves = r.leaves.filter { $0.user_id == me.id && $0.status == "pending" }.count
        let swaps = r.swaps.filter { ($0.from_user == me.id || $0.to_user == me.id) && $0.status == "pending" }.count
        return leaves + swaps
    }
    /// Next date (within `days`) where the employee has the given code.
    func nextDate(for emp: UUID, code target: ShiftCode, days: Int = 60) -> Date? {
        let cal = Calendar.current
        for i in 0..<days {
            guard let d = cal.date(byAdding: .day, value: i, to: Date()) else { continue }
            if code(for: emp, on: d) == target { return d }
        }
        return nil
    }
}

struct CoverageGap: Identifiable {
    let date: Date
    let day: Int
    let night: Int
    let minDay: Int
    let minNight: Int
    var id: Date { date }
    var shortNight: Bool { night < minNight }
    var shortfall: Int { max(1, (minDay - day).clampedToZero + (minNight - night).clampedToZero) }
}

extension Int { var clampedToZero: Int { Swift.max(0, self) } }

extension AppStore {
    func autoFill(pattern: [ShiftCode], staggered: Bool) {
        for (i, e) in departmentEmployees.enumerated() {
            for d in 1...daysInMonth {
                let off = staggered ? i * max(1, pattern.count / max(1, departmentEmployees.count)) : 0
                setCode(pattern[(d - 1 + off) % pattern.count], emp: e.id, day: d)
            }
        }
        log(L("تعبئة تلقائية"), L("نمط %@", "\(pattern.map(\.rawValue).joined())"))
    }
}

extension Int { var clamped: Int { self <= 0 ? 2 : self } }

// MARK: - Coverage warnings
struct CoverageWarnings: View {
    @Environment(AppStore.self) private var store
    @AppStorage("minDay") private var minDay = 2
    @AppStorage("minNight") private var minNight = 1
    var body: some View {
        let short = (1...store.daysInMonth).filter { let c = store.coverage(day: $0); return c.day < minDay || c.night < minNight }
        VStack(alignment: .leading, spacing: 8) {
            Label(short.isEmpty ? L("التغطية مكتملة لكل الأيام") : L("%@ يوم بتغطية ناقصة", "\(short.count)"), systemImage: short.isEmpty ? "checkmark.shield" : "exclamationmark.triangle.fill")
                .font(.headline).foregroundStyle(short.isEmpty ? .green : .orange)
            HStack {
                Stepper(L("نهاري ≥ %@", "\(minDay)"), value: $minDay, in: 0...20)
                Stepper(L("ليلي ≥ %@", "\(minNight)"), value: $minNight, in: 0...20)
            }.font(.caption).disabled(!Session.shared.isHead)
            if Session.shared.online && Session.shared.me?.isHead == true {
                Button(L("حفظ الحد الأدنى للقسم")) { Task { try? await Session.shared.setCoverage(minDay: minDay, minNight: minNight) } }.font(.caption).buttonStyle(.bordered)
            }
            if !short.isEmpty {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(short, id: \.self) { d in
                            let c = store.coverage(day: d)
                            VStack { Text("\(d)").bold(); Text("D\(c.day) N\(c.night)").font(.caption2) }
                                .padding(8).background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }
        }
        .card()
        .task { if let d = Session.shared.myDepartment { minDay = d.min_day ?? minDay; minNight = d.min_night ?? minNight } }
    }
}

struct AutoFillSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var template = 0
    @State private var staggered = true
    @State private var fair = true
    private let templates: [(String, [ShiftCode])] = [
        (L("2 نهاري · 2 ليلي · 2 راحة"), [.day, .day, .night, .night, .rest, .rest]),
        (L("4 نهاري · 3 راحة"), [.day, .day, .day, .day, .rest, .rest, .rest]),
        (L("3 ليلي · 3 راحة"), [.night, .night, .night, .rest, .rest, .rest]),
        (L("5 نهاري · 2 راحة"), [.day, .day, .day, .day, .day, .rest, .rest]),
    ]
    var body: some View {
        NavigationStack {
            Form {
                Toggle(L("توزيع عادل تلقائي (يوازن النهاري/الليلي/نهاية الأسبوع)"), isOn: $fair)
                if !fair {
                Picker(L("قالب الدوران"), selection: $template) { ForEach(templates.indices, id: \.self) { Text(templates[$0].0).tag($0) } }
                    .pickerStyle(.inline)
                Toggle(L("توزيع متدرّج بين الموظفين لتغطية أفضل"), isOn: $staggered)
                }
                Section { Text(L("سيتم استبدال خانات %1$@ لكل موظفي %2$@. يمكنك التعديل يدويًا بعدها.", "\(store.monthTitle)", "\(store.data.selectedDepartment)")).font(.footnote) }
            }
            .navigationTitle(L("تعبئة تلقائية")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("إلغاء")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(L("تطبيق")) { if fair { store.fairFill(minDay: Session.shared.myDepartment?.min_day ?? UserDefaults.standard.integer(forKey: "minDay").clamped, minNight: Session.shared.myDepartment?.min_night ?? max(1, UserDefaults.standard.integer(forKey: "minNight"))) } else { store.autoFill(pattern: templates[template].1, staggered: staggered) }; UINotificationFeedbackGenerator().notificationOccurred(.success); dismiss() } }
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.direction)
    }
}

// MARK: - My shifts
struct MyShiftsView: View {
    @Environment(AppStore.self) private var store
    @Binding var screen: Screen
    @State private var exportMsg: String?
    @State private var reminderMsg: String?
    @State private var showSwap = false
    private var session: Session { Session.shared }

    var body: some View {
        VStack(spacing: Bento.gap) {
            if let me = store.myEmployee {
                let shifts = store.upcomingShifts(for: me.id)
                let s = store.data.settings
                MasarHero(compact: true).entry(0)
                weekStrip(me).entry(1)
                BentoRow { col in
                    BentoStat(caption: L("ساعات الشهر"), value: "\(store.rosterHours(for: me.id))")
                        .frame(width: Bento.span(2, col: col))
                    if let leave = store.nextDate(for: me.id, code: .leave) {
                        BentoStat(caption: L("إجازة قادمة"), value: Fmt.date(leave, "EEEE d"), valueFont: Bento.small)
                            .frame(width: Bento.span(2, col: col))
                    } else if let rest = store.nextDate(for: me.id, code: .rest) {
                        BentoStat(caption: L("راحة قادمة"), value: Fmt.date(rest, "EEEE d"), valueFont: Bento.small)
                            .frame(width: Bento.span(2, col: col))
                    } else {
                        BentoStat(caption: L("إجازة قادمة"), value: "—", valueFont: Bento.small)
                            .frame(width: Bento.span(2, col: col))
                    }
                }
                BentoRow { col in
                    BentoAction(title: L("طلب تبديل"), symbol: "arrow.left.arrow.right", style: .green) {
                        if session.online { showSwap = true } else { screen = .requests }
                    }
                    .frame(width: Bento.span(2, col: col))
                    BentoAction(title: s.notificationsEnabled ? L("التنبيه مفعّل") : L("تنبيه قبلها"), symbol: s.notificationsEnabled ? "bell.badge.fill" : "bell",
                                subtitle: L("قبل %@ دقيقة", "\(s.reminderMinutesBefore)")) { Task { await enableReminders() } }
                        .frame(width: Bento.span(2, col: col))
                }
                if let reminderMsg { Text(reminderMsg).font(.footnote).foregroundStyle(Theme.muted).frame(maxWidth: .infinity, alignment: .leading) }

                VStack(alignment: .leading, spacing: 10) {
                    HStack { Text(L("مناوباتي القادمة")).font(.title3.weight(.heavy)); Spacer(); Text("\(shifts.count)").font(.headline).monospacedDigit().foregroundStyle(Theme.muted) }
                    if shifts.isEmpty { ContentUnavailableView(L("لا توجد مناوبات"), systemImage: "calendar.badge.exclamationmark", description: Text(L("ستظهر هنا بعد رفع الجدول أو تصوير الجدول الورقي."))) }
                    ForEach(monthGroups(shifts.prefix(60)), id: \.key) { group in
                        HStack {
                            Text(group.title).font(.caption.weight(.bold)).foregroundStyle(Theme.muted)
                            Spacer()
                            Text(L("%1$@ مناوبة · %2$@ ساعة", "\(group.shifts.count)", "\(group.shifts.count * s.shiftLength)")).font(.caption).foregroundStyle(Theme.faint).monospacedDigit()
                        }
                        .padding(.top, 6)
                        ForEach(group.shifts, id: \.0) { sh in
                            ShiftRow(date: sh.0, code: sh.1, hours: s.shiftLength)
                            if sh.0 != group.shifts.last?.0 { Divider().overlay(Theme.border) }
                        }
                    }
                    Button { Task { exportMsg = await CalendarExport.add(shifts: shifts, hours: s.shiftLength) } } label: { Label(L("إضافة للتقويم"), systemImage: "calendar.badge.plus") }
                        .buttonStyle(OutlineButtonStyle()).disabled(shifts.isEmpty)
                    if let exportMsg { Text(exportMsg).font(.footnote).foregroundStyle(Theme.muted) }
                }
                .card()
                .entry(2)
            } else {
                ContentUnavailableView(L("لم يتم ربط حسابك بموظف"), systemImage: "person.crop.circle.badge.questionmark", description: Text(L("سجّل الدخول برقمك الوظيفي وكلمة المرور، أو فعّل حسابك بكود الدعوة.")))
                    .card()
            }
        }
        .sheet(isPresented: $showSwap) { SwapForm() }
    }

    private struct MonthGroup { let key: Int; let title: String; let shifts: [(Date, ShiftCode)] }

    /// Upcoming shifts bucketed by calendar month, in order.
    private func monthGroups<S: Sequence>(_ shifts: S) -> [MonthGroup] where S.Element == (Date, ShiftCode) {
        let cal = Calendar.current
        var out: [MonthGroup] = []
        for sh in shifts {
            let k = cal.component(.year, from: sh.0) * 100 + cal.component(.month, from: sh.0)
            if let i = out.firstIndex(where: { $0.key == k }) {
                out[i] = MonthGroup(key: k, title: out[i].title, shifts: out[i].shifts + [sh])
            } else {
                out.append(MonthGroup(key: k, title: Fmt.date(sh.0, "MMMM yyyy"), shifts: [sh]))
            }
        }
        return out
    }

    /// Seven chips for today and the next six days, coloured by shift code; today is ringed.
    private func weekStrip(_ me: Employee) -> some View {
        let cal = Calendar.current
        let days: [Date] = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: Date()) }
        return VStack(alignment: .leading, spacing: 6) {
            Text(L("هذا الأسبوع")).bentoCaption(.dark)
            HStack(spacing: 6) {
                ForEach(days, id: \.self) { d in
                    let c = store.code(for: me.id, on: d)
                    Text(Fmt.date(d, "d"))
                        .font(.footnote.weight(.bold)).monospacedDigit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(c.chipBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .foregroundStyle(c.chipForeground)
                        .overlay {
                            if cal.isDateInToday(d) { RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.primaryLight, lineWidth: 2) }
                        }
                        .accessibilityLabel("\(Fmt.date(d, "EEEE d")): \(c.title)")
                }
            }
        }
        .bentoTile(.dark, rows: 1)
    }

    private func enableReminders() async {
        let ok = await NotificationManager.shared.requestPermission()
        store.data.settings.notificationsEnabled = ok
        if ok {
            await store.rescheduleNotifications()
            reminderMsg = L("ستصلك التنبيهات قبل كل مناوبة بـ %@ دقيقة.", "\(store.data.settings.reminderMinutesBefore)")
            Haptics.success()
        } else {
            reminderMsg = L("التنبيهات مرفوضة. فعّلها من الإعدادات ← مِناوب ← الإشعارات.")
            Haptics.error()
        }
    }
}

enum CalendarExport {
    static func add(shifts: [(Date, ShiftCode)], hours: Int) async -> String {
        let ev = EKEventStore()
        do {
            guard try await ev.requestWriteOnlyAccessToEvents() else { return L("لم يُسمح بالوصول للتقويم") }
            var n = 0
            for (start, code) in shifts where start > Date() {
                let e = EKEvent(eventStore: ev)
                e.title = L("مناوبة %@ — مِناوب", "\(code.title)")
                e.startDate = start; e.endDate = start.addingTimeInterval(Double(hours) * 3600)
                e.calendar = ev.defaultCalendarForNewEvents
                e.addAlarm(EKAlarm(relativeOffset: -3600))
                try ev.save(e, span: .thisEvent, commit: false); n += 1
            }
            try ev.commit()
            return L("✅ أُضيفت %@ مناوبة إلى التقويم", "\(n)")
        } catch { return L("تعذّر الإضافة: %@", "\(error.localizedDescription)") }
    }
}

// MARK: - Requests (leave + swap)
struct RequestsView: View {
    @Environment(AppStore.self) private var store
    @State private var showLeave = false
    @State private var showSwap = false
    @State private var error: String?
    private var session: Session { Session.shared }

    var body: some View {
        VStack(spacing: 16) {
            if !session.online {
                ContentUnavailableView(L("يتطلب حسابًا سحابيًا"), systemImage: "icloud.slash", description: Text(L("طلبات الإجازة والتبديل تعمل بعد تسجيل الدخول.")))
                    .card()
            } else {
                HStack(spacing: 12) {
                    Button { showLeave = true } label: { Label(L("طلب إجازة"), systemImage: "airplane") }.buttonStyle(PrimaryButtonStyle())
                    Button { showSwap = true } label: { Label(L("طلب تبديل"), systemImage: "arrow.left.arrow.right") }.buttonStyle(OutlineButtonStyle())
                }
                if let error { Text(error).foregroundStyle(.red).font(.footnote) }
                section(L("طلبات الإجازة"), session.remote?.leaves ?? []) { l in
                    RequestRow(title: session.user(l.user_id)?.name ?? "—", detail: "\(l.start_date) ← \(l.end_date)\(l.reason.map { " · " + $0 } ?? "")", status: l.status,
                               canDecide: session.isManager && l.status == "pending") { ok in await act { try await session.decideLeave(l.id, approve: ok) } }
                }
                section(L("طلبات التبديل"), session.remote?.swaps ?? []) { s in
                    RequestRow(title: "\(session.user(s.from_user)?.name ?? "—") ⇄ \(session.user(s.to_user)?.name ?? "—")", detail: L("يوم %1$@%2$@", "\(s.date)", "\(s.note.map { " · " + $0 } ?? "")"), status: s.status,
                               canDecide: session.isManager && s.status == "pending") { ok in await act { try await session.decideSwap(s.id, approve: ok) } }
                }
            }
        }
        .sheet(isPresented: $showLeave) { LeaveForm() }
        .sheet(isPresented: $showSwap) { SwapForm() }
    }

    private func act(_ f: () async throws -> Void) async {
        do { try await f(); error = nil; UINotificationFeedbackGenerator().notificationOccurred(.success) }
        catch { self.error = (error as? LocalizedError)?.errorDescription }
    }

    private func section<T: Identifiable, R: View>(_ title: String, _ items: [T], @ViewBuilder row: @escaping (T) -> R) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title3.bold())
            if items.isEmpty { Text(L("لا توجد طلبات")).font(.footnote).foregroundStyle(.secondary) }
            ForEach(items) { row($0); Divider() }
        }.card()
    }
}

struct RequestRow: View {
    let title: String; let detail: String; let status: String; let canDecide: Bool
    let decide: (Bool) async -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.subheadline.bold())
                Spacer()
                Text(status == "approved" ? L("موافق عليه") : status == "rejected" ? L("مرفوض") : L("قيد الانتظار"))
                    .font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 3)
                    .background((status == "approved" ? Color.green : status == "rejected" ? .red : .orange).opacity(0.15), in: Capsule())
            }
            Text(detail).font(.caption).foregroundStyle(.secondary)
            if canDecide {
                HStack {
                    Button(L("موافقة")) { Task { await decide(true) } }.buttonStyle(.borderedProminent)
                    Button(L("رفض"), role: .destructive) { Task { await decide(false) } }.buttonStyle(.bordered)
                }
            }
        }
    }
}

struct LeaveForm: View {
    @Environment(\.dismiss) private var dismiss
    @State private var from = Date()
    @State private var to = Date().addingTimeInterval(86400)
    @State private var reason = ""
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                DatePicker(L("من"), selection: $from, displayedComponents: .date)
                DatePicker(L("إلى"), selection: $to, in: from..., displayedComponents: .date)
                TextField(L("السبب"), text: $reason, axis: .vertical)
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle(L("طلب إجازة")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("إلغاء")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(L("إرسال")) { Task { do { try await Session.shared.requestLeave(from: from, to: to, reason: reason); dismiss() } catch { self.error = (error as? LocalizedError)?.errorDescription } } } }
            }
            .keyboardDone()
        }
        .environment(\.layoutDirection, LanguageManager.shared.direction)
    }
}

struct SwapForm: View {
    @Environment(\.dismiss) private var dismiss
    @State private var colleague = ""
    @State private var date = Date()
    @State private var note = ""
    @State private var error: String?
    var body: some View {
        let me = Session.shared.me
        let others = (Session.shared.remote?.users ?? []).filter { $0.id != me?.id && $0.department_id == me?.department_id }
        NavigationStack {
            Form {
                Picker(L("الزميل"), selection: $colleague) {
                    Text(L("اختر")).tag("")
                    ForEach(others) { Text($0.name).tag($0.id) }
                }
                DatePicker(L("يوم المناوبة"), selection: $date, displayedComponents: .date)
                AppTextField(placeholder: L("ملاحظة"), text: $note).frame(minHeight: 32)
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle(L("طلب تبديل")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("إلغاء")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("إرسال")) { Task { do { try await Session.shared.requestSwap(with: colleague, date: date, note: note); dismiss() } catch { self.error = (error as? LocalizedError)?.errorDescription } } }
                        .disabled(colleague.isEmpty)
                }
            }
            .keyboardDone()
        }
        .environment(\.layoutDirection, LanguageManager.shared.direction)
    }
}

// MARK: - Announcements
struct AnnouncementsView: View {
    @Environment(AppStore.self) private var store
    @State private var title = ""
    @State private var text = ""
    @State private var allHospital = true
    @State private var busy = false
    @State private var error: String?
    private var session: Session { Session.shared }
    var body: some View {
        VStack(spacing: 16) {
            if session.online && session.isManager {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L("إعلان جديد")).font(.title3.bold())
                    AppTextField(placeholder: L("العنوان"), text: $title).frame(minHeight: 32).fieldBox()
                    TextField(L("النص"), text: $text, axis: .vertical).lineLimit(3...6).fieldBox()
                    Toggle(L("لكل المستشفى"), isOn: $allHospital)
                    if let error { Text(error).foregroundStyle(.red).font(.footnote) }
                    Button {
                        Task {
                            busy = true; defer { busy = false }
                            do { try await session.announce(title: title, body: text, dept: allHospital ? nil : store.data.selectedDepartment); title = ""; text = ""; KeyboardHelper.dismiss() }
                            catch { self.error = (error as? LocalizedError)?.errorDescription }
                        }
                    } label: { Label(L("نشر وإرسال تنبيه"), systemImage: "megaphone") }
                        .buttonStyle(PrimaryButtonStyle()).disabled(title.isEmpty || busy)
                }.card()
            }
            VStack(alignment: .leading, spacing: 10) {
                Text(L("لوحة الإعلانات")).font(.title3.bold())
                let items = session.remote?.announcements ?? []
                if items.isEmpty { ContentUnavailableView(L("لا توجد إعلانات"), systemImage: "megaphone", description: Text(session.online ? L("ستظهر إعلانات الإدارة هنا.") : L("سجّل الدخول لمشاهدة إعلانات المستشفى."))) }
                ForEach(items) { a in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(a.title).font(.headline)
                        if let b = a.body, !b.isEmpty { Text(b).font(.subheadline) }
                        Text("\(a.author ?? "") · \(Fmt.date(Date(timeIntervalSince1970: a.created_at / 1000), "d MMM h:mm a"))").font(.caption).foregroundStyle(.secondary)
                    }
                    Divider()
                }
            }.card()
        }
    }
}

// MARK: - Reports
struct HoursRow: Identifiable { let id: UUID; let name: String; let number: String; let rostered: Int; let logged: Double }

struct ReportsView: View {
    @Environment(AppStore.self) private var store
    @State private var fileURL: URL?
    var body: some View {
        let rows = store.departmentEmployees.map { e in
            HoursRow(id: e.id, name: e.name, number: e.employeeNumber, rostered: store.rosterHours(for: e.id),
                     logged: store.monthHours().filter { $0.employeeID == e.id }.reduce(0) { $0 + $1.hours })
        }
        let cov = (1...store.daysInMonth).map { (d: $0, c: store.coverage(day: $0)) }
        VStack(spacing: 16) {
            VStack(alignment: .leading) {
                Text(L("ساعات %@", "\(store.monthTitle)")).font(.title3.bold())
                if rows.isEmpty { ContentUnavailableView(L("لا يوجد موظفون"), systemImage: "chart.bar") }
                else {
                    Chart(rows) { r in
                        BarMark(x: .value(L("الساعات"), r.rostered), y: .value(L("الموظف"), r.name)).foregroundStyle(Theme.primary).annotation(position: .trailing) { Text("\(r.rostered)").font(.caption2) }
                    }
                    .frame(height: CGFloat(max(160, rows.count * 34)))
                    .accessibilityLabel(L("مخطط ساعات الموظفين"))
                }
            }.card()
            VStack(alignment: .leading) {
                Text(L("التغطية اليومية")).font(.title3.bold())
                Chart {
                    ForEach(cov, id: \.d) { x in
                        LineMark(x: .value(L("اليوم"), x.d), y: .value(L("العدد"), x.c.day)).foregroundStyle(by: .value(L("نوع"), L("نهاري")))
                        LineMark(x: .value(L("اليوم"), x.d), y: .value(L("العدد"), x.c.night)).foregroundStyle(by: .value(L("نوع"), L("ليلي")))
                    }
                }
                .chartForegroundStyleScale([L("نهاري"): Theme.amber, L("ليلي"): Theme.indigo])
                .frame(height: 180)
            }.card()
            HStack(spacing: 12) {
                Button { fileURL = ReportExport.pdf(store: store, rows: rows) } label: { Label("PDF", systemImage: "doc.richtext") }.buttonStyle(OutlineButtonStyle())
                Button { fileURL = ReportExport.csv(store: store, rows: rows) } label: { Label("CSV / Excel", systemImage: "tablecells") }.buttonStyle(OutlineButtonStyle())
            }
            if let fileURL { ShareLink(item: fileURL) { Label(L("مشاركة %@", "\(fileURL.lastPathComponent)"), systemImage: "square.and.arrow.up") }.buttonStyle(PrimaryButtonStyle()) }
        }
    }
}

enum ReportExport {
    static func csv(store: AppStore, rows: [HoursRow]) -> URL {
        var s = L("\u{FEFF}الموظف,الرقم,ساعات الجدول,الساعات المسجلة\n")
        for r in rows { s += "\"\(r.name)\",\(r.number),\(r.rostered),\(Fmt.hours(r.logged))\n" }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("munawib-hours-\(store.year)-\(store.month).csv")
        try? s.data(using: .utf8)?.write(to: url)
        return url
    }
    static func pdf(store: AppStore, rows: [HoursRow]) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("munawib-hours-\(store.year)-\(store.month).pdf")
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let para = NSMutableParagraphStyle(); para.alignment = .right; para.baseWritingDirection = .rightToLeft
        let title: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 20), .paragraphStyle: para]
        let body: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12), .paragraphStyle: para]
        try? UIGraphicsPDFRenderer(bounds: page).writePDF(to: url) { ctx in
            ctx.beginPage()
            (L("تقرير ساعات %1$@ — %2$@", "\(store.monthTitle)", "\(store.data.selectedDepartment)") as NSString).draw(in: CGRect(x: 40, y: 40, width: 515, height: 30), withAttributes: title)
            (store.data.settings.hospital as NSString).draw(in: CGRect(x: 40, y: 70, width: 515, height: 20), withAttributes: body)
            var y: CGFloat = 110
            (L("الموظف        الرقم        ساعات الجدول        المسجلة") as NSString).draw(in: CGRect(x: 40, y: y, width: 515, height: 18), withAttributes: title.merging([.font: UIFont.boldSystemFont(ofSize: 12)]) { $1 })
            y += 24
            for r in rows {
                if y > 800 { ctx.beginPage(); y = 40 }
                ("\(r.name)        \(r.number)        \(r.rostered)        \(Fmt.hours(r.logged))" as NSString).draw(in: CGRect(x: 40, y: y, width: 515, height: 18), withAttributes: body)
                y += 20
            }
            (L("الإجمالي: %@ ساعة", "\(rows.reduce(0) { $0 + $1.rostered })") as NSString).draw(in: CGRect(x: 40, y: y + 10, width: 515, height: 18), withAttributes: title.merging([.font: UIFont.boldSystemFont(ofSize: 13)]) { $1 })
        }
        return url
    }
}
