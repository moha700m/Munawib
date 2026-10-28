import SwiftUI
import LocalAuthentication

// MARK: - Saved credentials for Face ID quick login (device-only Keychain)
enum QuickLogin {
    static var enabled: Bool { get { UserDefaults.standard.bool(forKey: "faceID") } set { UserDefaults.standard.set(newValue, forKey: "faceID"); if !newValue { Keychain.set(nil, for: "ql") } } }
    static func save(identifier: String, code: String, password: String) {
        guard enabled, let d = try? JSONEncoder().encode([identifier, code, password]) else { return }
        Keychain.set(String(data: d, encoding: .utf8), for: "ql")
    }
    static var saved: [String]? { Keychain.get("ql").flatMap { try? JSONDecoder().decode([String].self, from: Data($0.utf8)) } }
    static var biometryName: String {
        let c = LAContext(); _ = c.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return c.biometryType == .touchID ? "Touch ID" : "Face ID"
    }
    static var available: Bool { LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) }
    static func authenticate() async -> Bool {
        (try? await LAContext().evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: L("الدخول السريع إلى مِناوب"))) ?? false
    }
}

// MARK: - Login
struct AuthView: View {
    enum Route: Hashable { case signup, activate }
    @State private var path: [Route] = []
    @State private var identifier = UserDefaults.standard.string(forKey: "lastIdentifier") ?? ""
    @State private var hospitalCode = Session.shared.savedHospitalCode
    @State private var password = ""
    @State private var showPassword = false
    @State private var busy = false
    @State private var error: String?
    @State private var errorIsActivation = false
    @State private var showServer = false
    @State private var showForgot = false
    @State private var faceID = QuickLogin.enabled
    @State private var focus: Field?
    enum Field { case id, code, pw }
    private let session = Session.shared

