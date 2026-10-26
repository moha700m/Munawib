import SwiftUI

struct InviteCodeRow: View {
    let code: String
    let name: String
    let number: String?
    @State private var copied = false
    var shareText: String {
        var t = L("مرحبًا %1$@،\nلتفعيل حسابك في مِناوب: افتح التطبيق ← «تفعيل حساب بدعوة» ← أدخل الكود: %2$@", "\(name)", "\(code)")
        if let c = Session.shared.remote?.hospital?.code { t += L("\nبعد التفعيل ادخل برقمك الوظيفي %1$@ ورمز المستشفى %2$@", "\(number ?? "")", "\(c)") }
        return t + "\nmunawib://join?code=\(code)"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(code).font(.system(.title, design: .monospaced).bold()).textSelection(.enabled)
                Spacer()
                Button {
                    UIPasteboard.general.string = code; Haptics.success()
                    withAnimation(Motion.entry) { copied = true }
                    Task { try? await Task.sleep(for: .seconds(1.5)); withAnimation { copied = false } }
                } label: { Label(copied ? L("تم النسخ") : L("نسخ"), systemImage: copied ? "checkmark" : "doc.on.doc") }
                .buttonStyle(.bordered).tint(copied ? .green : Theme.primary)
            }
            ShareLink(item: shareText) { Label(L("مشاركة الدعوة"), systemImage: "square.and.arrow.up") }
            Text(L("أعطِ هذا الكود للموظف ليختار كلمة مروره. لن يستطيع الدخول قبل التفعيل.")).font(.caption).foregroundStyle(.secondary)
        }
    }
}
