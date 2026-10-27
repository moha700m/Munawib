import SwiftUI
import UIKit

/// Design tokens: spacing, radii, typography helpers.
enum DS {
    static let xs: CGFloat = 4, s: CGFloat = 8, m: CGFloat = 12, l: CGFloat = 20, xl: CGFloat = 32
    static let radiusS: CGFloat = 10, radiusM: CGFloat = 14, radiusL: CGFloat = 20
}

enum Haptics {
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
}

struct DSFieldChrome: ViewModifier {
    @FocusState private var dummy: Bool
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, DS.m)
            .frame(minHeight: 54)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: DS.radiusM, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.radiusM, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }
}
extension View { func dsFieldChrome() -> some View { modifier(DSFieldChrome()) } }

struct DSField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var ltr: Bool = false
    var numeric: Bool = false
    var autofocus: Bool = false
    var keyboard: UIKeyboardType = .default
    var uppercase: Bool = false
    var contentType: UITextContentType? = nil
    var id: String? = nil
    var returnKey: UIReturnKeyType = .next
    var onReturn: (() -> Void)? = nil
    var body: some View {
        HStack(spacing: DS.s) {
            Image(systemName: icon).foregroundStyle(.secondary).frame(width: 22).accessibilityHidden(true)
            AppTextField(placeholder: placeholder, text: $text, keyboard: keyboard, digitsOnly: numeric, uppercase: uppercase, ltr: ltr, contentType: contentType, returnKey: returnKey, identifier: id, focusOnAppear: autofocus, onReturn: onReturn)
                .frame(minHeight: 44)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                    .accessibilityLabel(L("مسح"))
            }
        }
        .dsFieldChrome()
    }
}

struct DSSecureField: View {
    let placeholder: String
    @Binding var text: String
    var id: String? = nil
    var contentType: UITextContentType = .newPassword
    var onReturn: (() -> Void)? = nil
    @State private var show = false
    var body: some View {
        HStack(spacing: DS.s) {
            Image(systemName: "lock").foregroundStyle(.secondary).frame(width: 22).accessibilityHidden(true)
            AppTextField(placeholder: placeholder, text: $text, secure: !show, contentType: contentType, returnKey: .go, identifier: id, onReturn: onReturn)
                .frame(minHeight: 44)
            Button { show.toggle() } label: { Image(systemName: show ? "eye.slash" : "eye").foregroundStyle(.secondary).frame(width: 44, height: 44) }
                .accessibilityLabel(show ? L("إخفاء كلمة المرور") : L("إظهار كلمة المرور"))
        }
        .dsFieldChrome()
    }
}

struct StepHeader: View {
    let step: Int?
    let total: Int
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: DS.s) {
            if let step {
                HStack(spacing: DS.xs) {
                    ForEach(1...total, id: \.self) { i in
                        Capsule().fill(i <= step ? Theme.primary : Color.secondary.opacity(0.25)).frame(height: 4)
                    }
                }
                .accessibilityLabel(L("الخطوة %1$@ من %2$@", "\(step)", "\(total)"))
                Text(L("الخطوة %1$@ من %2$@", "\(step)", "\(total)")).font(.caption.weight(.semibold)).foregroundStyle(Theme.primary)
            }
            Text(title).font(.title2.bold())
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

/// Shimmering placeholder for loading states.
struct Skeleton: View {
    var height: CGFloat = 16
    @State private var phase = false
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.secondary.opacity(phase ? 0.12 : 0.22))
            .frame(height: height)
            .onAppear { if !reduce { withAnimation(.easeInOut(duration: 0.9).repeatForever()) { phase = true } } }
            .accessibilityHidden(true)
    }
}

// MARK: - Bento grid

