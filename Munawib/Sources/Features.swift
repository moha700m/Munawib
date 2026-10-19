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
            Label("اختبار التنبيهات", systemImage: "bell.and.waves.left.and.right").font(.title3.bold())
            VStack(alignment: .leading, spacing: 8) {
                row("إذن الإشعارات", statusText, status == .authorized)
                row("رمز الجهاز (APNs)", session.deviceToken == nil ? "غير متوفر" : "تم الحصول عليه", session.deviceToken != nil)
                row("مسجّل على الخادم", session.tokenRegistered ? "نعم" : "لا", session.tokenRegistered)
                if let r = session.lastPushResult { Text("آخر نتيجة Push: \(r)").font(.caption).foregroundStyle(.secondary) }
                if let r = localResult { Text(r).font(.caption).foregroundStyle(.secondary) }
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.background, in: RoundedRectangle(cornerRadius: 12))

            if status != .authorized {
                Button { Task { await session.registerForPush(); await refreshStatus() } } label: { Label("السماح بالإشعارات", systemImage: "bell.badge") }
                    .buttonStyle(PrimaryButtonStyle())
            }
            Button {
                Task { await NotificationManager.shared.notifyNow(title: "اختبار محلي 🔔", body: "هذا تنبيه محلي من جهازك."); localResult = "تمت جدولة تنبيه محلي خلال ثانيتين"; haptic() }
            } label: { Label("تنبيه محلي الآن", systemImage: "bell") }
                .buttonStyle(OutlineButtonStyle())
            Button {
                Task { await NotificationManager.shared.notify(after: 10, title: "اختبار بعد 10 ثوانٍ ⏱️", body: "اقفل الشاشة أو اخرج من التطبيق لترى التنبيه."); localResult = "سيصلك تنبيه بعد 10 ثوانٍ — اخرج من التطبيق"; haptic() }
            } label: { Label("تنبيه محلي بعد 10 ثوانٍ", systemImage: "timer") }
                .buttonStyle(OutlineButtonStyle())
            Button {
                Task { sending = true; await session.sendServerTestPush(); sending = false; haptic() }
            } label: { HStack { if sending { ProgressView() }; Label("Push حقيقي من الخادم لهذا الجهاز", systemImage: "antenna.radiowaves.left.and.right") } }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(sending || !session.online)
            if !session.online { Text("Push من الخادم يحتاج تسجيل الدخول بحساب سحابي.").font(.caption2).foregroundStyle(.secondary) }
        }
        .card()
        .task { await refreshStatus() }
    }

    private func refreshStatus() async {
        status = await NotificationManager.shared.status()
        if status == .authorized { await MainActor.run { UIApplication.shared.registerForRemoteNotifications() } }
    }
    private var statusText: String {
        switch status { case .authorized: return "مسموح"; case .denied: return "مرفوض — من إعدادات الجهاز"; case .provisional: return "مؤقت"; default: return "لم يُطلب" }
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
                .overlay(alignment: .bottomTrailing) { Image(systemName: "camera.circle.fill").foregroundStyle(Theme.primary).background(.white, in: Circle()) }
            }
            .accessibilityLabel("تغيير الصورة الشخصية")
            VStack(alignment: .leading, spacing: 4) {
                Text(session.me?.name ?? "مستخدم محلي").font(.headline)
                Text(session.me.map { "\($0.roleTitle) · \(session.deptName($0.department_id))" } ?? "وضع محلي").font(.caption).foregroundStyle(.secondary)
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
        guard code == .day || code == .night else { return nil }
        return Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: code == .day ? data.settings.dayStartHour : data.settings.nightStartHour))
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
    func autoFill(pattern: [ShiftCode], staggered: Bool) {
        for (i, e) in departmentEmployees.enumerated() {
            for d in 1...daysInMonth {
                let off = staggered ? i * max(1, pattern.count / max(1, departmentEmployees.count)) : 0
                setCode(pattern[(d - 1 + off) % pattern.count], emp: e.id, day: d)
            }
        }
        log("تعبئة تلقائية", "نمط \(pattern.map(\.rawValue).joined())")
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
            Label(short.isEmpty ? "التغطية مكتملة لكل الأيام" : "\(short.count) يوم بتغطية ناقصة", systemImage: short.isEmpty ? "checkmark.shield" : "exclamationmark.triangle.fill")
                .font(.headline).foregroundStyle(short.isEmpty ? .green : .orange)
            HStack {
                Stepper("نهاري ≥ \(minDay)", value: $minDay, in: 0...20)
                Stepper("ليلي ≥ \(minNight)", value: $minNight, in: 0...20)
            }.font(.caption).disabled(!Session.shared.isHead)
            if Session.shared.online && Session.shared.me?.isHead == true {
                Button("حفظ الحد الأدنى للقسم") { Task { try? await Session.shared.setCoverage(minDay: minDay, minNight: minNight) } }.font(.caption).buttonStyle(.bordered)
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
        ("2 نهاري · 2 ليلي · 2 راحة", [.day, .day, .night, .night, .rest, .rest]),
        ("4 نهاري · 3 راحة", [.day, .day, .day, .day, .rest, .rest, .rest]),
        ("3 ليلي · 3 راحة", [.night, .night, .night, .rest, .rest, .rest]),
        ("5 نهاري · 2 راحة", [.day, .day, .day, .day, .day, .rest, .rest]),
    ]
    var body: some View {
        NavigationStack {
            Form {
                Toggle("توزيع عادل تلقائي (يوازن النهاري/الليلي/نهاية الأسبوع)", isOn: $fair)
                if !fair {
                Picker("قالب الدوران", selection: $template) { ForEach(templates.indices, id: \.self) { Text(templates[$0].0).tag($0) } }
                    .pickerStyle(.inline)
                Toggle("توزيع متدرّج بين الموظفين لتغطية أفضل", isOn: $staggered)
                }
                Section { Text("سيتم استبدال خانات \(store.monthTitle) لكل موظفي \(store.data.selectedDepartment). يمكنك التعديل يدويًا بعدها.").font(.footnote) }
            }
            .navigationTitle("تعبئة تلقائية").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("تطبيق") { if fair { store.fairFill(minDay: Session.shared.myDepartment?.min_day ?? UserDefaults.standard.integer(forKey: "minDay").clamped, minNight: Session.shared.myDepartment?.min_night ?? max(1, UserDefaults.standard.integer(forKey: "minNight"))) } else { store.autoFill(pattern: templates[template].1, staggered: staggered) }; UINotificationFeedbackGenerator().notificationOccurred(.success); dismiss() } }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }
}

