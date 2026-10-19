import Foundation

enum ShiftCode: String, Codable, CaseIterable, Identifiable {
    case day = "D", night = "N", rest = "R", leave = "L", course = "C", empty = ""
    var id: String { rawValue }
    var title: String {
        switch self {
        case .day: return "نهاري"
        case .night: return "ليلي"
        case .rest: return "راحة"
        case .leave: return "إجازة"
        case .course: return "دورة"
        case .empty: return "فارغ"
        }
    }
    var label: String { self == .empty ? "—" : rawValue }
}

struct Employee: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var title: String
    var employeeNumber: String
    var department: String
    var phone: String = ""
    var linked: Bool = false
}

struct RosterEntry: Codable, Hashable {
    var employeeID: UUID
    var codes: [String: ShiftCode] // key = day number as string
}

enum RosterStatus: String, Codable { case draft, reviewed, approved
    var title: String {
        switch self { case .draft: return "مسودة"; case .reviewed: return "تمت المراجعة"; case .approved: return "معتمد" }
    }
}

struct Roster: Codable, Identifiable {
    var id = UUID()
    var year: Int
    var month: Int
    var department: String
    var status: RosterStatus = .draft
    var source: String? = nil
    var entries: [RosterEntry] = []
}

enum HourKind: String, Codable, CaseIterable, Identifiable {
    case actual = "H", overtime = "OT", standby = "SB", compensatory = "CT", leave = "LV", course = "CR"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .actual: return "الحضور الفعلي"
        case .overtime: return "الإضافي"
        case .standby: return "الاستعداد"
        case .compensatory: return "الساعات التعويضية"
        case .leave: return "الإجازات"
        case .course: return "الدورات"
        }
    }
    var symbol: String { "clock" }
}

struct HourLog: Codable, Identifiable {
    var id = UUID()
    var employeeID: UUID
    var date: Date
    var kind: HourKind
    var hours: Double
    var note: String = ""
}

struct HospitalEvent: Codable, Identifiable {
    var id = UUID()
    var title: String
    var date: Date
    var location: String
    var audience: String
}

struct SendLog: Codable, Identifiable {
    var id = UUID()
    var date: Date
    var title: String
    var detail: String
}

struct AppSettings: Codable {
    var hospital: String = "مستشفى مِناوب"
    var departments: [String] = ["تمريض الأطفال", "الطوارئ", "العناية المركزة"]
    var dayStartHour: Int = 5
    var nightStartHour: Int = 17
    var shiftLength: Int = 12
    var reminderMinutesBefore: Int = 60
    var notificationsEnabled: Bool = false
    var loggedInEmployeeNumber: String? = nil
}

struct AppData: Codable {
    var settings = AppSettings()
    var selectedDepartment = "تمريض الأطفال"
    var employees: [Employee] = []
    var rosters: [Roster] = []
    var hours: [HourLog] = []
    var events: [HospitalEvent] = []
    var sendLog: [SendLog] = []
}
