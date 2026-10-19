import SwiftUI

struct AuthView: View {
    @Environment(AppStore.self) private var store
    @State private var mode: Mode = .login
    @State private var email = ""
    @State private var password = ""
    @State private var name = ""
    @State private var hospital = ""
    @State private var department = ""
    @State private var code = ""
    @State private var byNumber = true
    @State private var hospitalCode = Session.shared.savedHospitalCode
    @State private var number = ""
    @State private var hnName = ""
    @State private var hnNumber = ""
    @State private var busy = false
    @State private var error: String?
    @FocusState private var focus: Bool
    private let session = Session.shared

    enum Mode: String, CaseIterable, Identifiable { case login, join, signup
        var id: String { rawValue }
        var title: String { self == .login ? "دخول" : self == .join ? "انضمام بدعوة" : "تسجيل مستشفى" }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 8) {
                        IconTile(symbol: "waveform.path.ecg", tint: .white, size: 72)
                            .background(Theme.primary, in: RoundedRectangle(cornerRadius: 20))
                        Text("مِناوب").font(.largeTitle.bold())
                        Text("إدارة مناوبات المستشفى وتنبيهات الفريق").font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.top, 30)

                    Picker("", selection: $mode) { ForEach(Mode.allCases) { Text($0.title).tag($0) } }
                        .pickerStyle(.segmented)

                    VStack(spacing: 12) {
                        if mode == .signup {
                            TextField("اسم المستشفى", text: $hospital).fieldBox()
                            TextField("القسم الأول (مثال: الطوارئ)", text: $department).fieldBox()
                            TextField("اسمك", text: $name).textContentType(.name).fieldBox()
                        }
                        if mode == .login {
                            Picker("طريقة الدخول", selection: $byNumber) { Text("بالرقم الوظيفي").tag(true); Text("بالبريد (المدير)").tag(false) }
                                .pickerStyle(.segmented)
                        }
                        if mode == .signup {
                            Text("اختياري: رئيسة التمريض للقسم").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                            TextField("اسم رئيسة التمريض", text: $hnName).fieldBox()
                            TextField("رقمها الوظيفي", text: $hnNumber).keyboardType(.asciiCapableNumberPad).digitsOnly($hnNumber).fieldBox()
                        }
                        if mode == .join {
                            TextField("رمز الدعوة", text: $code).textInputAutocapitalization(.characters).autocorrectionDisabled().fieldBox()
                            Text("يعطيك المشرف رمز الدعوة بعد إضافتك في النظام.").font(.caption).foregroundStyle(.secondary)
                        }
                        if mode == .login && byNumber {
                            TextField("رمز المستشفى", text: $hospitalCode).textInputAutocapitalization(.characters).autocorrectionDisabled()
                                .environment(\.layoutDirection, .leftToRight).fieldBox()
                            TextField("الرقم الوظيفي", text: $number).keyboardType(.asciiCapableNumberPad).digitsOnly($number)
                                .environment(\.layoutDirection, .leftToRight).fieldBox()
                        } else {
                        TextField(mode == .join ? "البريد الإلكتروني (اختياري)" : "البريد الإلكتروني", text: $email)
                            .keyboardType(.emailAddress).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .environment(\.layoutDirection, .leftToRight).fieldBox()
                        }
                        SecureField("كلمة المرور (8 أحرف على الأقل)", text: $password)
                            .textContentType(mode == .login ? .password : .newPassword).fieldBox()
                    }
                    .focused($focus)
                    .card()

                    if let error { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.footnote) }

                    Button { Task { await submit() } } label: {
                        HStack { if busy { ProgressView().tint(.white) }; Text(mode.title) }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(busy || !valid)

                    Button("المتابعة بدون حساب (وضع محلي)") { session.useOffline() }
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding()
            }
            .background(Theme.background.onTapGesture { focus = false })
            .keyboardDone()
            .onAppear { if let c = session.pendingInvite { code = c; mode = .join } }
            .onChange(of: session.pendingInvite) { _, c in if let c { code = c; mode = .join } }
        }
    }

    private var valid: Bool {
        let base = email.contains("@") && password.count >= 8
        switch mode {
        case .login: return byNumber ? (hospitalCode.count >= 4 && !number.isEmpty && !password.isEmpty) : (email.contains("@") && !password.isEmpty)
        case .join: return password.count >= 8 && code.count >= 4 && (email.isEmpty || email.contains("@"))
        case .signup: return base && !hospital.isEmpty && !name.isEmpty
        }
    }

    private func submit() async {
        focus = false; busy = true; error = nil
        defer { busy = false }
        let e = email.trimmingCharacters(in: .whitespaces).lowercased()
        do {
            switch mode {
            case .login:
                if byNumber { try await session.loginEmployee(hospitalCode: hospitalCode.trimmingCharacters(in: .whitespaces).uppercased(), number: number.asciiDigits, password: password) }
                else { try await session.login(email: e, password: password) }
            case .join: try await session.join(code: code.asciiDigits.uppercased(), email: e, password: password)
            case .signup: try await session.signup(hospital: hospital, department: department.isEmpty ? "القسم الرئيسي" : department, name: name, email: e, password: password, headNurseName: hnName, headNurseNumber: hnNumber.asciiDigits)
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "تعذّر الاتصال بالخادم"
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}
