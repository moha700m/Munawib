import SwiftUI

// MARK: - «مسار» timeline hero

/// One row of today's timeline: a shift window (day / evening / night), the "now" marker, or tomorrow's first window.
struct MasarRow: Identifiable {
    enum Kind { case shift, now, tomorrow }
    let id: String
    let kind: Kind
    let time: Date
    let title: String
    let color: Color
    /// Trailing status: «خلصت», «بعد 02:22», «بكرة», …
    let status: String?
    /// Window already over → drawn dimmed.
    let past: Bool
    /// The signed-in user's next shift → drawn larger.
    let emphasized: Bool
}

/// Builds the rows from the shift settings and the user's codes for today / tomorrow. Pure, so it can be reasoned about
/// without a view: windows are ordered by start hour, the "now" marker is inserted chronologically and tomorrow's first
/// window closes the list.
enum MasarTimeline {
    static func rows(now: Date, settings s: AppSettings, todayCode: ShiftCode?, tomorrowCode: ShiftCode?, next: (Date, ShiftCode)?, calendar cal: Calendar = .current) -> [MasarRow] {
        let len = Double(s.shiftLength) * 3600
        let windows: [(ShiftCode, Int)] = [(.day, s.dayStartHour), (.evening, s.eveningStart), (.night, s.nightStartHour)].sorted { $0.1 < $1.1 }
        let dayStart = cal.startOfDay(for: now)
        var out: [MasarRow] = []
        for (code, hour) in windows {
            guard let start = cal.date(byAdding: .hour, value: hour, to: dayStart) else { continue }
            let end = start.addingTimeInterval(len)
            let mine = todayCode == code
            let isNext = next.map { cal.isDate($0.0, equalTo: start, toGranularity: .minute) } ?? false
            let status: String?
            if end <= now { status = L("خلصت") }
            else if start <= now {
                status = mine ? L("تنتهي بعد %@", countdown(until: end, from: now)) : L("الآن")
            } else if isNext {
                status = L("بعد %@", countdown(until: start, from: now))
            } else { status = nil }
            out.append(MasarRow(id: "today-\(code.rawValue)", kind: .shift, time: start, title: code.title, color: code.color, status: status, past: end <= now, emphasized: isNext))
        }
        out.append(MasarRow(id: "now", kind: .now, time: now, title: L("الحين"), color: Theme.ink, status: nil, past: false, emphasized: false))
        if let first = windows.first, let tomorrow = cal.date(byAdding: .day, value: 1, to: dayStart), let start = cal.date(byAdding: .hour, value: first.1, to: tomorrow) {
            let code = tomorrowCode.flatMap { $0.isWorking || $0 == .empty ? nil : $0 }
            let isNext = next.map { cal.isDate($0.0, equalTo: start, toGranularity: .minute) } ?? false
            out.append(MasarRow(id: "tomorrow", kind: .tomorrow, time: start, title: code?.title ?? first.0.title, color: code?.color ?? first.0.color, status: L("بكرة"), past: false, emphasized: isNext))
        }
        return out.sorted { $0.time < $1.time }
    }

    static func countdown(until target: Date, from now: Date) -> String {
        let cd = Countdown.parts(until: target, from: now)
        return cd.unit.map { "\(cd.value) \($0)" } ?? cd.value
    }
}

