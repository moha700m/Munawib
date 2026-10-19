import SwiftUI
import UserNotifications

struct HoursView: View {
    @Environment(AppStore.self) private var store
    @Binding var sheet: ActiveSheet?
    private let tints: [HourKind: Color] = [.actual: .teal, .overtime: .orange, .standby: .purple, .compensatory: .blue, .leave: .yellow, .course: .pink]

    var body: some View {
        let logs = store.monthHours()
        VStack(spacing: 16) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                ForEach(HourKind.allCases) { k in
                    StatCard(symbol: "clock", tint: tints[k] ?? Theme.primary, caption: k.title, value: "\(Fmt.hours(store.total(k))) ساعة", footnote: "هذا الشهر")
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("\(logs.count) سجل قابل للتدقيق").font(.caption).foregroundStyle(.secondary)
                        Text("تفاصيل \(store.monthTitle)").font(.title2.bold())
                    }
                    Spacer()
                    Button { sheet = .addHours } label: { Label("إضافة سجل", systemImage: "plus") }
                        .buttonStyle(.borderedProminent)
                }
                Text("H حضور فعلي · SB الاستعداد · OT الإضافي · CT تعويضي").font(.caption).foregroundStyle(.secondary)
                if logs.isEmpty {
                    ContentUnavailableView("لم تُسجل ساعات بعد", systemImage: "clock", description: Text("ابدأ بإضافة الحضور أو الاستعداد أو الإضافي أو الإجازة أو الدورة."))
                }
                ForEach(logs) { l in
                    HStack {
                        Text(l.kind.rawValue).font(.caption.bold()).frame(width: 36, height: 36)
                            .background(Theme.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading) {
                            Text(store.employee(l.employeeID)?.name ?? "-").font(.subheadline.bold())
                            Text("\(Fmt.date(l.date, "d MMMM")) · \(l.kind.title)\(l.note.isEmpty ? "" : " · \(l.note)")").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(Fmt.hours(l.hours)) س").font(.headline)
                        Button(role: .destructive) { store.data.hours.removeAll { $0.id == l.id } } label: { Image(systemName: "trash") }
                            .accessibilityLabel("حذف السجل")
                    }
                }
            }
            .card()
        }
    }
}

struct EmployeesView: View {
    @Environment(AppStore.self) private var store
    @Binding var sheet: ActiveSheet?
    @State private var query = ""
    @State private var editing: Employee?

    var body: some View {
        let list = store.departmentEmployees.filter {
            query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.employeeNumber.contains(query)
        }
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text("\(store.departmentEmployees.count) موظفًا").font(.caption).foregroundStyle(.secondary)
                    Text("دليل الموظفين").font(.title2.bold())
                }
                Spacer()
                Button { sheet = .addEmployee } label: { Label("إضافة موظف", systemImage: "plus") }
                    .buttonStyle(.borderedProminent)
            }
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("بحث بالاسم أو الرقم", text: $query)
            }
            .padding(12).background(Theme.background, in: RoundedRectangle(cornerRadius: 12))
            if list.isEmpty { ContentUnavailableView.search(text: query) }
            ForEach(list) { e in
                Button { editing = e } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(e.name).font(.headline).foregroundStyle(.primary)
                            Text(e.title).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text(e.employeeNumber).font(.subheadline).foregroundStyle(.primary)
                            Text(e.department).font(.caption2).foregroundStyle(.secondary)
                        }
                        Image(systemName: e.linked ? "link.circle.fill" : "link.circle").foregroundStyle(e.linked ? Theme.primary : .secondary)
                            .accessibilityLabel(e.linked ? "حساب مربوط" : "غير مربوط")
                    }
                    .padding(.vertical, 6)
                }
                Divider()
            }
        }
        .card()
        .sheet(item: $editing) { EmployeeForm(employee: $0) }
    }
}

struct EventsView: View {
    @Environment(AppStore.self) private var store
    @Binding var sheet: ActiveSheet?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("الدورات والفعاليات").font(.title2.bold())
                Spacer()
                Button { sheet = .addEvent } label: { Label("إضافة", systemImage: "plus") }.buttonStyle(.borderedProminent)
            }
            if store.data.events.isEmpty { ContentUnavailableView("لا توجد فعاليات", systemImage: "book.pages") }
            ForEach(store.data.events.sorted { $0.date < $1.date }) { ev in
                HStack {
                    EventRow(event: ev)
                    Button(role: .destructive) { store.data.events.removeAll { $0.id == ev.id } } label: { Image(systemName: "trash") }
                        .accessibilityLabel("حذف")
                }
                Divider()
            }
        }
        .card()
    }
}

