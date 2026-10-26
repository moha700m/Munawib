import SwiftUI

struct StatCard: View {
    let symbol: String
    let tint: Color
    let caption: String
    let value: String
    let footnote: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(caption).bentoCaption()
                Spacer(minLength: 4)
                Image(systemName: symbol).font(.caption.weight(.semibold)).foregroundStyle(tint).accessibilityHidden(true)
            }
            Text(value).font(Bento.value).monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
            Text(footnote).bentoCaption()
        }
        .bentoTile()
        .accessibilityElement(children: .combine)
    }
}

/// A day in the 7-day coverage strip.
struct CoverageDay: Identifiable {
    let date: Date
    let ratio: Double
    let short: Bool
    var id: Date { date }
}

/// "The department today" bento block shared by the manager home and the head-nurse dashboard.
struct DepartmentBento: View {
    @Environment(AppStore.self) private var store
    @Binding var screen: Screen
    @Binding var sheet: ActiveSheet?
    @State private var approving = false
    @AppStorage("minDay") private var storedMinDay = 2
    @AppStorage("minNight") private var storedMinNight = 1
    private var session: Session { Session.shared }

    private var minDay: Int { session.myDepartment?.min_day ?? storedMinDay.clamped }
    private var minNight: Int { session.myDepartment?.min_night ?? max(1, storedMinNight) }

    var body: some View {
        let s = store.data.settings
        let now = Date()
        let cal = Calendar.current
        let hour = cal.component(.hour, from: now)
        let dayActive = hour >= s.dayStartHour && hour < s.nightStartHour
        let today = store.todayCounts()
        let onDuty = dayActive ? today.day : today.night
        let todayStr = Session.day(now)
        let leaves = session.remote?.leaves ?? [], swaps = session.remote?.swaps ?? []
        let pending = leaves.filter { $0.status == "pending" }.count + swaps.filter { $0.status == "pending" }.count
        let pendingSwaps = swaps.filter { $0.status == "pending" }.count
        let onLeave = session.online
            ? leaves.filter { $0.status == "approved" && $0.start_date <= todayStr && $0.end_date >= todayStr }.count
            : store.departmentEmployees.filter { store.code(for: $0.id, day: cal.component(.day, from: now)) == .leave }.count
        let gap = store.upcomingGaps(minDay: minDay, minNight: minNight, days: 14).first
        let week = coverageWeek(from: now)

        VStack(spacing: Bento.gap) {
            BentoRow(rows: 2) { col in
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("على رأس العمل الآن")).bentoCaption(.dark)
                    Text("\(onDuty)").font(Bento.hero).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                    Spacer(minLength: 0)
                    Text(dayActive ? L("نهاري حتى %@", Fmt.clock(s.nightStartHour)) : L("ليلي حتى %@", Fmt.clock(s.dayStartHour))).bentoCaption(.dark)
                }
                .bentoTile(.dark, rows: 2)
                .frame(width: Bento.span(2, col: col))
                .accessibilityElement(children: .combine)

                VStack(spacing: Bento.gap) {
                    if session.online {
                        BentoStat(caption: L("تنتظر موافقتك"), value: "\(pending)").frame(height: Bento.row)
                    } else {
                        BentoStat(caption: L("جدول %@", "\(store.monthTitle)"), value: store.roster.status.title, valueFont: Bento.small).frame(height: Bento.row)
                    }
                    HStack(spacing: Bento.gap) {
                        BentoStat(caption: L("إجازة"), value: "\(onLeave)")
                        BentoStat(caption: L("تبديل"), value: "\(pendingSwaps)")
                    }
                    .frame(height: Bento.row)
                }
                .frame(width: Bento.span(2, col: col))
            }

            gapTile(gap)