/// «مدار يومك» card in design D «مسار»: the next-shift countdown in the shift's colour, a vertical timeline of today's
/// windows with a "now" marker, and three legend chips with the shift time ranges. Refreshes every minute.
struct MasarHero: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduce
    var compact = false

    @State private var drawn: CGFloat = 0

    private var rowHeight: CGFloat { compact ? 46 : 54 }
    private let timeWidth: CGFloat = 72
    private let dotWidth: CGFloat = 26
    private let gap: CGFloat = 14

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { ctx in
            let now = ctx.date
            let s = store.data.settings
            let len = Double(s.shiftLength) * 3600
            let me = store.myEmployee
            let shifts = me.map { store.upcomingShifts(for: $0.id) } ?? []
            let current = shifts.first { $0.0 <= now && now < $0.0.addingTimeInterval(len) }
            let next = current ?? shifts.first { $0.0 > now }
            let cal = Calendar.current
            let todayCode = me.map { store.code(for: $0.id, on: now) }
            let tomorrowCode = me.flatMap { e in cal.date(byAdding: .day, value: 1, to: now).map { store.code(for: e.id, on: $0) } }
            let rows = MasarTimeline.rows(now: now, settings: s, todayCode: todayCode, tomorrowCode: tomorrowCode, next: next, calendar: cal)

            VStack(spacing: Bento.gap) {
                VStack(alignment: .leading, spacing: compact ? 10 : 14) {
                    header(now: now, me: me, next: next, current: current != nil, length: len)
                    timeline(rows)
                }
                .card()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L("مدار يومك"))
                .accessibilityValue(accessibilityValue(next: next, current: current != nil, now: now, length: len, rows: rows))

                legend(s)
            }
            .onAppear {
                guard drawn < 1 else { return }
                if reduce { drawn = 1 } else { withAnimation(Motion.draw) { drawn = 1 } }
            }
        }
    }

    // MARK: Header

    @ViewBuilder private func header(now: Date, me: Employee?, next: (Date, ShiftCode)?, current: Bool, length: TimeInterval) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(current ? L("مناوبتك الآن · تنتهي بعد") : L("المناوبة الجاية")).font(.caption).foregroundStyle(Theme.muted)
            if let next {
                let cd = Countdown.parts(until: current ? next.0.addingTimeInterval(length) : next.0, from: now)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(cd.value)
                            .font(.system(size: compact ? 50 : 64, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(next.1.color)
                            .contentTransition(reduce ? ContentTransition.identity : ContentTransition.numericText(countsDown: true))
                            .animation(Motion.quick(reduce), value: cd.value)
                        if let u = cd.unit { Text(u).font(.title3.bold()).foregroundStyle(Theme.muted) }
                    }
                    .environment(\.layoutDirection, .leftToRight)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(next.1.title).font(.title3.weight(.heavy)).foregroundStyle(Theme.ink)
                        Text(Fmt.date(next.0, "EEEE d")).font(.caption).foregroundStyle(Theme.muted)
                    }
                    .lineLimit(1).minimumScaleFactor(0.7)
                }
                .lineLimit(1).minimumScaleFactor(0.5)
            } else if me == nil {
                Label(L("اربط حسابك بموظف لعرض مناوباتك"), systemImage: "person.crop.circle.badge.questionmark")
                    .font(.headline).foregroundStyle(Theme.ink).padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("لا توجد مناوبات قادمة")).font(.title3.weight(.heavy)).foregroundStyle(Theme.ink)
                    Text(L("صوّر الجدول الورقي لإضافتها")).font(.caption).foregroundStyle(Theme.muted)
                }
                .padding(.vertical, 6)
            }
        }
    }

    // MARK: Timeline

    private func timeline(_ rows: [MasarRow]) -> some View {
        let lineColors = rows.filter { $0.kind != .now }.map(\.color)
        return VStack(spacing: 0) {
            ForEach(rows) { row in
                HStack(spacing: gap) {
                    Text(Fmt.date(row.time, "h:mm a"))
                        .font(.subheadline.weight(.medium)).monospacedDigit()
                        .foregroundStyle(row.kind == .now ? Theme.ink : Theme.muted)
                        .frame(width: timeWidth, alignment: .leading)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    ZStack {
                        if row.kind == .now {
                            Circle().fill(Theme.ink.opacity(0.18)).frame(width: dotWidth, height: dotWidth)
                            Circle().fill(Theme.ink).frame(width: 14, height: 14)
                        } else {
                            Circle().fill(row.color.opacity(0.2)).frame(width: dotWidth, height: dotWidth)
                            Circle().fill(row.color).frame(width: row.emphasized ? 14 : 11, height: row.emphasized ? 14 : 11)
                        }
                    }
                    .frame(width: dotWidth, height: dotWidth)
                    Text(row.title)
                        .font(row.emphasized ? .title3.weight(.heavy) : .body.weight(row.kind == .now ? .heavy : .bold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 6)
                    if let status = row.status {
                        Text(status).font(.caption).foregroundStyle(row.emphasized ? row.color : Theme.muted).monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.7)
                            .contentTransition(reduce ? ContentTransition.identity : ContentTransition.numericText(countsDown: true))
                            .animation(Motion.quick(reduce), value: status)
                    }
                }
                .frame(height: rowHeight)
                .opacity(row.past ? 0.4 : 1)
            }
        }
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(LinearGradient(colors: lineColors.isEmpty ? [Theme.border] : lineColors, startPoint: .top, endPoint: .bottom))
                .frame(width: 3)
                .scaleEffect(y: drawn, anchor: .top)
                .padding(.vertical, rowHeight / 2)
                .padding(.leading, timeWidth + gap + (dotWidth - 3) / 2)
        }
        .accessibilityHidden(true)
    }

    // MARK: Legend

    private func legend(_ s: AppSettings) -> some View {
        HStack(spacing: Bento.gap) {
            ForEach([ShiftCode.day, .evening, .night], id: \.self) { code in
                if let h = s.startHour(code) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Circle().fill(code.color).frame(width: 9, height: 9)
                            Text(code.title).font(.caption).foregroundStyle(Theme.muted)
                        }
                        Text("\(Fmt.date(hourDate(h), "h a")) – \(Fmt.date(hourDate(h + s.shiftLength), "h a"))")
                            .font(.subheadline.weight(.bold)).monospacedDigit().foregroundStyle(Theme.ink)
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.border, lineWidth: 1))
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func hourDate(_ h: Int) -> Date {
        Calendar.current.date(bySettingHour: ((h % 24) + 24) % 24, minute: 0, second: 0, of: Date()) ?? Date()
    }

    private func accessibilityValue(next: (Date, ShiftCode)?, current: Bool, now: Date, length: TimeInterval, rows: [MasarRow]) -> String {
        var parts: [String] = []
        if let next {
            let when = MasarTimeline.countdown(until: current ? next.0.addingTimeInterval(length) : next.0, from: now)
            parts.append("\(current ? L("تنتهي بعد") : L("المناوبة الجاية")) \(when)، \(next.1.title) \(Fmt.date(next.0, "EEEE d"))")
        } else {
            parts.append(L("لا توجد مناوبات قادمة"))
        }
        for r in rows where r.kind != .now {
            parts.append("\(Fmt.date(r.time, "h:mm a")) \(r.title)\(r.status.map { " \($0)" } ?? "")")
        }
        return parts.joined(separator: "، ")
    }
}