/// Bento grid metrics: a 4-column grid with 82pt rows and 10pt gutters (mirrors the design mock).
enum Bento {
    static let row: CGFloat = 82
    static let gap: CGFloat = 10
    static let padding: CGFloat = 12
    static func height(_ rows: Int) -> CGFloat { row * CGFloat(rows) + gap * CGFloat(max(0, rows - 1)) }
    static func span(_ n: Int, col: CGFloat) -> CGFloat { col * CGFloat(n) + gap * CGFloat(max(0, n - 1)) }

    static let value = Font.system(size: 26, weight: .heavy, design: .rounded)
    static let small = Font.system(size: 18, weight: .heavy, design: .rounded)
    static let hero = Font.system(size: 48, weight: .heavy, design: .rounded)
    static let heroLarge = Font.system(size: 56, weight: .heavy, design: .rounded)
}

/// Tile styles: `light` = base card, `dark` = raised card, `green` = amber accent (primary action), `danger` = coral tint.
enum BentoStyle {
    case light, dark, green, danger
    var background: Color {
        switch self { case .light: return Theme.card; case .dark: return Theme.tileDark; case .green: return Theme.primary; case .danger: return Theme.dangerSoft }
    }
    var border: Color {
        switch self { case .light: return Theme.border; case .dark: return Theme.borderStrong; case .danger: return Theme.dangerBorder; case .green: return .clear }
    }
    var foreground: Color {
        switch self { case .light, .danger, .dark: return Theme.ink; case .green: return Theme.onPrimary }
    }
    var caption: Color {
        switch self { case .light, .danger: return Theme.muted; case .dark: return Theme.slate; case .green: return Theme.primaryPale }
    }
}

struct BentoTileModifier: ViewModifier {
    let style: BentoStyle
    var rows: Int?
    func body(content: Content) -> some View {
        content
            .padding(Bento.padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .frame(height: rows.map(Bento.height))
            .foregroundStyle(style.foreground)
            .background(style.background, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).stroke(style.border, lineWidth: 1))
    }
}

extension View {
    /// Wraps content in a bento tile. `rows` fixes the height to the grid; omit for intrinsic height.
    func bentoTile(_ style: BentoStyle = .light, rows: Int? = nil) -> some View { modifier(BentoTileModifier(style: style, rows: rows)) }
    func bentoCaption(_ style: BentoStyle = .light) -> some View { font(.caption).foregroundStyle(style.caption).lineLimit(1).minimumScaleFactor(0.8) }
}

/// One horizontal band of the grid. Hands the content a column unit width so tiles can span 1–4 columns.
struct BentoRow<Content: View>: View {
    var rows: Int = 1
    @ViewBuilder let content: (CGFloat) -> Content
    var body: some View {
        GeometryReader { geo in
            let col = max(0, (geo.size.width - 3 * Bento.gap) / 4)
            HStack(spacing: Bento.gap) { content(col) }
        }
        .frame(height: Bento.height(rows))
    }
}

/// Caption-over-number tile.
struct BentoStat: View {
    let caption: String
    let value: String
    var footnote: String? = nil
    var style: BentoStyle = .light
    var valueFont: Font = Bento.value
    var valueColor: Color? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(caption).bentoCaption(style)
            Text(value).font(valueFont).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                .foregroundStyle(valueColor ?? style.foreground)
            if let footnote {
                Spacer(minLength: 0)
                Text(footnote).bentoCaption(style)
            }
        }
        .bentoTile(style)
        .accessibilityElement(children: .combine)
    }
}

struct BentoPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Icon + bold label action tile (green = primary action, light = secondary).
struct BentoAction: View {
    let title: String
    let symbol: String
    var style: BentoStyle = .light
    var subtitle: String? = nil
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: symbol).font(.system(size: 18, weight: .semibold)).accessibilityHidden(true)
                Spacer(minLength: 0)
                Text(title).font(.subheadline.weight(.heavy)).lineLimit(2).minimumScaleFactor(0.75).multilineTextAlignment(.leading)
                if let subtitle { Text(subtitle).bentoCaption(style) }
            }
            .bentoTile(style)
        }
        .buttonStyle(BentoPressStyle())
    }
}
