import SwiftUI

// MARK: - 24-hour dial

/// One coloured band on the dial, in hours of the day; may wrap past midnight.
struct DialArc: Identifiable {
    let code: ShiftCode
    let start: Double
    let length: Double
    var emphasized: Bool = false
    var id: String { "\(code.rawValue)-\(start)-\(emphasized)" }
}

/// Circular 24-hour clock: midnight at the top, hours clockwise. Shift windows are drawn as arcs
/// (amber day, pink evening, indigo night); the emphasized arc draws itself once on first appearance.
struct MadarDial<Center: View>: View {
    let arcs: [DialArc]
    let now: Date
    var size: CGFloat = 236
    var lineWidth: CGFloat = 16
    @ViewBuilder let center: () -> Center

    @State private var progress: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.layoutDirection) private var direction

    private struct Segment: Identifiable {
        let id: Int
        let from: CGFloat
        let to: CGFloat
    }

    var body: some View {
        let radius = size / 2 - lineWidth / 2
        ZStack {
            Circle().stroke(Theme.track, lineWidth: lineWidth).padding(lineWidth / 2)
            ForEach(0..<24, id: \.self) { h in
                Capsule()
                    .fill(h % 6 == 0 ? Theme.muted : Theme.borderStrong)
                    .frame(width: h % 6 == 0 ? 2 : 1, height: h % 6 == 0 ? 9 : 5)
                    .offset(y: -(radius - lineWidth / 2 - 10))
                    .rotationEffect(.degrees(Double(h) * 15))
            }
            ForEach(arcs.filter { !$0.emphasized }) { arc in band(arc, radius: radius, drawn: 1) }
            ForEach(arcs.filter(\.emphasized)) { arc in band(arc, radius: radius, drawn: progress) }
            Circle()
                .fill(Theme.ink)
                .frame(width: 9, height: 9)
                .overlay(Circle().stroke(Theme.background, lineWidth: 2))
                .offset(y: -radius)
                .rotationEffect(.degrees(hourAngle(now)))
            hourLabels(radius: radius)
            center()
                .environment(\.layoutDirection, direction)
                .frame(width: size - lineWidth * 2 - 36)
        }
        .frame(width: size, height: size)
        .environment(\.layoutDirection, .leftToRight)
        .onAppear {
            guard progress < 1 else { return }
            if reduce { progress = 1 } else { withAnimation(Motion.draw) { progress = 1 } }
        }
    }

    private func hourAngle(_ d: Date) -> Double {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return (Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60) * 15
    }

    private func hourLabels(radius: CGFloat) -> some View {
        let inset = radius - lineWidth / 2 - 26
        return ZStack {
            Text("24").offset(y: -inset)
            Text("6").offset(x: inset)
            Text("12").offset(y: inset)
            Text("18").offset(x: -inset)
        }
        .font(.caption2.weight(.semibold)).monospacedDigit()
        .foregroundStyle(Theme.faint)
    }

    private func segments(_ arc: DialArc, drawn: CGFloat) -> [Segment] {
        let f0 = CGFloat(arc.start / 24), total = CGFloat(arc.length / 24)
        let end = f0 + total * drawn
        if end <= 1 { return [Segment(id: 0, from: f0, to: end)] }
        return [Segment(id: 0, from: f0, to: 1), Segment(id: 1, from: 0, to: end - 1)]
    }

    @ViewBuilder private func band(_ arc: DialArc, radius: CGFloat, drawn: CGFloat) -> some View {
        ForEach(segments(arc, drawn: drawn)) { seg in
            Circle()
                .trim(from: seg.from, to: seg.to)
                .stroke(arc.code.color.opacity(arc.emphasized ? 1 : 0.22),
                        style: StrokeStyle(lineWidth: arc.emphasized ? lineWidth : lineWidth - 6, lineCap: .round))
                .padding(lineWidth / 2)
                .rotationEffect(.degrees(-90))
                .shadow(color: arc.emphasized ? arc.code.color.opacity(0.45) : .clear, radius: 10)
        }
    }
}

// MARK: - Dial hero