            VStack(alignment: .leading, spacing: 6) {
                Text(L("تغطية الأسبوع")).bentoCaption()
                GeometryReader { g in
                    HStack(alignment: .bottom, spacing: 5) {
                        ForEach(week) { d in
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(d.short ? Theme.coral : Theme.primaryLight)
                                .frame(height: max(8, g.size.height * d.ratio))
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        }
                    }
                }
                HStack(spacing: 5) {
                    ForEach(week) { d in
                        Text(Fmt.date(d.date, "EEEEE")).font(.caption2).foregroundStyle(Theme.muted).frame(maxWidth: .infinity)
                    }
                }
            }
            .bentoTile(.light, rows: 2)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L("تغطية الأسبوع"))
            .accessibilityValue(L("%@ يوم بتغطية ناقصة", "\(week.filter(\.short).count)"))

            BentoRow { col in
                if session.online {
                    BentoAction(title: L("اعتماد الطلبات"), symbol: "checkmark", style: .green) { screen = .requests }
                        .frame(width: Bento.span(2, col: col))
                } else {
                    BentoAction(title: store.roster.status == .approved ? L("الجدول معتمد") : L("اعتماد الجدول"), symbol: store.roster.status == .approved ? "checkmark.seal.fill" : "checkmark", style: .green) {
                        guard !approving, store.roster.status != .approved else { return }
                        Task { approving = true; await store.approve(); approving = false }
                    }
                    .frame(width: Bento.span(2, col: col))
                    .disabled(approving)
                }
                BentoAction(title: L("رفع جدول"), symbol: "calendar") { sheet = .importRoster }
                    .frame(width: Bento.span(2, col: col))
            }
        }
    }

    @ViewBuilder private func gapTile(_ gap: CoverageGap?) -> some View {
        if let gap {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle").font(.title2.weight(.semibold)).foregroundStyle(Theme.danger).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Fmt.date(gap.date, "EEEE d")) · \(gap.shortNight ? L("ليلي") : L("نهاري"))").bentoCaption(.danger)
                    Text(gap.shortfall == 1 ? L("ناقص ممرضة واحدة") : L("ناقص %@ ممرضات", "\(gap.shortfall)"))
                        .font(.system(size: 17, weight: .heavy)).foregroundStyle(Theme.danger).lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer(minLength: 4)
                Button { store.currentMonth = gap.date; screen = .roster } label: {
                    Text(L("سدّ النقص")).font(.footnote.bold()).foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Theme.danger, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(BentoPressStyle())
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .bentoTile(.danger, rows: 1)
        } else {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.shield").font(.title2.weight(.semibold)).foregroundStyle(Theme.primary).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("الأسبوعان القادمان")).bentoCaption()
                    Text(L("التغطية مكتملة")).font(.system(size: 17, weight: .heavy)).foregroundStyle(Theme.primary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .bentoTile(.light, rows: 1)
            .accessibilityElement(children: .combine)
        }
    }

    private func coverageWeek(from now: Date) -> [CoverageDay] {
        let cal = Calendar.current
        let need = Double(max(1, minDay + minNight))
        return (0..<7).compactMap { i -> CoverageDay? in
            guard let d = cal.date(byAdding: .day, value: i, to: now) else { return nil }
            let c = store.coverage(on: d) ?? (day: 0, night: 0)
            return CoverageDay(date: d, ratio: min(1, Double(c.day + c.night) / need), short: c.day < minDay || c.night < minNight)
        }
    }
}

struct HomeView: View {
    @Environment(AppStore.self) private var store
    @Binding var screen: Screen
    @Binding var sheet: ActiveSheet?
    @State private var approving = false

