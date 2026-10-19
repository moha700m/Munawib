import Foundation
import Observation
import UIKit
import SwiftUI
import UserNotifications

/// Bridges the cloud backend (Cloudflare Worker) and the local AppStore used by the views.
@Observable
final class Session {
    static let shared = Session()
    var store: AppStore?
    var me: RUser?
    var remote: Bootstrap?
    var offlineMode = UserDefaults.standard.bool(forKey: "offlineMode")
    var syncing = false
    var lastError: String?
    var lastSync: Date?
    var deviceToken: String? = UserDefaults.standard.string(forKey: "deviceToken")
    var tokenRegistered = UserDefaults.standard.bool(forKey: "tokenRegistered")
    var lastPushResult: String?
    var pendingInvite: String?

    /// Observed mirror of the Keychain token so SwiftUI re-renders immediately on login/logout.
    var authToken: String? = APIClient.shared.token
    var isLoggedIn: Bool { offlineMode || (authToken != nil && me != nil) }
    var isManager: Bool { offlineMode || (me?.isManager ?? false) }
    var isHead: Bool { offlineMode || (me?.isHead ?? false) }
    var roleTitle: String { offlineMode ? "وضع محلي" : (me?.roleTitle ?? "") }
    var savedHospitalCode: String { get { UserDefaults.standard.string(forKey: "hospitalCode") ?? "" } set { UserDefaults.standard.set(newValue, forKey: "hospitalCode") } }
    var signupInfo: String?
    var myDepartment: RDepartment? { remote?.departments.first { $0.id == me?.department_id } }

