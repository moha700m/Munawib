import SwiftUI

struct EmployeeForm: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let employee: Employee?
    @State private var name = ""
    @State private var title = "Nurse"
    @State private var number = ""
    @State private var dept = ""
    @State private var phone = ""
    @State private var role = "employee"
    @State private var originalRole = "employee"
    @State private var resetCode: String?
    @State private var invite: NewEmployeeResponse?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                AppTextField(placeholder: L("الاسم"), text: $name).frame(minHeight: 32)
                AppTextField(placeholder: L("المسمى الوظيفي"), text: $title).frame(minHeight: 32)
                NumericField(placeholder: L("الرقم الوظيفي"), text: $number, identifier: "employee.number")
                AppTextField(placeholder: L("الجوال"), text: $phone, keyboard: .phonePad, ltr: true).frame(minHeight: 32)
                if Session.shared.online && Session.shared.me?.isHead == true {
                    Picker(L("الصلاحية"), selection: $role) {
                        Text(L("موظف")).tag("employee"); Text(L("مشرف")).tag("supervisor")
                        if Session.shared.me?.role == "admin" { Text(L("رئيسة تمريض")).tag("head_nurse"); Text(L("مدير")).tag("admin") }
                    }
                    .onChange(of: role) { _, r in
                        guard let employee, r != originalRole else { return }
                        Task { do { try await Session.shared.setRole(employee.id, role: r); originalRole = r } catch { self.error = (error as? LocalizedError)?.errorDescription } }
                    }
                    if let employee, let u = Session.shared.user(employee.id.uuidString.lowercased()) {
                        if let c = resetCode ?? u.invite_code {
                            Section { InviteCodeRow(code: c, name: u.name, number: u.employee_number) } header: { Text(L("كود التفعيل — الحساب غير مفعّل")) }
                        } else {
                            Section {
                                Button(L("إعادة تعيين كلمة المرور (كود جديد)"), role: .destructive) {
                                    Task { do { resetCode = try await Session.shared.resetInvite(employee.id) } catch { self.error = (error as? LocalizedError)?.errorDescription } }
                                }
                            } footer: { Text(L("يُلغى الدخول الحالي ويظهر كود تفعيل جديد للموظف.")) }
                        }
                    }
                }
                if let invite {
                    Section { InviteCodeRow(code: invite.invite_code, name: invite.user.name, number: invite.user.employee_number) } header: { Text(L("تمت الإضافة — كود التفعيل")) }
                }
                if let error { Text(error).foregroundStyle(.red) }
                Picker(L("القسم"), selection: $dept) {
                    ForEach(store.data.settings.departments, id: \.self) { Text($0).tag($0) }
                }
                if let employee {
                    Section {
                        Button(L("حذف الموظف"), role: .destructive) {
                            store.data.employees.removeAll { $0.id == employee.id }
                            Task { try? await Session.shared.deleteEmployee(employee.id) }
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(employee == nil ? L("إضافة موظف") : L("تعديل موظف"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("إلغاء")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(invite == nil ? L("حفظ") : L("تم")) { save() }.disabled(name.isEmpty || number.isEmpty)
                }
            }
            .onAppear {
                dept = employee?.department ?? store.data.selectedDepartment
                if let e = employee { name = e.name; title = e.title; number = e.employeeNumber; phone = e.phone; let r = Session.shared.user(e.id.uuidString.lowercased())?.role ?? "employee"; role = r; originalRole = r }
            }
        }
        .keyboardDone()
        .environment(\.layoutDirection, LanguageManager.shared.direction)
    }

    private func save() {
        if let employee, let i = store.data.employees.firstIndex(where: { $0.id == employee.id }) {
            store.data.employees[i].name = name; store.data.employees[i].title = title
            store.data.employees[i].employeeNumber = number; store.data.employees[i].department = dept
            store.data.employees[i].phone = phone
            Task { try? await Session.shared.updateEmployee(employee.id, name: name, title: title, number: number, dept: dept, phone: phone) }
            dismiss()
        } else if Session.shared.online {
            if invite != nil { dismiss(); return }
            Task {
                do {
                    invite = try await Session.shared.createEmployee(name: name, title: title, number: number, dept: dept, phone: phone, role: role)
                    store.log(L("دعوة موظف"), L("%1$@ — رمز %2$@", "\(name)", "\(invite?.invite_code ?? "")"))
                } catch { self.error = (error as? LocalizedError)?.errorDescription }
            }
        } else {
            store.data.employees.append(Employee(name: name, title: title, employeeNumber: number, department: dept, phone: phone))
            store.log(L("دعوة موظف"), "\(name) — \(number)")
            dismiss()
        }
    }
}

struct HoursForm: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var empID: UUID?
    @State private var kind: HourKind = .actual
    @State private var date = Date()
    @State private var hours = 12.0
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Picker(L("الموظف"), selection: $empID) {
                    ForEach(store.departmentEmployees) { Text($0.name).tag(Optional($0.id)) }
                }
                Picker(L("النوع"), selection: $kind) {
                    ForEach(HourKind.allCases) { Text("\($0.rawValue) — \($0.title)").tag($0) }
                }
                DatePicker(L("التاريخ"), selection: $date, displayedComponents: .date)
                Stepper(L("الساعات: %@", "\(Fmt.hours(hours))"), value: $hours, in: 0.5...24, step: 0.5)
                AppTextField(placeholder: L("ملاحظة"), text: $note).frame(minHeight: 32)
            }
            .navigationTitle(L("إضافة سجل ساعات"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("إلغاء")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("حفظ")) {
                        if let empID { let h = HourLog(employeeID: empID, date: date, kind: kind, hours: hours, note: note); store.data.hours.append(h); Task { try? await Session.shared.addHours(h) } }
                        dismiss()
                    }.disabled(empID == nil)
                }
            }
            .onAppear {
                if empID == nil { empID = store.departmentEmployees.first?.id }
                date = store.currentMonth
            }
        }
        .keyboardDone()
        .environment(\.layoutDirection, LanguageManager.shared.direction)
    }
}

struct EventForm: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var date = Date().addingTimeInterval(86400)
    @State private var location = ""
    @State private var allHospital = false

    var body: some View {
        NavigationStack {
            Form {
                AppTextField(placeholder: L("العنوان"), text: $title).frame(minHeight: 32)
                DatePicker(L("الموعد"), selection: $date)
                AppTextField(placeholder: L("المكان"), text: $location).frame(minHeight: 32)
                Toggle(L("لكل المستشفى"), isOn: $allHospital)
            }
            .navigationTitle(L("دورة أو فعالية"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("إلغاء")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("حفظ")) {
                        let ev = HospitalEvent(title: title, date: date, location: location, audience: allHospital ? L("كل المستشفى") : store.data.selectedDepartment); store.data.events.append(ev); Task { try? await Session.shared.addEvent(ev) }
                        store.log(L("إضافة فعالية"), title)
                        Task { await store.rescheduleNotifications() }
                        dismiss()
                    }.disabled(title.isEmpty)
                }
            }
        }
        .keyboardDone()
        .environment(\.layoutDirection, LanguageManager.shared.direction)
    }
}
