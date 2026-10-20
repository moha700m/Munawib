import SwiftUI

struct StatCard: View {
    let symbol: String
    let tint: Color
    let caption: String
    let value: String
    let footnote: String
    var body: some View {
        HStack(alignment: .top) {
            IconTile(symbol: symbol, tint: tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(caption).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.title2.bold()).minimumScaleFactor(0.6).lineLimit(1)
                Text(footnote).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .card()
        .accessibilityElement(children: .combine)
    }
}

struct HomeView: View {
    @Environment(AppStore.self) private var store
    @Binding var screen: Screen
    @Binding var sheet: ActiveSheet?
    @State private var approving = false

    var body: some View {
        let today = store.todayCounts()
        let emps = store.departmentEmployees
        VStack(spacing: 16) {
            TodayShiftCard()
            if Session.shared.syncing && Session.shared.remote == nil { VStack(alignment: .leading, spacing: 10) { Skeleton(height: 22); Skeleton(); Skeleton() }.card() }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                StatCard(symbol: "calendar", tint: Theme.primary, caption: L("جدول %@", "\(store.monthTitle)"), value: store.roster.status.title, footnote: store.roster.status == .approved ? L("تم الإرسال للفريق") : L("لن تُرسل التنبيهات قبل الاعتماد"))
                StatCard(symbol: "person.2", tint: .blue, caption: L("الموظفون"), value: "\(emps.count)", footnote: L("في القسم الحالي"))
                StatCard(symbol: "paperclip", tint: .orange, caption: L("الحسابات المربوطة"), value: "\(emps.filter(\.linked).count)", footnote: L("من أصل %@", "\(emps.count)"))
                StatCard(symbol: "alarm", tint: .purple, caption: L("تنبيهات اليوم"), value: "\(today.day + today.night)", footnote: L("%1$@ نهاري · %2$@ ليلي", "\(today.day)", "\(today.night)"))
            }
            statusCard
            dailyAlerts
            eventsCard
            shortcuts
        }
    }

    private var stage: Int {
        switch store.roster.status { case .draft: return store.roster.source == nil ? 0 : 1; case .reviewed: return 1; case .approved: return 2 }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading) {
                    Text(store.roster.source ?? L("لم يُرفع جدول بعد")).font(.caption).foregroundStyle(.secondary)
                    Text(L("حالة الجدول")).font(.title2.bold())
                }
                Spacer()
                StatusBadge(status: store.roster.status)
            }
            HStack {
                step(L("رفع الملف"), "checkmark", done: true)
                line
                step(L("المراجعة"), "sparkles", done: stage >= 1)
                line
                step(L("إرسال للفريق"), "paperplane", done: stage >= 2)
            }
            Label(L("لن تُرسل الجداول أو التنبيهات قبل الاعتماد."), systemImage: "checkmark.shield")
                .font(.footnote).foregroundStyle(Theme.primary)
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            HStack {
                Button {
                    Task { approving = true; await store.approve(); approving = false }
                } label: { Label(L("اعتماد وإرسال للفريق"), systemImage: "paperplane") }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(approving || store.roster.status == .approved)
                Button(L("مراجعة الجدول")) { screen = .roster }
                    .font(.subheadline.bold()).frame(minHeight: 44)
            }
        }
        .card()
    }

    private var line: some View { Rectangle().fill(.quaternary).frame(height: 1) }

    private func step(_ t: String, _ s: String, done: Bool) -> some View {
        Label(t, systemImage: s).font(.caption.bold())
            .foregroundStyle(done ? Theme.primary : .secondary)
            .fixedSize()
    }

    private var dailyAlerts: some View {
        let s = store.data.settings
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text(L("مواعيد ثابتة")).font(.caption).foregroundStyle(.secondary)
                    Text(L("التنبيهات اليومية")).font(.title2.bold())
                }
                Spacer()
                Image(systemName: "alarm").foregroundStyle(Theme.primary).font(.title2)
            }
            shiftRow(.day, L("الشفت النهاري"), hour: s.dayStartHour)
            Divider()
            shiftRow(.night, L("الشفت الليلي"), hour: s.nightStartHour)
            Label(L("التذكير قبل بداية الشفت بـ %@ دقيقة بعد تفعيل التنبيهات واعتماد الجدول.", "\(s.reminderMinutesBefore)"), systemImage: "checkmark.shield")
                .font(.caption).foregroundStyle(.secondary)
        }
        .card()
    }

    private func shiftRow(_ c: ShiftCode, _ title: String, hour: Int) -> some View {
        HStack {
            Text(c.rawValue).font(.headline).foregroundStyle(c.color)
                .frame(width: 40, height: 40).background(c.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading) {
                Text(title).font(.headline)
                Text(L("%1$@ %2$@ · %3$@ ساعة", "\(c.title)", "\(hour12(hour))", "\(store.data.settings.shiftLength)")).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(hour % 12 == 0 ? 12 : hour % 12):00").font(.title.bold()).monospacedDigit()
        }
    }

    private func hour12(_ h: Int) -> String { "\(h % 12 == 0 ? 12 : h % 12) \(h < 12 ? L("صباحًا") : L("مساءً"))" }

    private var eventsCard: some View {
        let upcoming = store.data.events.filter { $0.date > Date().addingTimeInterval(-86400) }.sorted { $0.date < $1.date }.prefix(3)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text(L("تنبيه + تقويم")).font(.caption).foregroundStyle(.secondary)
                    Text(L("الدورات والفعاليات القادمة")).font(.title3.bold())
                }
                Spacer()
                Button { sheet = .addEvent } label: { Label(L("إضافة"), systemImage: "plus") }
                    .buttonStyle(.bordered)
            }
            if upcoming.isEmpty {
                Text(L("لا توجد فعاليات قادمة")).foregroundStyle(.secondary)
            }
            ForEach(Array(upcoming)) { EventRow(event: $0) }
        }
        .card()
    }

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("إجراء سريع")).font(.caption).foregroundStyle(.secondary)
            Text(L("اختصارات")).font(.title2.bold())
            shortcut(L("رفع صورة أو PDF"), L("يقرأ النظام الجدول من الصورة ثم يعرضه للمراجعة."), "doc.viewfinder") { sheet = .importRoster }
            shortcut(L("إضافة موظف"), L("دعوة مرتبطة بالرقم الوظيفي"), "person.badge.plus") { sheet = .addEmployee }
            shortcut(L("سجل الإرسال"), L("الرسائل والتنبيهات"), "paperplane") { screen = .alerts }
        }
        .card()
    }

    private func shortcut(_ t: String, _ d: String, _ s: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: s).foregroundStyle(Theme.primary).frame(width: 30)
                VStack(alignment: .leading) {
                    Text(t).font(.headline).foregroundStyle(.primary)
                    Text(d).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                }
                Spacer()
            }
            .padding()
            .background(Theme.background, in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

struct EventRow: View {
    let event: HospitalEvent
    var body: some View {
        HStack {
            VStack {
                Text(Fmt.date(event.date, "d")).font(.title3.bold()).foregroundStyle(Theme.primary)
                Text(Fmt.date(event.date, "MMMM")).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(width: 56, height: 56)
            .background(Theme.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading) {
                Text(event.title).font(.headline)
                Text("\(Fmt.date(event.date, "HH:mm")) · \(event.location)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(event.audience).font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
