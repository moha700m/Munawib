import SwiftUI

struct RoleBadge: View {
    let title: String
    var body: some View {
        if !title.isEmpty {
            Text(title).font(.caption2.bold()).lineLimit(1).minimumScaleFactor(0.7).fixedSize(horizontal: true, vertical: false).padding(.horizontal, 8).padding(.vertical, 4)
                .foregroundStyle(Theme.onPrimary).background(Theme.primary, in: Capsule())
                .accessibilityLabel(L("الدور: %@", "\(title)"))
        }
    }
}

struct HeadNurseDashboard: View {
    @Environment(AppStore.self) private var store
    @Binding var screen: Screen
    @Binding var sheet: ActiveSheet?
    @State private var showPush = false
    @State private var showAudit = false
    private var session: Session { Session.shared }

    var body: some View {
        let today = store.todayCounts()
        let minD = session.myDepartment?.min_day ?? 2, minN = session.myDepartment?.min_night ?? 1
        VStack(spacing: Bento.gap) {
            if let info = session.signupInfo {
                VStack(alignment: .leading, spacing: 6) {
                    Label(L("احفظ هذه الرموز"), systemImage: "key.fill").font(.headline)
                    Text(info).font(.body.monospaced()).textSelection(.enabled)
                    ShareLink(item: info) { Label(L("مشاركة"), systemImage: "square.and.arrow.up") }
                }.card()
            }
            DialHero(compact: true).entry(0)
            DepartmentBento(screen: $screen, sheet: $sheet).entry(1)
            BentoRow { col in
                BentoStat(caption: L("تغطية اليوم"), value: "D\(today.day) · N\(today.night)", footnote: L("الحد الأدنى D%1$@ · N%2$@", "\(minD)", "\(minN)"), valueFont: Bento.small)
                    .frame(width: Bento.span(2, col: col))
                if let code = session.remote?.hospital?.code {
                    BentoStat(caption: L("رمز المستشفى لدخول الموظفين"), value: code, valueFont: Bento.small)
                        .frame(width: Bento.span(2, col: col))
                        .textSelection(.enabled)
                } else {
                    BentoStat(caption: L("الموظفون"), value: "\(store.departmentEmployees.count)", footnote: L("في القسم الحالي"))
                        .frame(width: Bento.span(2, col: col))
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(L("إجراءات سريعة")).bentoCaption().padding(.horizontal, 4)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: Bento.gap), GridItem(.flexible())], spacing: Bento.gap) {
                    quick(L("الموافقات"), "checkmark.seal") { screen = .requests }
                    quick(L("الجدول"), "calendar") { screen = .roster }
                    quick(L("تعبئة عادلة"), "wand.and.stars") { screen = .roster; sheet = .autoFill }
                    quick(L("إضافة موظف"), "person.badge.plus") { sheet = .addEmployee }
                    quick(L("إرسال تنبيه"), "paperplane") { showPush = true }
                    quick(L("إعلان"), "megaphone") { screen = .announcements }
                    quick(L("التقارير"), "chart.bar") { screen = .reports }
                    quick(L("سجل التدقيق"), "list.bullet.clipboard") { showAudit = true }
                }
            }
        }
        .sheet(isPresented: $showPush) { CustomPushSheet() }
        .sheet(isPresented: $showAudit) { AuditLogView() }
    }

    private func quick(_ t: String, _ s: String, _ a: @escaping () -> Void) -> some View {
        BentoAction(title: t, symbol: s) { Haptics.tap(); a() }
            .frame(height: Bento.row)
    }
}

struct CustomPushSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var text = ""
    @State private var everyone = true
    @State private var selected: Set<String> = []
    @State private var result: String?
    @State private var busy = false
    var body: some View {
        let me = Session.shared.me
        let staff = (Session.shared.remote?.users ?? []).filter { me?.role == "admin" || $0.department_id == me?.department_id }
        NavigationStack {
            Form {
                AppTextField(placeholder: L("العنوان"), text: $title).frame(minHeight: 32)
                TextField(L("النص"), text: $text, axis: .vertical)
                Toggle(L("كل القسم"), isOn: $everyone)
                if !everyone {
                    Section(L("المستلمون")) {
                        ForEach(staff) { u in
                            Button { if selected.contains(u.id) { selected.remove(u.id) } else { selected.insert(u.id) } } label: {
                                HStack { Text(u.name).foregroundStyle(.primary); Spacer(); if selected.contains(u.id) { Image(systemName: "checkmark").foregroundStyle(Theme.primary) } }
                            }
                        }
                    }
                }
                if let result { Text(result) }
            }
            .navigationTitle(L("تنبيه مخصص")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("إغلاق")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("إرسال")) {
                        Task {
                            busy = true; defer { busy = false }
                            do { result = try await Session.shared.customPush(title: title, body: text, userIDs: everyone ? [] : Array(selected)); UINotificationFeedbackGenerator().notificationOccurred(.success) }
                            catch { result = (error as? LocalizedError)?.errorDescription }
                        }
                    }.disabled(title.isEmpty || busy || (!everyone && selected.isEmpty))
                }
            }
            .keyboardDone()
        }
        .environment(\.layoutDirection, LanguageManager.shared.direction)
    }
}

