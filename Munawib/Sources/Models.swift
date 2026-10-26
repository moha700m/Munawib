import Foundation

enum ShiftCode: String, Codable, CaseIterable, Identifiable {
    case day = "D", evening = "E", night = "N", rest = "R", leave = "L", course = "C", empty = ""
    var id: String { rawValue }
    var title: String {
        switch self {
        case .day: return L("نهاري")
        case .evening: return L("مسائي")
        case .night: return L("ليلي")
        case .rest: return L("راحة")
        case .leave: return L("إجازة")
        case .course: return L("دورة")
        case .empty: return L("فارغ")
        }
    }
    var label: String { self == .empty ? "—" : rawValue }
    /// Day, evening and night are the codes that put someone on duty (hours, reminders, countdown).
    var isWorking: Bool { self == .day || self == .evening || self == .night }
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
        switch self { case .draft: return L("مسودة"); case .reviewed: return L("تمت المراجعة"); case .approved: return L("معتمد") }
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
        case .actual: return L("الحضور الفعلي")
        case .overtime: return L("الإضافي")
        case .standby: return L("الاستعداد")
        case .compensatory: return L("الساعات التعويضية")
        case .leave: return L("الإجازات")
        case .course: return L("الدورات")
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
    /// Optional so settings saved by earlier builds still decode; see `eveningStart`.
    var eveningStartHour: Int? = nil

    var eveningStart: Int {
        get { eveningStartHour ?? 13 }
        set { eveningStartHour = newValue }
    }
    /// Start hour of a working code, nil for rest / leave / course / empty.
    func startHour(_ code: ShiftCode) -> Int? {
        switch code {
        case .day: return dayStartHour
        case .evening: return eveningStart
        case .night: return nightStartHour
        default: return nil
        }
    }
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