// MARK: - My shifts
struct MyShiftsView: View {
    @Environment(AppStore.self) private var store
    @State private var exportMsg: String?
    var body: some View {
        VStack(spacing: 16) {
            if let me = store.myEmployee {
                let shifts = store.upcomingShifts(for: me.id)
                TodayShiftCard()
                VStack(alignment: .leading, spacing: 10) {
                    HStack { Text("مناوباتي القادمة").font(.title3.bold()); Spacer(); Text("\(shifts.count)").foregroundStyle(.secondary) }
                    if shifts.isEmpty { ContentUnavailableView("لا توجد مناوبات", systemImage: "calendar.badge.exclamationmark", description: Text("ستظهر هنا بعد رفع الجدول.")) }
                    ForEach(shifts.prefix(40), id: \.0) { s in
                        HStack {
                            Text(s.1.label).font(.headline).frame(width: 36, height: 36).background(s.1.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 8)).foregroundStyle(s.1.color)
                            VStack(alignment: .leading) { Text(Fmt.date(s.0, "EEEE d MMMM")).font(.subheadline.bold()); Text("\(Fmt.date(s.0, "h:mm a")) · \(store.data.settings.shiftLength) ساعة").font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                        }
                        Divider()
                    }
                    Button { Task { exportMsg = await CalendarExport.add(shifts: shifts, hours: store.data.settings.shiftLength) } } label: { Label("إضافة للتقويم", systemImage: "calendar.badge.plus") }
                        .buttonStyle(PrimaryButtonStyle()).disabled(shifts.isEmpty)
                    if let exportMsg { Text(exportMsg).font(.footnote).foregroundStyle(.secondary) }
                }.card()
            } else {
                ContentUnavailableView("لم يتم ربط حسابك بموظف", systemImage: "person.crop.circle.badge.questionmark", description: Text("سجّل الدخول برقمك الوظيفي وكلمة المرور، أو فعّل حسابك بكود الدعوة."))
                    .card()
            }
        }
    }
}

