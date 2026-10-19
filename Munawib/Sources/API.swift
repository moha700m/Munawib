import Foundation
import Security

enum Keychain {
    static func set(_ value: String?, for key: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key, kSecAttrService as String: "munawib"]
        SecItemDelete(q as CFDictionary)
        guard let value, let d = value.data(using: .utf8) else { return }
        var add = q; add[kSecValueData as String] = d; add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }
    static func get(_ key: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key, kSecAttrService as String: "munawib",
                                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
}

struct APIError: LocalizedError {
    let status: Int; let message: String
    var errorDescription: String? {
        switch message {
        case "invalid credentials", "wrong password": return "كلمة المرور غير صحيحة"
        case "account not found": return "لا يوجد حساب بهذا البريد أو الرقم الوظيفي"
        case "hospital not found": return "رمز المستشفى غير صحيح"
        case "account not activated": return "الحساب غير مفعّل، استخدم كود الدعوة من رئيسة التمريض أو المدير"
        case "offline": return "لا يوجد اتصال بالإنترنت"
        case "unreachable": return "تعذّر الوصول إلى خادم المستشفى، تحقّق من إعدادات الخادم"
        case "missing fields": return "أكمل الحقول المطلوبة"
        case "duplicate employee number": return "رقمك الوظيفي يجب أن يختلف عن رقم رئيسة التمريض"
        case "email exists": return "البريد مسجّل مسبقًا"
        case "invalid invite": return "رمز الدعوة غير صحيح أو مستخدم"
        case "password too short": return "كلمة المرور يجب أن تكون 8 أحرف على الأقل"
        case "forbidden": return "ليست لديك صلاحية"
        case "employee number exists": return "الرقم الوظيفي مستخدم مسبقًا"
        case "colleague must be in your department": return "الزميل يجب أن يكون في قسمك"
        case "unauthorized": return "انتهت الجلسة، سجّل الدخول مجددًا"
        default: return message.isEmpty ? "تعذّر الاتصال بالخادم" : message
        }
    }
}

// MARK: DTOs
struct RUser: Codable, Identifiable, Hashable {
    var id: String; var hospital_id: String; var department_id: String?; var email: String?; var name: String
    var title: String?; var employee_number: String?; var role: String; var phone: String?; var photo: String?
    var reminder_minutes: Int?; var invite_code: String?; var joined: Bool?
    var roleTitle: String { role == "admin" ? "مدير" : role == "head_nurse" ? "رئيسة تمريض" : role == "supervisor" ? "مشرف" : "موظف" }
    var isManager: Bool { role == "admin" || role == "head_nurse" || role == "supervisor" }
    var isHead: Bool { role == "admin" || role == "head_nurse" }
}
struct RHospital: Codable { var id: String; var name: String; var code: String? }
struct RDepartment: Codable, Identifiable, Hashable { var id: String; var name: String; var min_day: Int?; var min_night: Int? }
struct RAudit: Codable, Identifiable, Hashable { var id: String; var user_name: String?; var action: String; var detail: String?; var created_at: Double }
struct RRoster: Codable { var id: String; var department_id: String; var year: Int; var month: Int; var status: String; var grid: [String: [String: String]]; var day_start: Int?; var night_start: Int? }
struct RAttendance: Codable { var id: String; var user_id: String; var date: String; var kind: String; var hours: Double; var note: String? }
struct REvent: Codable { var id: String; var title: String; var date: String; var location: String?; var audience: String? }
struct RLeave: Codable, Identifiable, Hashable { var id: String; var user_id: String; var start_date: String; var end_date: String; var reason: String?; var status: String; var created_at: Double? }
struct RSwap: Codable, Identifiable, Hashable { var id: String; var from_user: String; var to_user: String; var date: String; var note: String?; var status: String; var created_at: Double? }
struct RAnnouncement: Codable, Identifiable, Hashable { var id: String; var department_id: String?; var author: String?; var title: String; var body: String?; var created_at: Double }
struct RNotification: Codable, Identifiable, Hashable { var id: String; var title: String; var body: String?; var result: String?; var created_at: Double }
struct Bootstrap: Codable {
    var me: RUser; var hospital: RHospital?; var departments: [RDepartment]; var users: [RUser]; var rosters: [RRoster]
    var attendance: [RAttendance]; var events: [REvent]; var leaves: [RLeave]; var swaps: [RSwap]
    var announcements: [RAnnouncement]; var notifications: [RNotification]
    var audit_log: [RAudit]?
}
struct AuthResponse: Codable { var token: String; var user: RUser; var hospital_code: String?; var head_nurse_invite: String?; var hospital_name: String? }
struct NewEmployeeResponse: Codable { var user: RUser; var invite_code: String; var invite_link: String }
struct PushResult: Codable { var status: Int; var reason: String?; var host: String? }
struct PushTestResponse: Codable { var sent: Int; var devices: Int; var results: [PushResult] }
struct IDResponse: Codable { var id: String }

final class APIClient {
    static let shared = APIClient()
    static let defaultServer = "https://munawib-api.saad-cloud-2026.workers.dev"
    static var baseURL: URL { URL(string: UserDefaults.standard.string(forKey: "serverURL") ?? defaultServer) ?? URL(string: defaultServer)! }
    static func normalize(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty && !t.contains("://") { t = "https://" + t }
        while t.hasSuffix("/") { t.removeLast() }
        return t
    }
    /// Validates a server by calling /health; returns runtime name on success.
    static func check(_ server: String) async -> Result<String, Error> {
        guard let u = URL(string: normalize(server) + "/health") else { return .failure(APIError(status: 0, message: "bad url")) }
        do {
            var r = URLRequest(url: u); r.timeoutInterval = 10
            let (d, resp) = try await URLSession.shared.data(for: r)
            guard (resp as? HTTPURLResponse)?.statusCode == 200, let j = try JSONSerialization.jsonObject(with: d) as? [String: Any], j["service"] as? String == "munawib-api" else { return .failure(APIError(status: 0, message: "not munawib")) }
            return .success(j["runtime"] as? String ?? "cloudflare")
        } catch { return .failure(error) }
    }
    var token: String? { didSet { Keychain.set(token, for: "token") } }
    private init() { token = Keychain.get("token") }

    private let decoder = JSONDecoder()

    func send<T: Decodable>(_ method: String, _ path: String, _ body: [String: Any]? = nil, as: T.Type = T.self) async throws -> T {
        var req = URLRequest(url: Self.baseURL.appendingPathComponent(path))
        req.httpMethod = method
        req.timeoutInterval = 25
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let data: Data, resp: URLResponse
        do { (data, resp) = try await URLSession.shared.data(for: req) }
        catch let e as URLError {
            throw APIError(status: -1, message: [.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed].contains(e.code) ? "offline" : "unreachable")
        }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String ?? ""
            throw APIError(status: code, message: msg)
        }
        return try decoder.decode(T.self, from: data)
    }

    struct OK: Decodable {}
    func call(_ method: String, _ path: String, _ body: [String: Any]? = nil) async throws {
        _ = try await send(method, path, body, as: OK.self)
    }
}