struct AlertsView: View {
    @Environment(AppStore.self) private var store
    @State private var status: UNAuthorizationStatus = .notDetermined

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 12) {
                IconTile(symbol: store.data.settings.notificationsEnabled ? "bell.badge.fill" : "bell", size: 64)
                Text(store.data.settings.notificationsEnabled ? "التنبيهات مفعّلة على جهازك" : "فعّل التنبيهات على جهازك").font(.title3.bold())
                Text("ستصلك تنبيهات اعتماد الجدول وبداية الشفت والفعاليات.").font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button {
                    Task {
                        let ok = await NotificationManager.shared.requestPermission()
                        store.data.settings.notificationsEnabled = ok
                        status = await NotificationManager.shared.status()
                        if ok {
                            await NotificationManager.shared.notifyNow(title: "مِناوب", body: "تم تفعيل التنبيهات بنجاح ✅")
                            await store.rescheduleNotifications()
                        }
                    }
                } label: { Label(store.data.settings.notificationsEnabled ? "إعادة الجدولة" : "تفعيل التنبيهات", systemImage: "bell") }
                .buttonStyle(PrimaryButtonStyle())
                if status == .denied {
                    Text("التنبيهات مرفوضة. فعّلها من الإعدادات ← مِناوب ← الإشعارات.").font(.caption).foregroundStyle(.orange)
                }
                Text(Session.shared.online ? "متصل بخادم مِناوب: تصل تنبيهات Push لكل الفريق حتى والتطبيق مغلق." : "وضع محلي: التنبيهات من هذا الجهاز فقط. سجّل الدخول لتفعيل تنبيهات Push.")
                    .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .card()
            NotificationTestPanel()
            VStack(alignment: .leading, spacing: 12) {
                Text("متى يرسل النظام؟").font(.title3.bold())
                Label("اعتماد الجدول — بعد الاعتماد فقط.", systemImage: "paperplane")
                Label("بداية الشفت — قبل البداية بـ \(store.data.settings.reminderMinutesBefore) دقيقة.", systemImage: "alarm")
                Label("الدورات والفعاليات — قبلها بساعة.", systemImage: "book.pages")
            }
            .card()
            VStack(alignment: .leading, spacing: 10) {
                Text("\(store.data.sendLog.count) عملية إرسال").font(.caption).foregroundStyle(.secondary)
                Text("سجل الإرسال").font(.title3.bold())
                ForEach(store.data.sendLog.prefix(30)) { l in
                    VStack(alignment: .leading) {
                        Text(l.title).font(.subheadline.bold())
                        Text("\(l.detail) · \(Fmt.date(l.date, "d MMM HH:mm"))").font(.caption).foregroundStyle(.secondary)
                    }
                    Divider()
                }
            }
            .card()
        }
        .task { status = await NotificationManager.shared.status() }
    }
}

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var newDept = ""
    @State private var confirmReset = false

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 16) {
            if Session.shared.online || Session.shared.demoInfo { HospitalInfoCard() }
            VStack(alignment: .leading, spacing: 12) {
                Text("المستشفى").font(.title3.bold())
                TextField("اسم المستشفى", text: $store.data.settings.hospital)
                    .padding(12).background(Theme.background, in: RoundedRectangle(cornerRadius: 12))
            }.card()
            VStack(alignment: .leading, spacing: 10) {
                Text("الأقسام").font(.title3.bold())
                ForEach(store.data.settings.departments, id: \.self) { d in
                    HStack {
                        Text(d)
                        Spacer()
                        if store.data.settings.departments.count > 1 {
                            Button(role: .destructive) {
                                store.data.settings.departments.removeAll { $0 == d }
                                if store.data.selectedDepartment == d { store.selectDepartment(store.data.settings.departments[0]) }
                            } label: { Image(systemName: "minus.circle") }
                            .accessibilityLabel("حذف القسم")
                        }
                    }
                }
                HStack {
                    TextField("قسم جديد", text: $newDept)
                    Button("إضافة") {
                        let n = newDept.trimmingCharacters(in: .whitespaces)
                        if !n.isEmpty && !store.data.settings.departments.contains(n) { store.data.settings.departments.append(n); Task { try? await Session.shared.addDepartment(n) } }
                        newDept = ""
                    }
                }
                .padding(12).background(Theme.background, in: RoundedRectangle(cornerRadius: 12))
            }.card()
            VStack(alignment: .leading, spacing: 10) {
                Text("أوقات الشفتات").font(.title3.bold())
                Stepper("بداية النهاري: \(store.data.settings.dayStartHour):00", value: $store.data.settings.dayStartHour, in: 0...23)
                Stepper("بداية الليلي: \(store.data.settings.nightStartHour):00", value: $store.data.settings.nightStartHour, in: 0...23)
                Stepper("طول الشفت: \(store.data.settings.shiftLength) ساعة", value: $store.data.settings.shiftLength, in: 4...24)
                Stepper("التذكير قبل: \(store.data.settings.reminderMinutesBefore) دقيقة", value: $store.data.settings.reminderMinutesBefore, in: 0...240, step: 15)
                Button("تطبيق على التنبيهات") { Task { await store.rescheduleNotifications(); try? await Session.shared.updateProfile(name: nil, phone: nil, photo: nil, reminder: store.data.settings.reminderMinutesBefore) } }.buttonStyle(.bordered)
            }.card()
            Button("إعادة البيانات التجريبية", role: .destructive) { confirmReset = true }
                .confirmationDialog("سيتم حذف كل البيانات", isPresented: $confirmReset, titleVisibility: .visible) {
                    Button("إعادة تعيين", role: .destructive) { store.data = AppStore.seed(); store.currentMonth = Date() }
                }
            ProfileCard()
            NotificationTestPanel()
            if Session.shared.online { DeleteAccountCard() }
            Button(role: .destructive) { Session.shared.logout() } label: { Label(Session.shared.offlineMode ? "الخروج من الوضع المحلي" : "تسجيل الخروج", systemImage: "rectangle.portrait.and.arrow.right") }
                .buttonStyle(OutlineButtonStyle())
            Text("مِناوب 2.2 — \(Session.shared.online ? "متزامن مع الخادم" : "البيانات على هذا الجهاز")").font(.caption).foregroundStyle(.secondary)
        }
    }
}