    var body: some View {
        VStack(spacing: Bento.gap) {
            DepartmentBento(screen: $screen, sheet: $sheet)
            if Session.shared.syncing && Session.shared.remote == nil { VStack(alignment: .leading, spacing: 10) { Skeleton(height: 22); Skeleton(); Skeleton() }.card() }
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
                    Text(store.roster.source ?? L("لم يُرفع جدول بعد")).bentoCaption()
                    Text(L("حالة الجدول")).font(.title3.weight(.heavy))
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
                .background(Theme.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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

    private var line: some View { Rectangle().fill(Theme.border).frame(height: 1) }

    private func step(_ t: String, _ s: String, done: Bool) -> some View {
        Label(t, systemImage: s).font(.caption.bold())
            .foregroundStyle(done ? Theme.primary : Theme.muted)
            .fixedSize()
    }

    private var dailyAlerts: some View {
        let s = store.data.settings
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text(L("مواعيد ثابتة")).bentoCaption()
                    Text(L("التنبيهات اليومية")).font(.title3.weight(.heavy))
                }
                Spacer()
                Image(systemName: "alarm").foregroundStyle(Theme.primary).font(.title2)
            }
            shiftRow(.day, L("الشفت النهاري"), hour: s.dayStartHour)
            Divider()
            shiftRow(.night, L("الشفت الليلي"), hour: s.nightStartHour)
            Label(L("التذكير قبل بداية الشفت بـ %@ دقيقة بعد تفعيل التنبيهات واعتماد الجدول.", "\(s.reminderMinutesBefore)"), systemImage: "checkmark.shield")
                .font(.caption).foregroundStyle(Theme.muted)
        }
        .card()
    }

    private func shiftRow(_ c: ShiftCode, _ title: String, hour: Int) -> some View {
        HStack {
            Text(c.rawValue).font(.headline).foregroundStyle(c.chipForeground)
                .frame(width: 40, height: 40).background(c.chipBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading) {
                Text(title).font(.headline)
                Text(L("%1$@ %2$@ · %3$@ ساعة", "\(c.title)", "\(hour12(hour))", "\(store.data.settings.shiftLength)")).font(.caption).foregroundStyle(Theme.muted)
            }
            Spacer()
            Text("\(hour % 12 == 0 ? 12 : hour % 12):00").font(Bento.value).monospacedDigit()
        }
    }

    private func hour12(_ h: Int) -> String { "\(h % 12 == 0 ? 12 : h % 12) \(h < 12 ? L("صباحًا") : L("مساءً"))" }

    private var eventsCard: some View {
        let upcoming = store.data.events.filter { $0.date > Date().addingTimeInterval(-86400) }.sorted { $0.date < $1.date }.prefix(3)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text(L("تنبيه + تقويم")).bentoCaption()
                    Text(L("الدورات والفعاليات القادمة")).font(.title3.weight(.heavy))
                }
                Spacer()
                Button { sheet = .addEvent } label: { Label(L("إضافة"), systemImage: "plus") }
                    .buttonStyle(.bordered)
            }
            if upcoming.isEmpty {
                Text(L("لا توجد فعاليات قادمة")).foregroundStyle(Theme.muted)
            }
            ForEach(Array(upcoming)) { EventRow(event: $0) }
        }
        .card()
    }

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("إجراء سريع")).bentoCaption()
            Text(L("اختصارات")).font(.title3.weight(.heavy))
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
                    Text(t).font(.headline).foregroundStyle(Theme.ink)
                    Text(d).font(.caption).foregroundStyle(Theme.muted).multilineTextAlignment(.leading)
                }
                Spacer()
            }
            .padding()
            .background(Theme.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(BentoPressStyle())
    }
}

struct EventRow: View {
    let event: HospitalEvent
    var body: some View {
        HStack {
            VStack {
                Text(Fmt.date(event.date, "d")).font(.title3.bold()).foregroundStyle(Theme.primary)
                Text(Fmt.date(event.date, "MMMM")).font(.caption2).foregroundStyle(Theme.muted)
            }
            .frame(width: 56, height: 56)
            .background(Theme.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading) {
                Text(event.title).font(.headline)
                Text("\(Fmt.date(event.date, "HH:mm")) · \(event.location)").font(.caption).foregroundStyle(Theme.muted)
            }
            Spacer()
            Text(event.audience).font(.caption).foregroundStyle(Theme.muted)
        }
        .accessibilityElement(children: .combine)
    }
}
