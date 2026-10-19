import SwiftUI

struct InviteCodeRow: View {
    let code: String
    let name: String
    let number: String?
    @State private var copied = false
    var shareText: String {
        var t = "مرحبًا \(name)،\nلتفعيل حسابك في مِناوب: افتح التطبيق ← «تفعيل حساب بدعوة» ← أدخل الكود: \(code)"
        if let c = Session.shared.remote?.hospital?.code { t += "\nبعد التفعيل ادخل برقمك الوظيفي \(number ?? "") ورمز المستشفى \(c)" }
        return t + "\nmunawib://join?code=\(code)"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(code).font(.system(.title, design: .monospaced).bold()).textSelection(.enabled)
                Spacer()
                Button {
                    UIPasteboard.general.string = code; Haptics.success()
                    withAnimation(.snappy) { copied = true }
                    Task { try? await Task.sleep(for: .seconds(1.5)); withAnimation { copied = false } }
                } label: { Label(copied ? "تم النسخ" : "نسخ", systemImage: copied ? "checkmark" : "doc.on.doc") }
                .buttonStyle(.bordered).tint(copied ? .green : Theme.primary)
            }
            ShareLink(item: shareText) { Label("مشاركة الدعوة", systemImage: "square.and.arrow.up") }
            Text("أعطِ هذا الكود للموظف ليختار كلمة مروره. لن يستطيع الدخول قبل التفعيل.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