    private var isEmployeeNumber: Bool { !identifier.isEmpty && !identifier.contains("@") && identifier.asciiDigits.allSatisfy(\.isNumber) }
    private var valid: Bool { !identifier.isEmpty && !password.isEmpty && (!isEmployeeNumber || hospitalCode.count >= 4) }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: DS.l) {
                    HStack { Spacer(); LanguagePicker(compact: true) }
                    header
                    VStack(spacing: DS.m) {
                        DSField(icon: "person", placeholder: L("البريد الإلكتروني أو الرقم الوظيفي"), text: $identifier, ltr: true, keyboard: .emailAddress, contentType: .username, id: "login.identifier")
                        if isEmployeeNumber {
                            DSField(icon: "building.2", placeholder: L("رمز المستشفى"), text: $hospitalCode, ltr: true, uppercase: true, id: "login.hospitalCode")
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        DSSecureField(placeholder: L("كلمة المرور"), text: $password, id: "login.password", contentType: .password, onReturn: { Task { await submit() } })
                        HStack {
                            if QuickLogin.available {
                                Toggle(isOn: $faceID) { Label(QuickLogin.biometryName, systemImage: "faceid").font(.footnote) }
                                    .toggleStyle(.button).tint(Theme.primary)
                                    .onChange(of: faceID) { _, v in QuickLogin.enabled = v }
                            }
                            Spacer()
                            Button(L("نسيت كلمة المرور؟")) { showForgot = true }.font(.footnote.weight(.semibold))
                        }
                    }
                    .animation(Motion.entry, value: isEmployeeNumber)

                    if let error {
                        VStack(alignment: .leading, spacing: DS.s) {
                            Label(error, systemImage: "exclamationmark.circle.fill").font(.subheadline).foregroundStyle(.red)
                            if errorIsActivation { Button(L("تفعيل الحساب الآن")) { path.append(.activate) }.font(.subheadline.bold()) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(DS.m).background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: DS.radiusM, style: .continuous))
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    }

                    Button { Task { await submit() } } label: {
                        HStack(spacing: DS.s) { if busy { ProgressView().tint(Theme.onPrimary) }; Text(busy ? L("جارٍ الدخول…") : L("تسجيل الدخول")) }
                    }
                    .buttonStyle(PrimaryButtonStyle()).disabled(busy || !valid)

                    if QuickLogin.enabled, QuickLogin.saved != nil {
                        Button { Task { await quickLogin() } } label: { Label(L("الدخول بـ %@", "\(QuickLogin.biometryName)"), systemImage: "faceid") }
                            .buttonStyle(OutlineButtonStyle())
                    }

                    VStack(spacing: DS.s) {
                        HStack { Rectangle().fill(.quaternary).frame(height: 1); Text(L("أو")).font(.caption).foregroundStyle(.secondary); Rectangle().fill(.quaternary).frame(height: 1) }
                        Button { path.append(.activate) } label: { Label(L("تفعيل حساب بدعوة"), systemImage: "ticket") }.buttonStyle(OutlineButtonStyle())
                        Button { path.append(.signup) } label: { Label(L("تسجيل مستشفى جديد"), systemImage: "building.2.crop.circle") }.buttonStyle(OutlineButtonStyle())
                    }
                    Button(L("تجربة التطبيق بدون حساب")) { session.useOffline() }.font(.footnote).foregroundStyle(.secondary).padding(.top, DS.s)
                }
                .padding(DS.l)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background.ignoresSafeArea().onTapGesture { KeyboardHelper.dismiss() })
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showServer = true } label: { Image(systemName: "gearshape") }.accessibilityLabel(L("خادم المستشفى"))
                }
            }
            .keyboardDone()
            .navigationDestination(for: Route.self) { r in
                switch r { case .signup: SignupWizard(); case .activate: ActivateView() }
            }
            .sheet(isPresented: $showServer) { ServerSettingsView() }
            .alert(L("نسيت كلمة المرور؟"), isPresented: $showForgot) { Button(L("حسنًا")) {} } message: {
                Text(L("اطلب من رئيسة التمريض أو مدير النظام «إعادة تعيين» حسابك من شاشة الموظفين، وسيظهر لهم كود تفعيل جديد. ثم اختر «تفعيل حساب بدعوة» وأدخل الكود وكلمة مرور جديدة."))
            }
            .onAppear {
                if let c = session.pendingInvite, !c.isEmpty { path = [.activate] }
                switch Demo.auth {
                case "signup", "signup2", "keyboard": path = [.signup]
                case "activate": path = [.activate]
                case "loginNumber": identifier = "5002"; hospitalCode = "NR7K2Q"; password = "••••••••"
                case "error": identifier = "5002"; hospitalCode = "NR7K2Q"; error = APIError(status: 403, message: "account not activated").errorDescription; errorIsActivation = true
                default: break
                }
            }
            .onChange(of: session.pendingInvite) { _, c in if c != nil { path = [.activate] } }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.s) {
            HStack(spacing: 6) {
                ForEach([ShiftCode.day, .evening, .night], id: \.self) { c in
                    Text(c.label).font(Brand.font(15, .bold, relativeTo: .subheadline)).foregroundStyle(c.chipForeground)
                        .frame(width: 44, height: 44).background(c.chipBackground, in: Capsule())
                }
            }
            .accessibilityHidden(true)
            Text(L("جدول الجناح\nفي جيبك")).font(Brand.font(40, .bold, relativeTo: .largeTitle)).foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(L("مِناوب: جدول مناوبات المستشفى، تبديل الورديات، وتنبيه قبل كل مناوبة.")).font(Brand.font(16, relativeTo: .subheadline)).foregroundStyle(Theme.muted)
            if UserDefaults.standard.string(forKey: "serverURL") != nil {
                Label(L("خادم المستشفى الداخلي"), systemImage: "server.rack").font(.caption).foregroundStyle(Theme.primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, DS.xl)
    }

    private func submit() async {
        guard valid else { return }
        KeyboardHelper.dismiss(); busy = true; withAnimation { error = nil }
        defer { busy = false }
        do {
            try await session.login(identifier: identifier, hospitalCode: hospitalCode, password: password)
            UserDefaults.standard.set(identifier, forKey: "lastIdentifier")
            QuickLogin.save(identifier: identifier, code: hospitalCode, password: password)
            Haptics.success()
        } catch {
            let e = error as? APIError
            withAnimation(Motion.entry) {
                errorIsActivation = e?.message == "account not activated"
                self.error = e?.errorDescription ?? L("تعذّر الاتصال بالخادم")
            }
            Haptics.error()
        }
    }

    private func quickLogin() async {
        guard let s = QuickLogin.saved, s.count == 3, await QuickLogin.authenticate() else { return }
        identifier = s[0]; hospitalCode = s[1]; password = s[2]
        await submit()
    }
}

