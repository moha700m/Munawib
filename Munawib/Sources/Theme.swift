import SwiftUI

/// «بينتو» visual system: navy base, health-green accent, flat bordered tiles on a cool off-white canvas.
enum Theme {
    // Accent
    static let primary = Color(hex: 0x059669)        // health green
    static let primaryLight = Color(hex: 0x34D399)   // mint (bars, hero digits)
    static let primaryPale = Color(hex: 0xD1FAE5)    // captions on green tiles
    // Base
    static let navy = Color(hex: 0x0F172A)
    static let navySoft = Color(hex: 0x1E293B)
    static let slate = Color(hex: 0x94A3B8)          // captions on navy tiles
    // Shift / status hues
    static let amber = Color(hex: 0xF59E0B)
    static let indigo = Color(hex: 0x6366F1)
    static let coral = Color(hex: 0xF87171)
    static let danger = Color(hex: 0xB91C1C)
    static let dangerBorder = Color(hex: 0xFCA5A5)

    static let radius: CGFloat = 20

    static var background: Color { dynamic(light: 0xF3F5F4, dark: 0x0B1220) }
    static var card: Color { dynamic(light: 0xFFFFFF, dark: 0x151E2E) }
    static var border: Color { Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor.white.withAlphaComponent(0.09) : UIColor(hex: 0xE2E8F0) }) }
    static var ink: Color { dynamic(light: 0x0F172A, dark: 0xF1F5F9) }
    static var muted: Color { dynamic(light: 0x475569, dark: 0x94A3B8) }
    static var dangerSoft: Color { Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0xB91C1C).withAlphaComponent(0.22) : UIColor(hex: 0xFEE2E2) }) }
    /// Navy tiles need to stay distinguishable from the dark-mode canvas.
    static var tileDark: Color { dynamic(light: 0x0F172A, dark: 0x1E293B) }
    /// Neutral chip on a navy tile (rest / unassigned days).
    static var chipRest: Color { dynamic(light: 0x1E293B, dark: 0x334155) }

    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension Color {
    init(hex: UInt32) { self.init(uiColor: UIColor(hex: hex)) }
}

/// Flat bento card: white surface, hairline border, 20pt continuous corners, no drop shadow.
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
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct StatusBadge: View {
    let status: RosterStatus
    var body: some View {
        Text(status.title)
            .font(.caption.bold())
            .padding(.horizontal, 10).padding(.vertical, 5)
            .foregroundStyle(status == .approved ? Theme.primary : Theme.amber)
            .background((status == .approved ? Theme.primary : Theme.amber).opacity(0.14), in: Capsule())
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
                .foregroundStyle(.white)
                .background(enabled ? Theme.primary : Color.gray.opacity(0.45), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .opacity(configuration.isPressed ? 0.9 : 1)
                .animation(.snappy(duration: 0.15), value: configuration.isPressed)
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
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.border, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

extension ShiftCode {
    var color: Color {
        switch self {
        case .day: return Theme.amber
        case .night: return Theme.indigo
        case .rest: return Color(hex: 0x64748B)
        case .leave: return Color(hex: 0x0EA5E9)
        case .course: return Color(hex: 0xEC4899)
        case .empty: return .secondary
        }
    }
    /// Chip colours on navy tiles (week strip): amber day, indigo night, slate otherwise.
    var chipBackground: Color {
        switch self {
        case .day: return Theme.amber
        case .night: return Theme.indigo
        case .leave: return Color(hex: 0x0EA5E9)
        case .course: return Color(hex: 0xEC4899)
        case .rest, .empty: return Theme.chipRest
        }
    }
    var chipForeground: Color { self == .day ? Theme.navy : .white }
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
}

/// Compact countdown used by the shifts hero: "7:28" under 48h, otherwise whole days.
enum Countdown {
    static func parts(until target: Date, from now: Date = Date()) -> (value: String, unit: String?) {
        let secs = max(0, Int(target.timeIntervalSince(now)))
        let h = secs / 3600, m = (secs % 3600) / 60
        if h >= 48 { return ("\(h / 24)", L("يوم")) }
        return (String(format: "%d:%02d", h, m), nil)
    }
}