enum CalendarExport {
    static func add(shifts: [(Date, ShiftCode)], hours: Int) async -> String {
        let ev = EKEventStore()
        do {
            guard try await ev.requestWriteOnlyAccessToEvents() else { return "لم يُسمح بالوصول للتقويم" }
            var n = 0
            for (start, code) in shifts where start > Date() {
                let e = EKEvent(eventStore: ev)
                e.title = "مناوبة \(code.title) — مِناوب"
                e.startDate = start; e.endDate = start.addingTimeInterval(Double(hours) * 3600)
                e.calendar = ev.defaultCalendarForNewEvents
                e.addAlarm(EKAlarm(relativeOffset: -3600))
                try ev.save(e, span: .thisEvent, commit: false); n += 1
            }
            try ev.commit()
            return "✅ أُضيفت \(n) مناوبة إلى التقويم"
        } catch { return "تعذّر الإضافة: \(error.localizedDescription)" }
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
                ContentUnavailableView("يتطلب حسابًا سحابيًا", systemImage: "icloud.slash", description: Text("طلبات الإجازة والتبديل تعمل بعد تسجيل الدخول."))
                    .card()
            } else {
                HStack(spacing: 12) {
                    Button { showLeave = true } label: { Label("طلب إجازة", systemImage: "airplane") }.buttonStyle(PrimaryButtonStyle())
                    Button { showSwap = true } label: { Label("طلب تبديل", systemImage: "arrow.left.arrow.right") }.buttonStyle(OutlineButtonStyle())
                }
                if let error { Text(error).foregroundStyle(.red).font(.footnote) }
                section("طلبات الإجازة", session.remote?.leaves ?? []) { l in
                    RequestRow(title: session.user(l.user_id)?.name ?? "—", detail: "\(l.start_date) ← \(l.end_date)\(l.reason.map { " · " + $0 } ?? "")", status: l.status,
                               canDecide: session.isManager && l.status == "pending") { ok in await act { try await session.decideLeave(l.id, approve: ok) } }
                }
                section("طلبات التبديل", session.remote?.swaps ?? []) { s in
                    RequestRow(title: "\(session.user(s.from_user)?.name ?? "—") ⇄ \(session.user(s.to_user)?.name ?? "—")", detail: "يوم \(s.date)\(s.note.map { " · " + $0 } ?? "")", status: s.status,
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
            if items.isEmpty { Text("لا توجد طلبات").font(.footnote).foregroundStyle(.secondary) }
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
                Text(status == "approved" ? "موافق عليه" : status == "rejected" ? "مرفوض" : "قيد الانتظار")
                    .font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 3)
                    .background((status == "approved" ? Color.green : status == "rejected" ? .red : .orange).opacity(0.15), in: Capsule())
            }
            Text(detail).font(.caption).foregroundStyle(.secondary)
            if canDecide {
                HStack {
                    Button("موافقة") { Task { await decide(true) } }.buttonStyle(.borderedProminent)
                    Button("رفض", role: .destructive) { Task { await decide(false) } }.buttonStyle(.bordered)
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
                DatePicker("من", selection: $from, displayedComponents: .date)
                DatePicker("إلى", selection: $to, in: from..., displayedComponents: .date)
                TextField("السبب", text: $reason, axis: .vertical)
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("طلب إجازة").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("إرسال") { Task { do { try await Session.shared.requestLeave(from: from, to: to, reason: reason); dismiss() } catch { self.error = (error as? LocalizedError)?.errorDescription } } } }
            }
            .keyboardDone()
        }
        .environment(\.layoutDirection, .rightToLeft)
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
                Picker("الزميل", selection: $colleague) {
                    Text("اختر").tag("")
                    ForEach(others) { Text($0.name).tag($0.id) }
                }
                DatePicker("يوم المناوبة", selection: $date, displayedComponents: .date)
                TextField("ملاحظة", text: $note)
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("طلب تبديل").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("إرسال") { Task { do { try await Session.shared.requestSwap(with: colleague, date: date, note: note); dismiss() } catch { self.error = (error as? LocalizedError)?.errorDescription } } }
                        .disabled(colleague.isEmpty)
                }
            }
            .keyboardDone()
        }
        .environment(\.layoutDirection, .rightToLeft)
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
                    Text("إعلان جديد").font(.title3.bold())
                    TextField("العنوان", text: $title).fieldBox()
                    TextField("النص", text: $text, axis: .vertical).lineLimit(3...6).fieldBox()
                    Toggle("لكل المستشفى", isOn: $allHospital)
                    if let error { Text(error).foregroundStyle(.red).font(.footnote) }
                    Button {
                        Task {
                            busy = true; defer { busy = false }
                            do { try await session.announce(title: title, body: text, dept: allHospital ? nil : store.data.selectedDepartment); title = ""; text = ""; KeyboardHelper.dismiss() }
                            catch { self.error = (error as? LocalizedError)?.errorDescription }
                        }
                    } label: { Label("نشر وإرسال تنبيه", systemImage: "megaphone") }
                        .buttonStyle(PrimaryButtonStyle()).disabled(title.isEmpty || busy)
                }.card()
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("لوحة الإعلانات").font(.title3.bold())
                let items = session.remote?.announcements ?? []
                if items.isEmpty { ContentUnavailableView("لا توجد إعلانات", systemImage: "megaphone", description: Text(session.online ? "ستظهر إعلانات الإدارة هنا." : "سجّل الدخول لمشاهدة إعلانات المستشفى.")) }
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
                Text("ساعات \(store.monthTitle)").font(.title3.bold())
                if rows.isEmpty { ContentUnavailableView("لا يوجد موظفون", systemImage: "chart.bar") }
                else {
                    Chart(rows) { r in
                        BarMark(x: .value("الساعات", r.rostered), y: .value("الموظف", r.name)).foregroundStyle(Theme.primary).annotation(position: .trailing) { Text("\(r.rostered)").font(.caption2) }
                    }
                    .frame(height: CGFloat(max(160, rows.count * 34)))
                    .accessibilityLabel("مخطط ساعات الموظفين")
                }
            }.card()
            VStack(alignment: .leading) {
                Text("التغطية اليومية").font(.title3.bold())
                Chart {
                    ForEach(cov, id: \.d) { x in
                        LineMark(x: .value("اليوم", x.d), y: .value("العدد", x.c.day)).foregroundStyle(by: .value("نوع", "نهاري"))
                        LineMark(x: .value("اليوم", x.d), y: .value("العدد", x.c.night)).foregroundStyle(by: .value("نوع", "ليلي"))
                    }
                }
                .chartForegroundStyleScale(["نهاري": .blue, "ليلي": .purple])
                .frame(height: 180)
            }.card()
            HStack(spacing: 12) {
                Button { fileURL = ReportExport.pdf(store: store, rows: rows) } label: { Label("PDF", systemImage: "doc.richtext") }.buttonStyle(OutlineButtonStyle())
                Button { fileURL = ReportExport.csv(store: store, rows: rows) } label: { Label("CSV / Excel", systemImage: "tablecells") }.buttonStyle(OutlineButtonStyle())
            }
            if let fileURL { ShareLink(item: fileURL) { Label("مشاركة \(fileURL.lastPathComponent)", systemImage: "square.and.arrow.up") }.buttonStyle(PrimaryButtonStyle()) }
        }
    }
}