struct AuditLogView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                let items = Session.shared.remote?.audit_log ?? []
                if items.isEmpty { ContentUnavailableView(L("لا توجد سجلات"), systemImage: "list.bullet.clipboard") }
                ForEach(items) { a in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(AuditLogView.title(a.action)).font(.subheadline.bold())
                        if let d = a.detail, !d.isEmpty { Text(d).font(.caption).lineLimit(3) }
                        Text("\(a.user_name ?? "") · \(Fmt.date(Date(timeIntervalSince1970: a.created_at / 1000), "d MMM h:mm a"))").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .refreshable { try? await Session.shared.refresh() }
            .navigationTitle(L("سجل التدقيق")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L("إغلاق")) { dismiss() } } }
        }
        .environment(\.layoutDirection, LanguageManager.shared.direction)
    }
    static func title(_ a: String) -> String {
        [ "roster.save": L("حفظ الجدول"), "roster.approved": L("اعتماد الجدول"), "roster.review": L("مراجعة الجدول"), "roster.draft": L("إرجاع الجدول مسودة"),
          "employee.create": L("إضافة موظف"), "employee.update": L("تعديل موظف"), "employee.delete": L("حذف موظف"), "employee.role": L("تغيير صلاحية"),
          "leave.request": L("طلب إجازة"), "leave.approved": L("موافقة إجازة"), "leave.rejected": L("رفض إجازة"),
          "swap.request": L("طلب تبديل"), "swap.approved": L("موافقة تبديل"), "swap.rejected": L("رفض تبديل"),
          "announcement": L("إعلان"), "push.custom": L("تنبيه مخصص"), "department.update": L("إعدادات القسم"), "attendance.add": L("تسجيل ساعات") ][a] ?? a
    }
}

// MARK: - Fair distribution
extension AppStore {
    /// Greedy fair fill: meets daily D/N minimums, balances total / night / weekend counts, avoids D right after N.
    func fairFill(minDay: Int, minNight: Int) {
        let emps = departmentEmployees
        guard !emps.isEmpty else { return }
        var total = [UUID: Int](), nights = [UUID: Int](), weekends = [UUID: Int](), last = [UUID: ShiftCode]()
        let cal = Calendar.current
        for d in 1...daysInMonth {
            let date = cal.date(from: DateComponents(year: year, month: month, day: d)) ?? Date()
            let wk = [6, 7].contains(cal.component(.weekday, from: date)) // Fri/Sat
            var free = emps.map(\.id).filter { code(for: $0, day: d) != .leave && code(for: $0, day: d) != .course }
            func pick(_ n: Int, night: Bool) -> [UUID] {
                let c = free.filter { night || last[$0] != .night }
                    .sorted { (total[$0, default: 0], night ? nights[$0, default: 0] : 0, wk ? weekends[$0, default: 0] : 0) < (total[$1, default: 0], night ? nights[$1, default: 0] : 0, wk ? weekends[$1, default: 0] : 0) }
                let chosen = Array(c.prefix(n)); free.removeAll { chosen.contains($0) }; return chosen
            }
            let ns = pick(minNight, night: true), ds = pick(minDay, night: false)
            for e in emps.map(\.id) {
                let cur = code(for: e, day: d)
                let c: ShiftCode = ns.contains(e) ? .night : ds.contains(e) ? .day : (cur == .leave || cur == .course ? cur : .rest)
                setCode(c, emp: e, day: d)
                if c == .day || c == .night { total[e, default: 0] += 1; if wk { weekends[e, default: 0] += 1 } }
                if c == .night { nights[e, default: 0] += 1 }
                last[e] = c
            }
        }
        log(L("تعبئة عادلة"), "D≥\(minDay) N≥\(minNight)")
    }
}
