import SwiftUI

// MARK: - 12-hour dial

/// One coloured band on the dial, in hours of the day (0…24); may wrap past midnight.
struct DialArc: Identifiable {
    let code: ShiftCode
    let start: Double
    let length: Double
    var emphasized: Bool = false
    var id: String { "\(code.rawValue)-\(start)-\(emphasized)" }
}

/// A normal 12-hour clock face (12 at the top, hours clockwise) with two concentric tracks:
/// the outer track is the morning half of the day (ص, 00:00–12:00) and the inner track the
/// afternoon/night half (م, 12:00–24:00). A 12-hour shift therefore reads as one spiral — day
/// starts on the outer track at 5 and ends on the inner track at 5 — so AM/PM is never ambiguous.
/// The emphasized arc (current or next shift) draws itself once on first appearance.
struct MadarDial<Center: View>: View {
    let arcs: [DialArc]
    let now: Date
    var size: CGFloat = 250
    var lineWidth: CGFloat = 13
    @ViewBuilder let center: () -> Center

    @State private var progress: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.layoutDirection) private var direction

    private let trackGap: CGFloat = 4

    /// One piece of an arc on a single track, as fractions of the 12-hour circle.
    private struct Piece: Identifiable {
        let id: Int
        let track: Int      // 0 = outer (AM), 1 = inner (PM)
        let from: CGFloat
        let to: CGFloat
    }

    private var outerRadius: CGFloat { size / 2 - lineWidth / 2 }
    private var innerRadius: CGFloat { outerRadius - lineWidth - trackGap }
    private var tickRadius: CGFloat { innerRadius - lineWidth / 2 - 8 }
    private var labelRadius: CGFloat { tickRadius - 8 }

    var body: some View {
        ZStack {
            track(radius: outerRadius)
            track(radius: innerRadius)
            ForEach(arcs.filter { !$0.emphasized }) { arc in band(arc, drawn: 1) }
            ForEach(arcs.filter(\.emphasized)) { arc in band(arc, drawn: progress) }
            ticks
            hourLabels
            periodBadge(radius: outerRadius, pm: false)
            periodBadge(radius: innerRadius, pm: true)
            nowMarker
            center()
                .environment(\.layoutDirection, direction)
                .frame(width: (labelRadius - 10) * 2)
        }
        .frame(width: size, height: size)
        .environment(\.layoutDirection, .leftToRight)
        .onAppear {
            guard progress < 1 else { return }
            if reduce { progress = 1 } else { withAnimation(Motion.draw) { progress = 1 } }
        }
    }

    // MARK: Pieces

    private func track(radius: CGFloat) -> some View {
        Circle().stroke(Theme.track, lineWidth: lineWidth).frame(width: radius * 2, height: radius * 2)
    }

    private var ticks: some View {
        ForEach(0..<12, id: \.self) { h in
            let major = h % 3 == 0
            Capsule()
                .fill(major ? Theme.muted : Theme.borderStrong)
                .frame(width: major ? 2 : 1, height: major ? 7 : 5)
                .offset(y: -tickRadius)
                .rotationEffect(.degrees(Double(h) * 30))
        }
    }

    private var hourLabels: some View {
        ZStack {
            Text("12").offset(y: -labelRadius)
            Text("3").offset(x: labelRadius)
            Text("6").offset(y: labelRadius)
            Text("9").offset(x: -labelRadius)
        }
        .font(.caption2.weight(.semibold)).monospacedDigit()
        .foregroundStyle(Theme.faint)
    }

    /// Small ص / م pill sitting on the track at the 11 o'clock position so each ring names its half of the day.
    private func periodBadge(radius: CGFloat, pm: Bool) -> some View {
        let f = DateFormatter(); f.locale = Fmt.ar
        let text = pm ? f.pmSymbol ?? "PM" : f.amSymbol ?? "AM"
        return Text(text)
            .font(.system(size: 9, weight: .bold)).monospacedDigit()
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Theme.card, in: Capsule())
            .overlay(Capsule().stroke(Theme.borderStrong, lineWidth: 1))
            .offset(y: -radius)
            .rotationEffect(.degrees(-45))
            .accessibilityHidden(true)
    }

    private var nowMarker: some View {
        let c = Calendar.current.dateComponents([.hour, .minute], from: now)
        let hour = Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
        let pm = hour >= 12
        return Circle()
            .fill(Theme.ink)
            .frame(width: 9, height: 9)
            .overlay(Circle().stroke(Theme.background, lineWidth: 2))
            .offset(y: -(pm ? innerRadius : outerRadius))
            .rotationEffect(.degrees(hour.truncatingRemainder(dividingBy: 12) * 30))
    }

    /// Splits a window of `length` hours starting at `start` (24h clock) into pieces on the AM / PM tracks,
    /// cutting at noon and midnight. Pieces are in time order so a partially `drawn` arc grows forward.
    private func pieces(start: Double, length: Double) -> [Piece] {
        var out: [Piece] = []
        var s = start.truncatingRemainder(dividingBy: 24); if s < 0 { s += 24 }
        var remaining = min(max(0, length), 24)
        var i = 0
        while remaining > 0.0001 && i < 6 {
            let track = Int(floor(s / 12)) % 2
            let trackEnd = Double(track + 1) * 12
            let e = min(trackEnd, s + remaining)
            out.append(Piece(id: i, track: track, from: CGFloat((s - Double(track) * 12) / 12), to: CGFloat((e - Double(track) * 12) / 12)))
            remaining -= (e - s)
            s = e >= 24 ? 0 : e
            i += 1
        }
        return out
    }

    @ViewBuilder private func band(_ arc: DialArc, drawn: CGFloat) -> some View {
        ForEach(pieces(start: arc.start, length: arc.length * Double(drawn))) { piece in
            let r = piece.track == 0 ? outerRadius : innerRadius
            Circle()
                .trim(from: piece.from, to: piece.to)
                .stroke(arc.code.color.opacity(arc.emphasized ? 1 : 0.2),
                        style: StrokeStyle(lineWidth: arc.emphasized ? lineWidth : lineWidth - 5, lineCap: .round))
                .frame(width: r * 2, height: r * 2)
                .rotationEffect(.degrees(-90))
                .shadow(color: arc.emphasized ? arc.code.color.opacity(0.4) : .clear, radius: 8)
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
                MadarDial(arcs: arcs, now: now, size: compact ? 216 : 250) {
                    VStack(spacing: 4) {
                        if let n = next, let cd {
                            Text(current != nil ? L("تنتهي بعد") : L("المناوبة القادمة بعد"))
                                .font(.caption).foregroundStyle(Theme.muted).lineLimit(1).minimumScaleFactor(0.7)
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(cd.value)
                                    .font(.system(size: compact ? 34 : 42, weight: .heavy, design: .rounded))
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
                .accessibilityHint(L("الحلقة الخارجية صباحًا والداخلية مساءً"))
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