// MARK: - Signup (2 steps)
struct SignupWizard: View {
    @State private var step = 1
    @State private var hospital = ""
    @State private var department = ""
    @State private var name = ""
    @State private var number = ""
    @State private var email = ""
    @State private var password = ""
    @State private var hnName = ""
    @State private var hnNumber = ""
    @State private var busy = false
    @State private var error: String?
    @FocusState private var numberFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.l) {
                StepHeader(step: step, total: 2, title: step == 1 ? L("بيانات المستشفى") : L("حساب المدير"), subtitle: step == 1 ? L("اسم المستشفى والقسم الأول، ورئيسة التمريض إن وُجدت.") : L("ستدخل بهذا البريد أو برقمك الوظيفي."))
                if step == 1 {
                    VStack(spacing: DS.m) {
                        DSField(icon: "building.2", placeholder: L("اسم المستشفى"), text: $hospital, id: "signup.hospital")
                        DSField(icon: "square.grid.2x2", placeholder: L("القسم الأول (مثال: الطوارئ)"), text: $department)
                        Text(L("رئيسة التمريض (اختياري)")).font(.footnote.weight(.semibold)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                        DSField(icon: "person.badge.shield.checkmark", placeholder: L("اسم رئيسة التمريض"), text: $hnName)
                        DSField(icon: "number", placeholder: L("رقمها الوظيفي"), text: $hnNumber, ltr: true, numeric: true, id: "signup.hnNumber")
                    }
                    Button(L("التالي")) { withAnimation(Motion.entry) { step = 2 } }.buttonStyle(PrimaryButtonStyle()).disabled(hospital.trimmingCharacters(in: .whitespaces).isEmpty)
                } else {
                    VStack(spacing: DS.m) {
                        DSField(icon: "person", placeholder: L("اسمك"), text: $name, contentType: .name, id: "signup.name")
                        DSField(icon: "number", placeholder: L("رقمك الوظيفي (اختياري)"), text: $number, ltr: true, numeric: true, autofocus: Demo.auth == "keyboard", id: "signup.number")
                        DSField(icon: "envelope", placeholder: L("البريد الإلكتروني"), text: $email, ltr: true, keyboard: .emailAddress, contentType: .username, id: "signup.email")
                        DSSecureField(placeholder: L("كلمة المرور (8 أحرف على الأقل)"), text: $password)
                    }
                    if let error { Label(error, systemImage: "exclamationmark.circle.fill").font(.subheadline).foregroundStyle(.red) }
                    Button { Task { await submit() } } label: { HStack { if busy { ProgressView().tint(Theme.onPrimary) }; Text(L("إنشاء المستشفى")) } }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(busy || name.isEmpty || !email.contains("@") || password.count < 8)
                    Button(L("رجوع")) { withAnimation(Motion.entry) { step = 1 } }.frame(maxWidth: .infinity)
                }
            }
            .padding(DS.l).frame(maxWidth: 520).frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(L("تسجيل مستشفى جديد")).navigationBarTitleDisplayMode(.inline)
        .keyboardDone()
        .onAppear {
            if Demo.auth == "signup" && !ProcessInfo.processInfo.arguments.contains("-noprefill") { hospital = "مستشفى النور التخصصي"; department = "الطوارئ"; hnName = "نورة العتيبي"; hnNumber = "5002" }
            if Demo.auth == "signup2" || Demo.auth == "keyboard" { step = 2; name = "د. سارة القحطاني"; email = "admin@alnoor.sa"; password = "Demo-Pass-2026" }
            if Demo.auth == "keyboard" { number = "50" }
        }
    }

    private func submit() async {
        KeyboardHelper.dismiss(); busy = true; error = nil
        defer { busy = false }
        do {
            try await Session.shared.signup(hospital: hospital, department: department.isEmpty ? L("القسم الرئيسي") : department, name: name, email: email.trimmingCharacters(in: .whitespaces).lowercased(), password: password, adminNumber: number.asciiDigits, headNurseName: hnName, headNurseNumber: hnNumber.asciiDigits)
            UserDefaults.standard.set(email.lowercased(), forKey: "lastIdentifier")
            Haptics.success()
        } catch { self.error = (error as? LocalizedError)?.errorDescription; Haptics.error() }
    }
}