    private static var cacheURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("remote-cache.json")
    }

    private init() {
        if APIClient.shared.token != nil, let d = try? Data(contentsOf: Self.cacheURL), let b = try? JSONDecoder().decode(Bootstrap.self, from: d) {
            remote = b; me = b.me
        }
    }

    // MARK: Auth
    var showHospitalCreated = false
    func signup(hospital: String, department: String, name: String, email: String, password: String, adminNumber: String = "", headNurseName: String = "", headNurseNumber: String = "") async throws {
        var b: [String: Any] = ["hospital": hospital, "department": department, "name": name, "email": email, "password": password]
        if !adminNumber.isEmpty { b["employee_number"] = adminNumber }
        if !headNurseName.isEmpty { b["head_nurse"] = ["name": headNurseName, "employee_number": headNurseNumber] }
        let r: AuthResponse = try await APIClient.shared.send("POST", "auth/signup", b)
        if r.hospital_code != nil { showHospitalCreated = true }
        if let c = r.hospital_code { savedHospitalCode = c; signupInfo = "رمز المستشفى: \(c)" + (r.head_nurse_invite.map { "\nدعوة رئيسة التمريض: \($0)" } ?? "") }
        try await finishAuth(r)
    }
    func login(identifier: String, hospitalCode: String, password: String) async throws {
        let id = identifier.trimmingCharacters(in: .whitespaces)
        if id.contains("@") { try await login(email: id.lowercased(), password: password) }
        else { try await loginEmployee(hospitalCode: hospitalCode.trimmingCharacters(in: .whitespaces).uppercased(), number: id.asciiDigits, password: password) }
    }
    func resetInvite(_ id: UUID) async throws -> String {
        struct R: Decodable { var invite_code: String }
        let r: R = try await APIClient.shared.send("POST", "employees/\(id.uuidString.lowercased())/reset")
        try? await refresh(); return r.invite_code
    }
    /// Formatted Arabic login details (never includes passwords).
    var loginDetailsText: String {
        var lines = ["بيانات الدخول إلى مِناوب"]
        if let h = remote?.hospital { lines.append("المستشفى: \(h.name)") }
        if let c = remote?.hospital?.code ?? (savedHospitalCode.isEmpty ? nil : savedHospitalCode) { lines.append("رمز المستشفى: \(c)") }
        if let me { lines.append("\(me.roleTitle): \(me.name)" + (me.employee_number.map { $0.isEmpty ? "" : " — الرقم الوظيفي \($0)" } ?? "") + (me.email.map { " — \($0)" } ?? "")) }
        for u in (remote?.users ?? []) where u.role == "head_nurse" && u.id != me?.id {
            lines.append("رئيسة التمريض: \(u.name)" + (u.employee_number.map { " — الرقم الوظيفي \($0)" } ?? "") + (u.invite_code.map { " — كود التفعيل \($0)" } ?? " — مفعّل"))
        }
        lines.append("طريقة الدخول: افتح مِناوب ← أدخل الرقم الوظيفي ورمز المستشفى وكلمة المرور. أول مرة: «تفعيل حساب بدعوة».")
        return lines.joined(separator: "\n")
    }
    func loginEmployee(hospitalCode: String, number: String, password: String) async throws {
        let r: AuthResponse = try await APIClient.shared.send("POST", "auth/login", ["hospital_code": hospitalCode, "employee_number": number, "password": password])
        savedHospitalCode = hospitalCode
        try await finishAuth(r)
    }
    func customPush(title: String, body: String, userIDs: [String]) async throws -> String {
        struct R: Decodable { var recipients: Int; var sent: Int; var devices: Int }
        let r: R = try await APIClient.shared.send("POST", "push/custom", ["title": title, "body": body, "user_ids": userIDs])
        try? await refresh()
        return "أُرسل إلى \(r.recipients) موظف (\(r.sent) من \(r.devices) جهاز)"
    }
    func setRole(_ id: UUID, role: String) async throws { try await APIClient.shared.call("POST", "employees/\(id.uuidString.lowercased())/role", ["role": role]); try? await refresh() }
    func setCoverage(minDay: Int, minNight: Int) async throws {
        guard online, let d = deptID(store?.data.selectedDepartment ?? "") else { return }
        try await APIClient.shared.call("PATCH", "departments/\(d)", ["min_day": minDay, "min_night": minNight]); try? await refresh()
    }
    func login(email: String, password: String) async throws {
        let r: AuthResponse = try await APIClient.shared.send("POST", "auth/login", ["email": email, "password": password])
        try await finishAuth(r)
    }
    func join(code: String, email: String, password: String) async throws {
        var b: [String: Any] = ["code": code, "password": password]
        if !email.isEmpty { b["email"] = email }
        let r: AuthResponse = try await APIClient.shared.send("POST", "auth/join", b)
        try await finishAuth(r)
    }
    private func finishAuth(_ r: AuthResponse) async throws {
        APIClient.shared.token = r.token
        UserDefaults.standard.set(false, forKey: "offlineMode")
        await MainActor.run {
            withAnimation(.easeInOut(duration: 0.35)) {
                self.authToken = r.token
                self.me = r.user
                self.offlineMode = false
            }
        }
        try? await refresh()
        Task { await registerForPush() }
    }
    func useOffline() { UserDefaults.standard.set(true, forKey: "offlineMode"); withAnimation(.easeInOut(duration: 0.35)) { offlineMode = true } }
    func logout() {
        if let t = deviceToken, APIClient.shared.token != nil {
            Task { try? await APIClient.shared.call("DELETE", "devices", ["token": t]) }
        }
        APIClient.shared.token = nil
        withAnimation(.easeInOut(duration: 0.35)) { authToken = nil; me = nil; offlineMode = false }
        remote = nil; tokenRegistered = false
        UserDefaults.standard.set(false, forKey: "tokenRegistered")
        offlineMode = false; UserDefaults.standard.set(false, forKey: "offlineMode")
        try? FileManager.default.removeItem(at: Self.cacheURL)
    }

    func deleteAccount(password: String) async throws {
        try await APIClient.shared.call("DELETE", "me", ["password": password])
        logout()
    }

    // MARK: Sync
    @MainActor
    func refresh() async throws {
        guard !offlineMode, authToken != nil else { return }
        syncing = true; defer { syncing = false }
        do {
            let b: Bootstrap = try await APIClient.shared.send("GET", "bootstrap")
            remote = b; me = b.me; lastSync = Date(); lastError = nil
            if let d = try? JSONEncoder().encode(b) { try? d.write(to: Self.cacheURL, options: .atomic) }
            apply(b)
        } catch let e as APIError where e.status == 401 {
            logout(); throw e
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? "تعذّر المزامنة — يتم عرض آخر بيانات محفوظة"
            throw error
        }
    }

    func deptName(_ id: String?) -> String { remote?.departments.first { $0.id == id }?.name ?? "" }
    func deptID(_ name: String) -> String? { remote?.departments.first { $0.name == name }?.id }
    func user(_ id: String) -> RUser? { remote?.users.first { $0.id == id } }

    private static let dayFmt: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f }()
    static func day(_ d: Date) -> String { dayFmt.string(from: d) }
    static func parseDay(_ s: String) -> Date? { dayFmt.date(from: String(s.prefix(10))) ?? ISO8601DateFormatter().date(from: s) }

    @MainActor
    private func apply(_ b: Bootstrap) {
        guard let store else { return }
        var d = store.data
        if let h = b.hospital { d.settings.hospital = h.name }
        d.settings.departments = b.departments.map(\.name)
        if !d.settings.departments.contains(d.selectedDepartment) { d.selectedDepartment = deptName(b.me.department_id).isEmpty ? (d.settings.departments.first ?? "") : deptName(b.me.department_id) }
        d.employees = b.users.compactMap { u in
            guard let id = UUID(uuidString: u.id) else { return nil }
            return Employee(id: id, name: u.name, title: u.title ?? "", employeeNumber: u.employee_number ?? "", department: deptName(u.department_id), phone: u.phone ?? "", linked: u.joined ?? false)
        }
        d.rosters = b.rosters.compactMap { r in
            var ro = Roster(id: UUID(uuidString: r.id) ?? UUID(), year: r.year, month: r.month, department: deptName(r.department_id))
            ro.status = r.status == "approved" ? .approved : r.status == "review" ? .reviewed : .draft
            ro.source = "الخادم"
            ro.entries = r.grid.compactMap { k, v in
                guard let id = UUID(uuidString: k) else { return nil }
                return RosterEntry(employeeID: id, codes: v.compactMapValues { ShiftCode(rawValue: $0) })
            }
            return ro
        }
        d.hours = b.attendance.compactMap { a in
            guard let uid = UUID(uuidString: a.user_id), let date = Self.parseDay(a.date) else { return nil }
            return HourLog(id: UUID(uuidString: a.id) ?? UUID(), employeeID: uid, date: date, kind: HourKind(rawValue: a.kind) ?? .actual, hours: a.hours, note: a.note ?? "")
        }
        d.events = b.events.compactMap { e in
            guard let date = ISO8601DateFormatter().date(from: e.date) ?? Self.parseDay(e.date) else { return nil }
            return HospitalEvent(id: UUID(uuidString: e.id) ?? UUID(), title: e.title, date: date, location: e.location ?? "", audience: e.audience ?? "")
        }
        if let n = b.me.employee_number, !n.isEmpty { d.settings.loggedInEmployeeNumber = n }
        if b.me.role != "admin", !deptName(b.me.department_id).isEmpty { d.selectedDepartment = deptName(b.me.department_id) }
        if let c = b.hospital?.code { savedHospitalCode = c }
        if let m = b.me.reminder_minutes { d.settings.reminderMinutesBefore = m }
        store.data = d
    }

    // MARK: Writes (silently no-op in offline mode)
    var online: Bool { !offlineMode && authToken != nil }

    func pushRoster(_ r: Roster, status: String?) async throws -> Int {
        guard online, let dep = deptID(r.department) else { return 0 }
        var grid: [String: [String: String]] = [:]
        for e in r.entries { grid[e.employeeID.uuidString.lowercased()] = e.codes.filter { $0.value != .empty }.mapValues(\.rawValue) }
        let s = store?.data.settings
        let res: IDResponse = try await APIClient.shared.send("PUT", "rosters", ["department_id": dep, "year": r.year, "month": r.month, "grid": grid, "day_start": s?.dayStartHour ?? 5, "night_start": s?.nightStartHour ?? 17])
        var pushed = 0
        if let status {
            struct S: Decodable { var push: [PushResult]? }
            let x: S = try await APIClient.shared.send("POST", "rosters/\(res.id)/status", ["status": status])
            pushed = x.push?.filter { $0.status == 200 }.count ?? 0
        }
        try? await refresh()
        return pushed
    }

    func createEmployee(name: String, title: String, number: String, dept: String, phone: String, role: String) async throws -> NewEmployeeResponse? {
        guard online else { return nil }
        let r: NewEmployeeResponse = try await APIClient.shared.send("POST", "employees", ["name": name, "title": title, "employee_number": number, "department_id": deptID(dept) ?? "", "phone": phone, "role": role])
        try? await refresh(); return r
    }
    func updateEmployee(_ id: UUID, name: String, title: String, number: String, dept: String, phone: String) async throws {
        guard online else { return }
        try await APIClient.shared.call("PATCH", "employees/\(id.uuidString.lowercased())", ["name": name, "title": title, "employee_number": number, "department_id": deptID(dept) ?? "", "phone": phone])
        try? await refresh()
    }
    func deleteEmployee(_ id: UUID) async throws {
        guard online else { return }
        try await APIClient.shared.call("DELETE", "employees/\(id.uuidString.lowercased())")
        try? await refresh()
    }
    func addDepartment(_ name: String) async throws { guard online else { return }; try await APIClient.shared.call("POST", "departments", ["name": name]); try? await refresh() }
    func addHours(_ h: HourLog) async throws {
        guard online else { return }
        try await APIClient.shared.call("POST", "attendance", ["user_id": h.employeeID.uuidString.lowercased(), "date": Self.day(h.date), "kind": h.kind.rawValue, "hours": h.hours, "note": h.note])
        try? await refresh()
    }
    func addEvent(_ e: HospitalEvent) async throws {
        guard online else { return }
        try await APIClient.shared.call("POST", "events", ["title": e.title, "date": ISO8601DateFormatter().string(from: e.date), "location": e.location, "audience": e.audience])
        try? await refresh()
    }
    func requestLeave(from: Date, to: Date, reason: String) async throws {
        try await APIClient.shared.call("POST", "leaves", ["start_date": Self.day(from), "end_date": Self.day(to), "reason": reason]); try? await refresh()
    }
    func decideLeave(_ id: String, approve: Bool) async throws { try await APIClient.shared.call("POST", "leaves/\(id)/decision", ["approve": approve]); try? await refresh() }
    func requestSwap(with userID: String, date: Date, note: String) async throws {
        try await APIClient.shared.call("POST", "swaps", ["to_user": userID, "date": Self.day(date), "note": note]); try? await refresh()
    }
    func decideSwap(_ id: String, approve: Bool) async throws { try await APIClient.shared.call("POST", "swaps/\(id)/decision", ["approve": approve]); try? await refresh() }
    func announce(title: String, body: String, dept: String?) async throws {
        try await APIClient.shared.call("POST", "announcements", ["title": title, "body": body, "department_id": dept.flatMap { deptID($0) }.map { $0 as Any } ?? NSNull()]); try? await refresh()
    }
    func updateProfile(name: String?, phone: String?, photo: String?, reminder: Int?) async throws {
        guard online else { return }
        var b: [String: Any] = [:]
        if let name { b["name"] = name }; if let phone { b["phone"] = phone }; if let photo { b["photo"] = photo }; if let reminder { b["reminder_minutes"] = reminder }
        try await APIClient.shared.call("PATCH", "me", b); try? await refresh()
    }

    // MARK: Push
    @MainActor
    func registerForPush() async {
        let ok = await NotificationManager.shared.requestPermission()
        store?.data.settings.notificationsEnabled = ok
        if ok { UIApplication.shared.registerForRemoteNotifications() }
    }

    func didRegister(token: Data) {
        let hex = token.map { String(format: "%02x", $0) }.joined()
        deviceToken = hex
        UserDefaults.standard.set(hex, forKey: "deviceToken")
        Task { await uploadToken() }
    }

    func uploadToken() async {
        guard online, let deviceToken else { return }
        do {
            try await APIClient.shared.call("POST", "devices", ["token": deviceToken, "env": "production"])
            tokenRegistered = true
        } catch { tokenRegistered = false; lastError = (error as? LocalizedError)?.errorDescription }
        UserDefaults.standard.set(tokenRegistered, forKey: "tokenRegistered")
    }

    func sendServerTestPush() async {
        guard online else { lastPushResult = "سجّل الدخول بحساب سحابي أولاً"; return }
        if deviceToken != nil && !tokenRegistered { await uploadToken() }
        do {
            let r: PushTestResponse = try await APIClient.shared.send("POST", "push/test")
            if r.devices == 0 { lastPushResult = "لا يوجد جهاز مسجّل على الخادم" }
            else if r.sent > 0 { lastPushResult = "✅ أُرسل إلى \(r.sent) من \(r.devices) جهاز" }
            else { lastPushResult = "❌ رفضت Apple: " + r.results.map { "\($0.status) \($0.reason ?? "")" }.joined(separator: "، ") }
        } catch { lastPushResult = "❌ " + ((error as? LocalizedError)?.errorDescription ?? "خطأ") }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Task { @MainActor in
            if await NotificationManager.shared.status() == .authorized { application.registerForRemoteNotifications() }
        }
        return true
    }
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Session.shared.didRegister(token: deviceToken)
    }
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Session.shared.lastPushResult = "فشل التسجيل في APNs: \(error.localizedDescription)"
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        Task { try? await Session.shared.refresh() }
        return [.banner, .sound, .list, .badge]
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        try? await Session.shared.refresh()
    }
}
