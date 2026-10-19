import Foundation

/// Launch-argument hooks used only for CI screenshots.
enum Demo {
    static var auth: String?
    static func installRemote() {
        let json = """
        {"me":{"id":"u1","hospital_id":"h1","department_id":"d1","email":"admin@alnoor.sa","name":"د. سارة القحطاني","employee_number":"5001","role":"admin"},
         "hospital":{"id":"h1","name":"مستشفى النور التخصصي","code":"NR7K2Q"},
         "departments":[{"id":"d1","hospital_id":"h1","name":"الطوارئ"}],
         "users":[{"id":"u1","hospital_id":"h1","department_id":"d1","email":"admin@alnoor.sa","name":"د. سارة القحطاني","employee_number":"5001","role":"admin"},
                  {"id":"u2","hospital_id":"h1","department_id":"d1","name":"نورة العتيبي","employee_number":"5002","role":"head_nurse","invite_code":"Q8M4TZ"}],
         "rosters":[],"attendance":[],"events":[],"leaves":[],"swaps":[],"announcements":[],"notifications":[]}
        """
        Session.shared.remote = try? JSONDecoder().decode(Bootstrap.self, from: Data(json.utf8))
        Session.shared.demoInfo = true
    }
}
