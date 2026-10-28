import SwiftUI

// MARK: - «جناح» v3 home components
// Bold typographic "shift ticket" hero, a 7-day duty strip, and an on-call / swap-board bento row.

/// Today's shift as a ticket: oversized shift name, time range, perforation, and a countdown stub.
struct TodayShiftTicket: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { ctx in
            let now = ctx.date
            let s = store.data.settings
            let me = store.myEmployee
            let len = Double(s.shiftLength) * 3600
            let shifts = me.map { store.upcomingShifts(for: $0.id) } ?? []
            let current = shifts.first { $0.0 <= now && now < $0.0.addingTimeInterval(len) }
            let next = current ?? shifts.first { $0.0 > now }
            let todayCode = me.map { store.code(for: $0.id, on: now) } ?? .empty

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(Fmt.date(now, "EEEE d MMMM")).font(Brand.font(13, .semibold, relativeTo: .footnote))
                        .foregroundStyle(Theme.slate)
                    Spacer()
                    Text(me?.name ?? L("ضيف")).font(Brand.font(13, .semibold, relativeTo: .footnote))
                        .foregroundStyle(Theme.slate).lineLimit(1)
                }
                Text(L("وردية اليوم")).font(Brand.font(13, .regular, relativeTo: .footnote)).foregroundStyle(Theme.slate)
                    .padding(.top, 14)
                Text(todayCode == .empty ? L("ما فيه جدول") : todayCode.title)
                    .font(Brand.heroTitle).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.5)
                if let h = s.startHour(todayCode) {
                    Text(Fmt.range(start: h, length: s.shiftLength)).font(Brand.font(17, .semibold, relativeTo: .headline))
                        .foregroundStyle(todayCode.color == Theme.indigo ? Theme.slate : todayCode.color.opacity(0.95))
                        .monospacedDigit()
                }
                Perforation().padding(.vertical, 14)
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(current != nil ? L("باقي على نهاية المناوبة") : L("المناوبة الجاية"))
                            .font(Brand.font(12, .semibold, relativeTo: .caption)).foregroundStyle(Theme.slate)
                        Text(countdown(now: now, next: next, current: current != nil, length: len))
                            .font(Brand.font(22, .bold, relativeTo: .title2)).foregroundStyle(.white).monospacedDigit()
                    }
                    Spacer()
                    if let next {
                        Text(next.1.label).font(Brand.font(20, .bold, relativeTo: .title3))
                            .foregroundStyle(next.1.chipForeground)
                            .frame(width: 48, height: 48)
                            .background(next.1.chipBackground, in: Circle())
                            .accessibilityHidden(true)
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.tileDark, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("home.todayTicket")
        }
    }

    private func countdown(now: Date, next: (Date, ShiftCode)?, current: Bool, length: Double) -> String {
        guard let next else { return L("لا توجد مناوبات قادمة") }
        let target = current ? next.0.addingTimeInterval(length) : next.0
        let mins = max(0, Int(target.timeIntervalSince(now) / 60))
        let d = mins / 1440, h = (mins % 1440) / 60, m = mins % 60
        if d > 0 { return L("%1$@ يوم و %2$@ ساعة", "\(d)", "\(h)") }
        return String(format: "%02d:%02d", h, m)
    }
}

/// Ticket perforation: a dashed rule between the shift and its countdown stub.
struct Perforation: View {
    var body: some View {
        Line().stroke(style: StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
            .foregroundStyle(Color.white.opacity(0.25)).frame(height: 1.5).accessibilityHidden(true)
    }
    private struct Line: Shape {
        func path(in r: CGRect) -> Path { var p = Path(); p.move(to: CGPoint(x: 0, y: r.midY)); p.addLine(to: CGPoint(x: r.maxX, y: r.midY)); return p }
    }
}

/// Seven pill columns: weekday letter over the shift code, today outlined.
struct DutyWeekStrip: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        let cal = Calendar.current
        let now = Date()
        let me = store.myEmployee
        let days = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: now) }
        VStack(alignment: .leading, spacing: 10) {
            Text(L("أسبوعك في الجناح")).bentoCaption()
            HStack(spacing: 6) {
                ForEach(days, id: \.self) { d in
                    let c = me.map { store.code(for: $0.id, on: d) } ?? .empty
                    VStack(spacing: 6) {
                        Text(Fmt.date(d, "EEEEE")).font(Brand.font(11, .semibold, relativeTo: .caption2)).foregroundStyle(Theme.muted)
                        Text(c.label).font(Brand.font(15, .bold, relativeTo: .subheadline))
                            .foregroundStyle(c.chipForeground)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(c.chipBackground, in: Capsule())
                            .overlay(Capsule().stroke(cal.isDate(d, inSameDayAs: now) ? Theme.ink : .clear, lineWidth: 2))
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(Fmt.date(d, "EEEE")): \(c.title)")
                }
            }
        }
        .bentoTile(.light)
    }
}

/// On-call + swap-board row: two tappable tiles that route to the requests screen.
struct OnCallSwapRow: View {
    @Environment(AppStore.self) private var store
    @Binding var screen: Screen
    var body: some View {
        let pending = store.myPendingRequests
        let me = store.myEmployee
        let nextNight = me.flatMap { e in store.upcomingShifts(for: e.id).first { $0.1 == .night && $0.0 > Date() } }
        BentoRow { col in
            BentoAction(title: L("سوق التبديل"), symbol: "arrow.triangle.swap", style: .green,
                        subtitle: pending.map { L("%@ طلب مفتوح", "\($0)") } ?? L("يتطلب حسابًا")) { screen = .requests }
                .frame(width: Bento.span(2, col: col))
                .accessibilityIdentifier("home.swapBoard")
            BentoAction(title: L("أقرب سهر"), symbol: "moon.stars",
                        subtitle: nextNight.map { Fmt.date($0.0, "EEEE d") } ?? L("لا يوجد")) { screen = .myShifts }
                .frame(width: Bento.span(2, col: col))
        }
    }
}

/// Branded empty state used across lists (replaces the stock ContentUnavailableView look on key screens).
struct WardEmptyState: View {
    let title: String
    let symbol: String
    var message: String? = nil
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 30, weight: .semibold)).foregroundStyle(Theme.primary)
                .frame(width: 72, height: 72)
                .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .accessibilityHidden(true)
            Text(title).font(Brand.font(20, .bold, relativeTo: .title3)).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
            if let message {
                Text(message).font(Brand.font(15, relativeTo: .subheadline)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

extension Brand {
    static let heroTitle = font(54, .bold, relativeTo: .largeTitle)
}
