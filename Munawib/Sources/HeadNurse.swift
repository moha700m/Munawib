import SwiftUI

struct RoleBadge: View {
    let title: String
    var body: some View {
        if !title.isEmpty {
            Text(title).font(.caption2.bold()).padding(.horizontal, 8).padding(.vertical, 4)
                .foregroundStyle(.white).background(Theme.primary, in: Capsule())
                .accessibilityLabel("الدور: \(title)")
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
        let pending = (session.remote?.leaves.filter { $0.status == "pending" }.count ?? 0) + (session.remote?.swaps.filter { $0.status == "pending" }.count ?? 0)
        let today = store.todayCounts()
        let todayStr = Session.day(Date())
        let onLeave = (session.remote?.leaves ?? []).filter { $0.status == "approved" && $0.start_date <= todayStr && $0.end_date >= todayStr }
        let minD = session.myDepartment?.min_day ?? 2, minN = session.myDepartment?.min_night ?? 1
        let gaps = upcomingGaps(minD: minD, minN: minN)
        VStack(spacing: 16) {
            if let info = session.signupInfo {
                VStack(alignment: .leading, spacing: 6) {
                    Label("احفظ هذه الرموز", systemImage: "key.fill").font(.headline)
                    Text(info).font(.body.monospaced()).textSelection(.enabled)
                    ShareLink(item: info) { Label("مشاركة", systemImage: "square.and.arrow.up") }
                }.card()
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                StatCard(symbol: "tray.full", tint: .orange, caption: "بانتظار الموافقة", value: "\(pending)", footnote: "إجازات وتبديلات")
                StatCard(symbol: "sun.max", tint: .blue, caption: "تغطية اليوم", value: "D\(today.day) · N\(today.night)", footnote: "الحد الأدنى D\(minD) · N\(minN)")
                StatCard(symbol: "airplane", tint: .pink, caption: "في إجازة اليوم", value: "\(onLeave.count)", footnote: onLeave.prefix(2).compactMap { session.user($0.user_id)?.name }.joined(separator: "، "))
                StatCard(symbol: "exclamationmark.triangle", tint: .red, caption: "فجوات قادمة (14 يوم)", value: "\(gaps.count)", footnote: gaps.prefix(3).map { "\($0)" }.joined(separator: "، "))
            }
            if let code = session.remote?.hospital?.code {
                HStack { Label("رمز المستشفى لدخول الموظفين", systemImage: "building.2"); Spacer(); Text(code).font(.headline.monospaced()).textSelection(.enabled) }.card()
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("إجراءات سريعة").font(.title3.bold())
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    quick("الموافقات", "checkmark.seal") { screen = .requests }
                    quick("الجدول", "calendar") { screen = .roster }
                    quick("تعبئة عادلة", "wand.and.stars") { screen = .roster; sheet = .autoFill }
                    quick("إضافة موظف", "person.badge.plus") { sheet = .addEmployee }
                    quick("إرسال تنبيه", "paperplane") { showPush = true }
                    quick("إعلان", "megaphone") { screen = .announcements }
                    quick("التقارير", "chart.bar") { screen = .reports }
                    quick("سجل التدقيق", "list.bullet.clipboard") { showAudit = true }
                }
            }.card()
        }
        .sheet(isPresented: $showPush) { CustomPushSheet() }
        .sheet(isPresented: $showAudit) { AuditLogView() }
    }

    private func upcomingGaps(minD: Int, minN: Int) -> [String] {
        let cal = Calendar.current
        var out: [String] = []
        for i in 0..<14 {
            guard let d = cal.date(byAdding: .day, value: i, to: Date()) else { continue }
            let y = cal.component(.year, from: d), m = cal.component(.month, from: d), day = cal.component(.day, from: d)
            guard let r = store.data.rosters.first(where: { $0.year == y && $0.month == m && $0.department == store.data.selectedDepartment }) else { out.append(Fmt.date(d, "d/M")); continue }
            var dc = 0, nc = 0
            for e in r.entries { switch e.codes["\(day)"] { case .day?: dc += 1; case .night?: nc += 1; default: break } }
            if dc < minD || nc < minN { out.append(Fmt.date(d, "d/M")) }
        }
        return out
    }

    private func quick(_ t: String, _ s: String, _ a: @escaping () -> Void) -> some View {
        Button { UIImpactFeedbackGenerator(style: .light).impactOccurred(); a() } label: {
            Label(t, systemImage: s).frame(maxWidth: .infinity, minHeight: 48)
                .background(Theme.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        }
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
                AppTextField(placeholder: "العنوان", text: $title).frame(minHeight: 32)
                TextField("النص", text: $text, axis: .vertical)
                Toggle("كل القسم", isOn: $everyone)
                if !everyone {
                    Section("المستلمون") {
                        ForEach(staff) { u in
                            Button { if selected.contains(u.id) { selected.remove(u.id) } else { selected.insert(u.id) } } label: {
                                HStack { Text(u.name).foregroundStyle(.primary); Spacer(); if selected.contains(u.id) { Image(systemName: "checkmark").foregroundStyle(Theme.primary) } }
                            }
                        }
                    }
                }
                if let result { Text(result) }
            }
            .navigationTitle("تنبيه مخصص").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إغلاق") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("إرسال") {
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
        .environment(\.layoutDirection, .rightToLeft)
    }
}

struct AuditLogView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                let items = Session.shared.remote?.audit_log ?? []
                if items.isEmpty { ContentUnavailableView("لا توجد سجلات", systemImage: "list.bullet.clipboard") }
                ForEach(items) { a in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(AuditLogView.title(a.action)).font(.subheadline.bold())
                        if let d = a.detail, !d.isEmpty { Text(d).font(.caption).lineLimit(3) }
                        Text("\(a.user_name ?? "") · \(Fmt.date(Date(timeIntervalSince1970: a.created_at / 1000), "d MMM h:mm a"))").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .refreshable { try? await Session.shared.refresh() }
            .navigationTitle("سجل التدقيق").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("إغلاق") { dismiss() } } }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }
    static func title(_ a: String) -> String {
        [ "roster.save": "حفظ الجدول", "roster.approved": "اعتماد الجدول", "roster.review": "مراجعة الجدول", "roster.draft": "إرجاع الجدول مسودة",
          "employee.create": "إضافة موظف", "employee.update": "تعديل موظف", "employee.delete": "حذف موظف", "employee.role": "تغيير صلاحية",
          "leave.request": "طلب إجازة", "leave.approved": "موافقة إجازة", "leave.rejected": "رفض إجازة",
          "swap.request": "طلب تبديل", "swap.approved": "موافقة تبديل", "swap.rejected": "رفض تبديل",
          "announcement": "إعلان", "push.custom": "تنبيه مخصص", "department.update": "إعدادات القسم", "attendance.add": "تسجيل ساعات" ][a] ?? a
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
        log("تعبئة عادلة", "D≥\(minDay) N≥\(minNight)")
    }
}