// MARK: - Activate with invite
struct ActivateView: View {
    @State private var code = Session.shared.pendingInvite ?? ""
    @State private var password = ""
    @State private var email = ""
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.l) {
                StepHeader(step: nil, total: 0, title: L("تفعيل حساب بدعوة"), subtitle: L("أدخل كود الدعوة الذي أعطاك إياه المشرف أو رئيسة التمريض، ثم اختر كلمة مرور."))
                VStack(spacing: DS.m) {
                    DSField(icon: "ticket", placeholder: L("كود الدعوة (6 أحرف)"), text: $code, ltr: true, uppercase: true, id: "activate.code")
                    DSSecureField(placeholder: L("كلمة مرور جديدة (8 أحرف على الأقل)"), text: $password)
                    DSField(icon: "envelope", placeholder: L("البريد الإلكتروني (اختياري)"), text: $email, ltr: true, keyboard: .emailAddress, id: "activate.email")
                }
                if let error { Label(error, systemImage: "exclamationmark.circle.fill").font(.subheadline).foregroundStyle(.red) }
                Button { Task { await submit() } } label: { HStack { if busy { ProgressView().tint(Theme.onPrimary) }; Text(L("تفعيل والدخول")) } }
                    .buttonStyle(PrimaryButtonStyle()).disabled(busy || code.count < 4 || password.count < 8)
                Text(L("بعد التفعيل تدخل لاحقًا برقمك الوظيفي ورمز المستشفى وكلمة المرور.")).font(.footnote).foregroundStyle(.secondary)
            }
            .padding(DS.l).frame(maxWidth: 520).frame(maxWidth: .infinity)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(L("تفعيل الحساب")).navigationBarTitleDisplayMode(.inline)
        .keyboardDone()
    }
    private func submit() async {
        KeyboardHelper.dismiss(); busy = true; error = nil
        defer { busy = false }
        do {
            try await Session.shared.join(code: code.trimmingCharacters(in: .whitespaces).uppercased(), email: email.trimmingCharacters(in: .whitespaces).lowercased(), password: password)
            Session.shared.pendingInvite = nil
            if let n = Session.shared.me?.employee_number, !n.isEmpty { UserDefaults.standard.set(n, forKey: "lastIdentifier") }
            Haptics.success()
        } catch { self.error = (error as? LocalizedError)?.errorDescription; Haptics.error() }
    }
}

// MARK: - Server settings
struct ServerSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var url = UserDefaults.standard.string(forKey: "serverURL") ?? ""
    @State private var status: String?
    @State private var ok = false
    @State private var checking = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://munawib.hospital.local", text: $url)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .environment(\.layoutDirection, .leftToRight)
                } header: { Text(L("خادم المستشفى")) } footer: {
                    Text(L("اتركه فارغًا لاستخدام الخادم السحابي الافتراضي. للخادم الداخلي أدخل الرابط الذي زوّدك به قسم تقنية المعلومات، أو افتح رابط إعداد المستشفى (munawib://server?url=…)."))
                }
                Section {
                    Button { Task { await check() } } label: { HStack { if checking { ProgressView() }; Text(L("اختبار الاتصال")) } }
                    if let status { Label(status, systemImage: ok ? "checkmark.circle.fill" : "xmark.octagon.fill").foregroundStyle(ok ? .green : .red) }
                }
            }
            .navigationTitle(L("إعدادات الخادم")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("إلغاء")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(L("حفظ")) { Task { await save() } }.disabled(checking) }
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.direction)
    }
    private func check() async -> Bool {
        checking = true; defer { checking = false }
        let target = url.isEmpty ? APIClient.defaultServer : url
        switch await APIClient.check(target) {
        case .success(let rt): ok = true; status = rt == "cloudflare" ? L("متصل بالخادم السحابي") : L("متصل بخادم المستشفى الداخلي"); return true
        case .failure: ok = false; status = L("تعذّر الوصول إلى خادم مِناوب على هذا الرابط"); return false
        }
    }
    private func save() async {
        if url.trimmingCharacters(in: .whitespaces).isEmpty { ServerConfig.set(nil); dismiss(); return }
        if await check() { ServerConfig.set(APIClient.normalize(url)); Haptics.success(); dismiss() } else { Haptics.error() }
    }
}