enum ReportExport {
    static func csv(store: AppStore, rows: [HoursRow]) -> URL {
        var s = "\u{FEFF}الموظف,الرقم,ساعات الجدول,الساعات المسجلة\n"
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
            ("تقرير ساعات \(store.monthTitle) — \(store.data.selectedDepartment)" as NSString).draw(in: CGRect(x: 40, y: 40, width: 515, height: 30), withAttributes: title)
            (store.data.settings.hospital as NSString).draw(in: CGRect(x: 40, y: 70, width: 515, height: 20), withAttributes: body)
            var y: CGFloat = 110
            ("الموظف        الرقم        ساعات الجدول        المسجلة" as NSString).draw(in: CGRect(x: 40, y: y, width: 515, height: 18), withAttributes: title.merging([.font: UIFont.boldSystemFont(ofSize: 12)]) { $1 })
            y += 24
            for r in rows {
                if y > 800 { ctx.beginPage(); y = 40 }
                ("\(r.name)        \(r.number)        \(r.rostered)        \(Fmt.hours(r.logged))" as NSString).draw(in: CGRect(x: 40, y: y, width: 515, height: 18), withAttributes: body)
                y += 20
            }
            ("الإجمالي: \(rows.reduce(0) { $0 + $1.rostered }) ساعة" as NSString).draw(in: CGRect(x: 40, y: y + 10, width: 515, height: 18), withAttributes: title.merging([.font: UIFont.boldSystemFont(ofSize: 13)]) { $1 })
        }
        return url
    }
}
