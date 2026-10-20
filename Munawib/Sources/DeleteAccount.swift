import SwiftUI

struct DeleteAccountCard: View {
    @State private var confirm = false
    @State private var password = ""
    @State private var error: String?
    @State private var busy = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L("حذف الحساب"), systemImage: "person.crop.circle.badge.xmark").font(.title3.bold()).foregroundStyle(.red)
            Text(Session.shared.me?.role == "admin" ? L("يحذف حسابك وبياناتك نهائيًا. إذا كنت المدير الوحيد فسيتم حذف بيانات المستشفى كاملة.") : L("يحذف حسابك وبياناتك (الساعات، الطلبات، الأجهزة) نهائيًا."))
                .font(.footnote).foregroundStyle(.secondary)
            Button(role: .destructive) { confirm = true } label: { Label(L("حذف حسابي نهائيًا"), systemImage: "trash") }
                .buttonStyle(.bordered)
        }
        .card()
        .alert(L("تأكيد حذف الحساب"), isPresented: $confirm) {
            SecureField(L("كلمة المرور"), text: $password)
            Button(L("حذف"), role: .destructive) {
                Task {
                    busy = true; defer { busy = false }
                    do { try await Session.shared.deleteAccount(password: password); UINotificationFeedbackGenerator().notificationOccurred(.success) }
                    catch { self.error = (error as? LocalizedError)?.errorDescription; password = "" }
                }
            }
            Button(L("إلغاء"), role: .cancel) { password = "" }
        } message: { Text(L("لا يمكن التراجع عن هذا الإجراء.")) }
        .alert(L("تعذّر الحذف"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button(L("حسنًا")) {} } message: { Text(error ?? "") }
    }
}
