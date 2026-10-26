import SwiftUI

/// «مدار» visual system: near-black surfaces, amber for day shifts, indigo for night, pink for evening.
/// The app is dark-only (see `preferredColorScheme(.dark)` on the root), so the tokens are constants.
enum Theme {
    // Shift hues (also the accent system: amber is the primary action colour)
    static let amber = Color(hex: 0xFBBF24)
    static let indigo = Color(hex: 0x6366F1)
    static let pink = Color(hex: 0xEC4899)

    static let primary = amber
    static let onPrimary = Color(hex: 0x0E0F12)           // text on amber
    static let primaryLight = Color(hex: 0xFDE68A)        // amber highlight (digits, rings)
    static let primaryPale = Color.black.opacity(0.62)    // captions on amber tiles

    // Surfaces
    static let background = Color(hex: 0x0E0F12)
    static let card = Color(hex: 0x16181D)
    static let surfaceRaised = Color(hex: 0x1D2027)
    static let border = Color.white.opacity(0.08)
    static let borderStrong = Color.white.opacity(0.14)
    static let track = Color.white.opacity(0.06)

    // Text
    static let ink = Color(hex: 0xF4F4F5)
    static let muted = Color(hex: 0x9CA3AF)
    static let faint = Color(hex: 0x6B7280)

    // Status
    static let success = Color(hex: 0x34D399)
    static let coral = Color(hex: 0xF87171)
    static let danger = Color(hex: 0xF87171)
    static let dangerSoft = Color(hex: 0xF87171).opacity(0.14)
    static let dangerBorder = Color(hex: 0xF87171).opacity(0.35)

    // Legacy names kept for the shared tiles / drawer
    static let navy = Color(hex: 0x16181D)
    static let navySoft = Color(hex: 0x1D2027)
    static let slate = Color(hex: 0x9CA3AF)
    static let tileDark = Color(hex: 0x1D2027)
    static let chipRest = Color(hex: 0x2A2E37)

    static let radius: CGFloat = 20

    static func dynamic(light: UInt32, dark: UInt32) -> Color { Color(hex: dark) }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension Color {
    init(hex: UInt32) { self.init(uiColor: UIColor(hex: hex)) }
}

/// Flat dark card: raised surface, hairline border, 20pt continuous corners, no drop shadow.
struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }
}

extension View { func card() -> some View { modifier(CardModifier()) } }

struct IconTile: View {
    let symbol: String
    var tint: Color = Theme.primary
    var size: CGFloat = 48
    var body: some View {
        Image(systemName: symbol)
            .font(.title3.weight(.semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct StatusBadge: View {
    let status: RosterStatus
    var body: some View {
        let tint = status == .approved ? Theme.success : Theme.amber
        Text(status.title)
            .font(.caption.bold())
            .padding(.horizontal, 10).padding(.vertical, 5)
            .foregroundStyle(tint)
            .background(tint.opacity(0.14), in: Capsule())
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { PrimaryBody(configuration: configuration) }
    private struct PrimaryBody: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var enabled
        var body: some View {
            configuration.label
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 52)
                .foregroundStyle(enabled ? Theme.onPrimary : Theme.muted)
                .background(enabled ? Theme.primary : Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .opacity(configuration.isPressed ? 0.9 : 1)
                .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
        }
    }
}

struct OutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(Theme.ink)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.borderStrong, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

extension ShiftCode {
    var color: Color {
        switch self {
        case .day: return Theme.amber
        case .evening: return Theme.pink
        case .night: return Theme.indigo
        case .rest: return Color(hex: 0x64748B)
        case .leave: return Color(hex: 0x0EA5E9)
        case .course: return Color(hex: 0x14B8A6)
        case .empty: return Theme.faint
        }
    }
    /// Chip fill on dark tiles (week strip, roster cells).
    var chipBackground: Color {
        switch self {
        case .rest, .empty: return Theme.chipRest
        default: return color
        }
    }
    var chipForeground: Color { self == .day ? Theme.onPrimary : .white }
    var symbol: String {
        switch self {
        case .day: return "sun.max.fill"
        case .evening: return "sunset.fill"
        case .night: return "moon.stars.fill"
        case .rest: return "bed.double.fill"
        case .leave: return "airplane"
        case .course: return "book.fill"
        case .empty: return "minus"
        }
    }
}

enum Fmt {
    static var ar: Locale { LanguageManager.current.locale }
    static func date(_ d: Date, _ format: String) -> String {
        let f = DateFormatter(); f.locale = ar; f.dateFormat = format; return f.string(from: d)
    }
    static func hours(_ h: Double) -> String { h == h.rounded() ? "\(Int(h))" : String(format: "%.1f", h) }
    /// "5:00 PM" style label for a whole hour of the day.
    static func clock(_ hour: Int) -> String {
        let d = Calendar.current.date(bySettingHour: hour % 24, minute: 0, second: 0, of: Date()) ?? Date()
        return date(d, "h:mm a")
    }
    /// "7 ص – 7 م" style range for a shift that starts at `hour` and lasts `length` hours.
    static func range(start hour: Int, length: Int) -> String {
        "\(clock(hour)) – \(clock((hour + length) % 24))"
    }
}

/// Compact countdown used by the dial: "7:28" under 48h, otherwise whole days.
enum Countdown {
    static func parts(until target: Date, from now: Date = Date()) -> (value: String, unit: String?) {
        let secs = max(0, Int(target.timeIntervalSince(now)))
        let h = secs / 3600, m = (secs % 3600) / 60
        if h >= 48 { return ("\(h / 24)", L("يوم")) }
        return (String(format: "%d:%02d", h, m), nil)
    }
}

/// Motion tokens: short ease-out entries, interruptible, and a Reduce-Motion fallback.
enum Motion {
    static let entry = Animation.easeOut(duration: 0.28)
    static let quick = Animation.easeOut(duration: 0.18)
    static let draw = Animation.easeOut(duration: 0.3)
    static func entry(_ reduce: Bool) -> Animation? { reduce ? nil : entry }
    static func quick(_ reduce: Bool) -> Animation? { reduce ? nil : quick }
}

/// Fades/slides content in once on first appearance (ease-out, under 300ms). Disabled under Reduce Motion.
struct EntryModifier: ViewModifier {
    var index: Int = 0
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduce
    func body(content: Content) -> some View {
        content
            .opacity(shown || reduce ? 1 : 0)
            .offset(y: shown || reduce ? 0 : 10)
            .onAppear {
                guard !shown else { return }
                withAnimation(Motion.entry.delay(Double(min(index, 6)) * 0.035)) { shown = true }
            }
    }
}

extension View {
    /// Staggered ease-out entry; `index` offsets siblings by 35ms each (capped so the last tile still lands under 300ms + stagger).
    func entry(_ index: Int = 0) -> some View { modifier(EntryModifier(index: index)) }
}