enum ServerConfig {
    static func set(_ url: String?) {
        let old = UserDefaults.standard.string(forKey: "serverURL")
        if let url { UserDefaults.standard.set(url, forKey: "serverURL") } else { UserDefaults.standard.removeObject(forKey: "serverURL") }
        if old != url { Session.shared.logout() }
    }
}

// MARK: - Hospital login details card (success screen + Settings)
struct HospitalInfoCard: View {
    private var session: Session { Session.shared }
    @State private var copied: String?
    var body: some View {
        VStack(alignment: .leading, spacing: DS.m) {
            Label(L("بيانات المستشفى"), systemImage: "building.2").font(.title3.bold())
            if let h = session.remote?.hospital { row(L("المستشفى"), h.name, copy: false) }
            if let c = session.remote?.hospital?.code ?? (session.savedHospitalCode.isEmpty ? nil : session.savedHospitalCode) { row(L("رمز المستشفى"), c) }
            if let me = session.me {
                if let n = me.employee_number, !n.isEmpty { row(L("رقمك الوظيفي"), n) }
                if let e = me.email { row(L("بريدك"), e) }
            }
            ForEach((session.remote?.users ?? []).filter { $0.role == "head_nurse" && $0.id != session.me?.id }) { u in
                Divider()
                Text(L("رئيسة التمريض: %@", "\(u.name)")).font(.subheadline.bold())
                if let n = u.employee_number, !n.isEmpty { row(L("الرقم الوظيفي"), n) }
                if let c = u.invite_code { row(L("كود التفعيل"), c) } else { Label(L("الحساب مفعّل"), systemImage: "checkmark.seal.fill").font(.caption).foregroundStyle(.green) }
            }
            ShareLink(item: session.loginDetailsText) { Label(L("مشاركة الكل"), systemImage: "square.and.arrow.up") }
                .buttonStyle(PrimaryButtonStyle())
            Text(L("لا تتضمن المشاركة أي كلمة مرور.")).font(.caption2).foregroundStyle(.secondary)
        }
        .card()
        .overlay(alignment: .top) {
            if let copied {
                Label(L("تم النسخ: %@", "\(copied)"), systemImage: "checkmark.circle.fill").font(.footnote.bold()).foregroundStyle(Theme.ink)
                    .padding(.horizontal, 14).padding(.vertical, 8).background(Theme.surfaceRaised, in: Capsule()).overlay(Capsule().stroke(Theme.borderStrong, lineWidth: 1))
                    .transition(.move(edge: .top).combined(with: .opacity)).offset(y: -12)
            }
        }
    }
    private func row(_ title: String, _ value: String, copy: Bool = true) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(copy ? .body.monospaced().weight(.semibold) : .body.weight(.semibold)).textSelection(.enabled)
            if copy {
                Button {
                    UIPasteboard.general.string = value; Haptics.success()
                    withAnimation(Motion.entry) { copied = title }
                    Task { try? await Task.sleep(for: .seconds(1.6)); withAnimation { if copied == title { copied = nil } } }
                } label: { Image(systemName: "doc.on.doc").frame(width: 44, height: 44) }
                .accessibilityLabel(L("نسخ %@", "\(title)"))
            }
        }
        .font(.subheadline)
    }
}

struct HospitalCreatedSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.l) {
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 56)).foregroundStyle(Theme.primary).symbolEffect(.bounce, value: true)
                    Text(L("تم إنشاء المستشفى")).font(.title.bold())
                    Text(L("احتفظ بهذه البيانات وشاركها مع رئيسة التمريض. يمكنك الرجوع إليها لاحقًا من الإعدادات ← بيانات المستشفى.")).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    HospitalInfoCard()
                }.padding(DS.l)
            }
            .background(Theme.background.ignoresSafeArea())
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("ابدأ")) { dismiss() } } }
        }
        .environment(\.layoutDirection, LanguageManager.shared.direction)
    }
}
