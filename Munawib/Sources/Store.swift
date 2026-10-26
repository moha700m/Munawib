import Foundation
import Observation

@Observable
final class AppStore {
    var data: AppData { didSet { save() } }
    var currentMonth: Date = Date() { didSet { _ = rosterIndex } }

    private static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("munawib.json")
    }

    init() {
        if let d = try? Data(contentsOf: Self.fileURL),
           let decoded = try? JSONDecoder().decode(AppData.self, from: d) {
            data = decoded
        } else {
            data = Self.seed()
        }
        _ = rosterIndex
    }

    func save() {
        if let d = try? JSONEncoder().encode(data) { try? d.write(to: Self.fileURL, options: .atomic) }
    }

    var year: Int { Calendar.current.component(.year, from: currentMonth) }
    var month: Int { Calendar.current.component(.month, from: currentMonth) }
    var daysInMonth: Int { Calendar.current.range(of: .day, in: .month, for: currentMonth)?.count ?? 30 }

    var departmentEmployees: [Employee] {
        data.employees.filter { $0.department == data.selectedDepartment }
    }

    var monthTitle: String {
        let f = DateFormatter(); f.locale = LanguageManager.current.locale; f.dateFormat = "MMMM yyyy"
        return f.string(from: currentMonth)
    }

    func shiftMonth(_ delta: Int) {
        if let d = Calendar.current.date(byAdding: .month, value: delta, to: currentMonth) { currentMonth = d }
    }

    func selectDepartment(_ d: String) { data.selectedDepartment = d; _ = rosterIndex }

    // MARK: Roster
    var rosterIndex: Int { rosterIndex(year: year, month: month) }

    /// Index of the selected department's roster for any month, creating an empty one when missing.
    func rosterIndex(year y: Int, month m: Int) -> Int {
        if let i = data.rosters.firstIndex(where: { $0.year == y && $0.month == m && $0.department == data.selectedDepartment }) {
            return i
        }
        var r = Roster(year: y, month: m, department: data.selectedDepartment)
        r.entries = departmentEmployees.map { RosterEntry(employeeID: $0.id, codes: [:]) }
        data.rosters.append(r)
        return data.rosters.count - 1
    }

    var roster: Roster { data.rosters[rosterIndex] }

    func code(for emp: UUID, day: Int) -> ShiftCode {
        roster.entries.first(where: { $0.employeeID == emp })?.codes["\(day)"] ?? .empty
    }

    func setCode(_ c: ShiftCode, emp: UUID, day: Int) {
        let i = rosterIndex
        if let e = data.rosters[i].entries.firstIndex(where: { $0.employeeID == emp }) {
            data.rosters[i].entries[e].codes["\(day)"] = c
        } else {
            data.rosters[i].entries.append(RosterEntry(employeeID: emp, codes: ["\(day)": c]))
        }
        if data.rosters[i].status == .approved { data.rosters[i].status = .draft }
    }

    func cycle(emp: UUID, day: Int) {
        let order: [ShiftCode] = [.day, .evening, .night, .rest, .leave, .course, .empty]
        let cur = code(for: emp, day: day)
        let next = order[((order.firstIndex(of: cur) ?? (order.count - 1)) + 1) % order.count]
        setCode(next, emp: emp, day: day)
    }

    func markReviewed() { data.rosters[rosterIndex].status = .reviewed; log(L("حفظ المراجعة"), L("جدول %@", "\(monthTitle)")) }

    func approve() async {
        let i = rosterIndex
        data.rosters[i].status = .approved
        log(L("اعتماد وإرسال للفريق"), L("جدول %1$@ — %2$@", "\(monthTitle)", "\(data.selectedDepartment)"))
        await NotificationManager.shared.notifyNow(title: L("تم اعتماد الجدول"), body: L("جدول %1$@ لقسم %2$@ أصبح معتمدًا.", "\(monthTitle)", "\(data.selectedDepartment)"))
        await rescheduleNotifications()
    }

    func applyImported(_ grid: [String: [Int: ShiftCode]], source: String) {
        let i = rosterIndex
        for emp in departmentEmployees {
            let row = grid[emp.employeeNumber] ?? grid[emp.name.uppercased()]
            guard let row else { continue }
            for (day, c) in row where day >= 1 && day <= daysInMonth { setCode(c, emp: emp.id, day: day) }
        }
        data.rosters[i].status = .draft
        data.rosters[i].source = source
        log(L("رفع جدول"), source)
    }

    /// Writes dated shifts (from the photo import review) into one employee's rows, across whichever months they fall in.
    /// Returns the number of cells written.
    @discardableResult
    func applyShifts(_ shifts: [ParsedShift], for emp: UUID, source: String) -> Int {
        let cal = Calendar.current
        var touched = Set<Int>()
        var n = 0
        for s in shifts {
            let y = cal.component(.year, from: s.date), m = cal.component(.month, from: s.date), d = cal.component(.day, from: s.date)
            let i = rosterIndex(year: y, month: m)
            if let e = data.rosters[i].entries.firstIndex(where: { $0.employeeID == emp }) {
                data.rosters[i].entries[e].codes["\(d)"] = s.code
            } else {
                data.rosters[i].entries.append(RosterEntry(employeeID: emp, codes: ["\(d)": s.code]))
            }
            touched.insert(i); n += 1
        }
        // A month that only exists because of this import is the paper roster itself: mark it approved so
        // reminders (which only consider approved rosters) are scheduled for the imported shifts.
        for i in touched where data.rosters[i].source == nil { data.rosters[i].source = source; data.rosters[i].status = .approved }
        if n > 0 { log(L("قراءة الجدول من صورة"), L("%@ مناوبة", "\(n)")) }
        return n
    }

    // MARK: Notifications
    func rescheduleNotifications() async {
        guard data.settings.notificationsEnabled else { return }
        await NotificationManager.shared.reschedule(store: self)
    }

    func todayCounts() -> (day: Int, night: Int) {
        let cal = Calendar.current
        let d = cal.component(.day, from: Date())
        guard cal.component(.month, from: Date()) == month, cal.component(.year, from: Date()) == year else {
            return (0, 0)
        }
        var dc = 0, nc = 0
        for e in departmentEmployees {
            switch code(for: e.id, day: d) { case .day: dc += 1; case .night: nc += 1; default: break }
        }
        return (dc, nc)
    }

    // MARK: Hours
    func total(_ kind: HourKind) -> Double {
        let cal = Calendar.current
        let ids = Set(departmentEmployees.map(\.id))
        return data.hours.filter {
            $0.kind == kind && ids.contains($0.employeeID) &&
            cal.component(.month, from: $0.date) == month && cal.component(.year, from: $0.date) == year
        }.reduce(0) { $0 + $1.hours }
    }

    func monthHours() -> [HourLog] {
        let cal = Calendar.current
        let ids = Set(departmentEmployees.map(\.id))
        return data.hours.filter {
            ids.contains($0.employeeID) && cal.component(.month, from: $0.date) == month && cal.component(.year, from: $0.date) == year
        }.sorted { $0.date > $1.date }
    }

    func rosterHours(for emp: UUID) -> Int {
        var n = 0
        for d in 1...daysInMonth where code(for: emp, day: d).isWorking { n += data.settings.shiftLength }
        return n
    }

    func employee(_ id: UUID) -> Employee? { data.employees.first { $0.id == id } }

    func log(_ title: String, _ detail: String) {
        data.sendLog.insert(SendLog(date: Date(), title: title, detail: detail), at: 0)
    }

    // MARK: Seed
    static func seed() -> AppData {
        var d = AppData()
        let dept = "تمريض الأطفال"
        d.employees = [Employee(name: "نورة القحطاني", title: "رئيسة تمريض", employeeNumber: "9001", department: dept, linked: true)]
        let names = ["سارة العتيبي", "ريم الشهري", "هند الغامدي", "منى الدوسري", "عبير الحربي", "لمى المطيري", "فاطمة الزهراني"]
        for (i, n) in names.enumerated() {
            d.employees.append(Employee(name: n, title: "ممرضة", employeeNumber: "\(9002 + i)", department: dept, linked: i % 3 != 2))
        }
        let cal = Calendar.current
        let now = Date()
        var r = Roster(year: cal.component(.year, from: now), month: cal.component(.month, from: now), department: dept)
        let pattern: [ShiftCode] = [.day, .day, .night, .night, .rest, .rest]
        let days = cal.range(of: .day, in: .month, for: now)?.count ?? 30
        for (idx, e) in d.employees.enumerated() {
            var codes: [String: ShiftCode] = [:]
            for day in 1...days { codes["\(day)"] = idx == 0 ? ((day % 7 == 5 || day % 7 == 6) ? .rest : .day) : pattern[(day + idx) % pattern.count] }
            r.entries.append(RosterEntry(employeeID: e.id, codes: codes))
        }
        r.status = .approved
        r.source = "جدول القسم المعتمد"
        d.rosters = [r]
        d.settings.loggedInEmployeeNumber = "9001"
        for (i, e) in d.employees.enumerated() {
            for back in 1...4 { d.hours.append(HourLog(employeeID: e.id, date: cal.date(byAdding: .day, value: -back, to: now) ?? now, kind: back == 4 && i % 2 == 0 ? .overtime : .actual, hours: 12)) }
        }
        d.sendLog = [SendLog(date: now.addingTimeInterval(-3600), title: "اعتماد وإرسال للفريق", detail: "جدول الشهر — \(dept)"),
                     SendLog(date: now.addingTimeInterval(-7200), title: "إعلان", detail: "اجتماع القسم الأسبوعي")]
        func future(_ days: Int, _ h: Int) -> Date {
            let base = cal.date(byAdding: .day, value: days, to: now) ?? now
            return cal.date(bySettingHour: h, minute: 0, second: 0, of: base) ?? base
        }
        d.events = [
            HospitalEvent(title: "دورة الإنعاش القلبي الرئوي", date: future(7, 10), location: "قاعة التدريب 2", audience: dept),
            HospitalEvent(title: "التعريف بنظام المناوبات", date: future(14, 13), location: "عن بُعد", audience: "كل المستشفى"),
        ]
        return d
    }
}
