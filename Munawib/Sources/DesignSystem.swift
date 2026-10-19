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
            .overlay(RoundedRectangle(cornerRadius: DS.radiusM, style: .continuous).stroke(.quaternary))
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
                    .accessibilityLabel("مسح")
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
                .accessibilityLabel(show ? "إخفاء كلمة المرور" : "إظهار كلمة المرور")
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
                .accessibilityLabel("الخطوة \(step) من \(total)")
                Text("الخطوة \(step) من \(total)").font(.caption.weight(.semibold)).foregroundStyle(Theme.primary)
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

/// Prominent "today / next shift" card used on home & my shifts.
struct TodayShiftCard: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        if let me = store.myEmployee {
            let shifts = store.upcomingShifts(for: me.id)
            let now = Date()
            let current = shifts.first { $0.0 <= now && now < $0.0.addingTimeInterval(Double(store.data.settings.shiftLength) * 3600) }
            let next = current ?? shifts.first { $0.0 > now }
            VStack(alignment: .leading, spacing: DS.m) {
                HStack {
                    Label(current != nil ? "مناوبتك الآن" : "مناوبتك القادمة", systemImage: current != nil ? "dot.radiowaves.left.and.right" : "clock")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.9))
                    Spacer()
                    Text(me.name).font(.caption).foregroundStyle(.white.opacity(0.8))
                }
                if let n = next {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(n.1.title).font(.title.bold())
                            Text(Fmt.date(n.0, "EEEE d MMMM · h:mm a")).font(.subheadline)
                        }
                        Spacer()
                        Image(systemName: n.1 == .night ? "moon.stars.fill" : "sun.max.fill").font(.system(size: 38)).symbolRenderingMode(.hierarchical)
                    }
                    if current == nil {
                        HStack(spacing: 6) { Text("يبدأ خلال"); Text(n.0, style: .relative).monospacedDigit().bold() }.font(.callout)
                    }
                } else {
                    Text("لا توجد مناوبات قادمة").font(.title3.bold())
                }
            }
            .foregroundStyle(.white)
            .padding(DS.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [Theme.primary, Theme.navy], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: DS.radiusL, style: .continuous))
            .shadow(color: Theme.primary.opacity(0.25), radius: 14, y: 6)
            .accessibilityElement(children: .combine)
        }
    }
}
