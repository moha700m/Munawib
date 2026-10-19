import SwiftUI

enum Theme {
    static let primary = Color(red: 0.07, green: 0.51, blue: 0.47)
    static let primaryLight = Color(red: 0.10, green: 0.60, blue: 0.56)
    static let navy = Color(red: 0.06, green: 0.16, blue: 0.24)
    static let radius: CGFloat = 20
    static var background: Color { Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.05, green: 0.08, blue: 0.10, alpha: 1) : UIColor(red: 0.95, green: 0.97, blue: 0.97, alpha: 1) }) }
    static var card: Color { Color(uiColor: .secondarySystemGroupedBackground) }
    static var border: Color { Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor.white.withAlphaComponent(0.08) : UIColor.black.withAlphaComponent(0.06) }) }
}

struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).stroke(Theme.border, lineWidth: 1))
            .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
    }
}

extension View { func card() -> some View { modifier(CardModifier()) } }

struct IconTile: View {
    let symbol: String
    var tint: Color = Theme.primary
    var size: CGFloat = 48
    var body: some View {
        Image(systemName: symbol)
            .font(.title3)
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct StatusBadge: View {
    let status: RosterStatus
    var body: some View {
        Text(status.title)
            .font(.caption.bold())
            .padding(.horizontal, 10).padding(.vertical, 5)
            .foregroundStyle(status == .approved ? Color.green : Color.orange)
            .background((status == .approved ? Color.green : Color.orange).opacity(0.15), in: Capsule())
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
                .background(LinearGradient(colors: enabled ? [Theme.primaryLight, Theme.primary] : [Color.gray.opacity(0.45), Color.gray.opacity(0.45)], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: enabled ? Theme.primary.opacity(0.25) : .clear, radius: 8, y: 4)
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .animation(.snappy(duration: 0.15), value: configuration.isPressed)
        }
    }
}

struct OutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(Theme.primary)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.primary.opacity(0.3)))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

extension ShiftCode {
    var color: Color {
        switch self {
        case .day: return .blue
        case .night: return .purple
        case .rest: return .gray
        case .leave: return .orange
        case .course: return .pink
        case .empty: return .secondary
        }
    }
}

enum Fmt {
    static let ar = Locale(identifier: "ar")
    static func date(_ d: Date, _ format: String) -> String {
        let f = DateFormatter(); f.locale = ar; f.dateFormat = format; return f.string(from: d)
    }
    static func hours(_ h: Double) -> String { h == h.rounded() ? "\(Int(h))" : String(format: "%.1f", h) }
}