/// «مدار يومك»: the dial with the countdown to the next shift (or time left on the current one) in the centre.
/// Refreshes every minute; the countdown digits roll with a numeric content transition.
struct DialHero: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduce
    var compact = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { ctx in
            let now = ctx.date
            let s = store.data.settings
            let len = Double(s.shiftLength) * 3600
            let me = store.myEmployee
            let shifts = me.map { store.upcomingShifts(for: $0.id) } ?? []
            let current = shifts.first { $0.0 <= now && now < $0.0.addingTimeInterval(len) }
            let next = current ?? shifts.first { $0.0 > now }
            let focus = next?.1
            let todayCode = me.map { store.code(for: $0.id, on: now) } ?? .empty
            let arcs: [DialArc] = [
                DialArc(code: .day, start: Double(s.dayStartHour), length: Double(s.shiftLength), emphasized: focus == .day),
                DialArc(code: .evening, start: Double(s.eveningStart), length: Double(s.shiftLength), emphasized: focus == .evening),
                DialArc(code: .night, start: Double(s.nightStartHour), length: Double(s.shiftLength), emphasized: focus == .night),
            ]
            let cd = next.map { Countdown.parts(until: current != nil ? $0.0.addingTimeInterval(len) : $0.0, from: now) }

            VStack(spacing: 14) {
                MadarDial(arcs: arcs, now: now, size: compact ? 200 : 236) {
                    VStack(spacing: 4) {
                        if let n = next, let cd {
                            Text(current != nil ? L("تنتهي بعد") : L("المناوبة القادمة بعد"))
                                .font(.caption).foregroundStyle(Theme.muted).lineLimit(1).minimumScaleFactor(0.7)
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(cd.value)
                                    .font(.system(size: compact ? 40 : 48, weight: .heavy, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(n.1.color)
                                    .contentTransition(reduce ? ContentTransition.identity : ContentTransition.numericText(countsDown: true))
                                    .animation(Motion.quick(reduce), value: cd.value)
                                if let u = cd.unit { Text(u).font(.headline).foregroundStyle(Theme.muted) }
                            }
                            .lineLimit(1).minimumScaleFactor(0.5)
                            Text("\(n.1.title) · \(Fmt.date(n.0, "EEEE d"))")
                                .font(.caption.weight(.semibold)).foregroundStyle(Theme.ink).lineLimit(1).minimumScaleFactor(0.7)
                            Text(Fmt.range(start: Calendar.current.component(.hour, from: n.0), length: s.shiftLength))
                                .font(.caption2).foregroundStyle(Theme.muted).lineLimit(1).minimumScaleFactor(0.7)
                        } else if me == nil {
                            Image(systemName: "person.crop.circle.badge.questionmark").font(.title2).foregroundStyle(Theme.muted)
                            Text(L("اربط حسابك بموظف لعرض مناوباتك")).font(.caption).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                        } else {
                            Image(systemName: "moon.zzz").font(.title2).foregroundStyle(Theme.muted)
                            Text(L("لا توجد مناوبات قادمة")).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
                            Text(L("صوّر الجدول الورقي لإضافتها")).font(.caption2).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                        }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L("مدار يومك"))
                .accessibilityValue(accessibilityValue(next: next, current: current != nil, cd: cd))

                HStack(spacing: 14) {
                    CodeDot(code: .day); CodeDot(code: .evening); CodeDot(code: .night)
                    Spacer(minLength: 0)
                    if me != nil {
                        Text(todayCode == .empty ? L("اليوم: لا شيء مسجّل") : L("اليوم: %@", todayCode.title))
                            .font(.caption.weight(.semibold)).foregroundStyle(todayCode.isWorking ? todayCode.color : Theme.muted)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                }
            }
            .padding(.vertical, 6)
            .card()
        }
    }

    private func accessibilityValue(next: (Date, ShiftCode)?, current: Bool, cd: (value: String, unit: String?)?) -> String {
        guard let next, let cd else { return L("لا توجد مناوبات قادمة") }
        let when = cd.unit.map { "\(cd.value) \($0)" } ?? cd.value
        return "\(current ? L("تنتهي بعد") : L("المناوبة القادمة بعد")) \(when)، \(next.1.title) \(Fmt.date(next.0, "EEEE d"))"
    }
}
