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
                    StatCard(symbol: "clock", tint: tints[k] ?? Theme.primary, caption: k.title, value: L("%@ ساعة", "\(Fmt.hours(store.total(k)))"), footnote: L("هذا الشهر"))
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading) {
                        Text(L("%@ سجل قابل للتدقيق", "\(logs.count)")).font(.caption).foregroundStyle(.secondary)
                        Text(L("تفاصيل %@", "\(store.monthTitle)")).font(.title2.bold())
                    }
                    Spacer()
                    Button { sheet = .addHours } label: { Label(L("إضافة سجل"), systemImage: "plus") }
                        .buttonStyle(.borderedProminent)
                }
                Text(L("H حضور فعلي · SB الاستعداد · OT الإضافي · CT تعويضي")).font(.caption).foregroundStyle(.secondary)
                if logs.isEmpty {
                    ContentUnavailableView(L("لم تُسجل ساعات بعد"), systemImage: "clock", description: Text(L("ابدأ بإضافة الحضور أو الاستعداد أو الإضافي أو الإجازة أو الدورة.")))
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
                        Text(L("%@ س", "\(Fmt.hours(l.hours))")).font(.headline)
                        Button(role: .destructive) { store.data.hours.removeAll { $0.id == l.id } } label: { Image(systemName: "trash") }
                            .accessibilityLabel(L("حذف السجل"))
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
                    Text(L("%@ موظفًا", "\(store.departmentEmployees.count)")).font(.caption).foregroundStyle(.secondary)
                    Text(L("دليل الموظفين")).font(.title2.bold())
                }
                Spacer()
                Button { sheet = .addEmployee } label: { Label(L("إضافة موظف"), systemImage: "plus") }
                    .buttonStyle(.borderedProminent)
            }
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                AppTextField(placeholder: L("بحث بالاسم أو الرقم"), text: $query).frame(minHeight: 32)
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
                            Text(Dept.display(e.department)).font(.caption2).foregroundStyle(.secondary)
                        }
                        Image(systemName: e.linked ? "link.circle.fill" : "link.circle").foregroundStyle(e.linked ? Theme.primary : .secondary)
                            .accessibilityLabel(e.linked ? L("حساب مربوط") : L("غير مربوط"))
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
                Text(L("الدورات والفعاليات")).font(.title2.bold())
                Spacer()
                Button { sheet = .addEvent } label: { Label(L("إضافة"), systemImage: "plus") }.buttonStyle(.borderedProminent)
            }
            if store.data.events.isEmpty { ContentUnavailableView(L("لا توجد فعاليات"), systemImage: "book.pages") }
            ForEach(store.data.events.sorted { $0.date < $1.date }) { ev in
                HStack {
                    EventRow(event: ev)
                    Button(role: .destructive) { store.data.events.removeAll { $0.id == ev.id } } label: { Image(systemName: "trash") }
                        .accessibilityLabel(L("حذف"))
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
                Text(store.data.settings.notificationsEnabled ? L("التنبيهات مفعّلة على جهازك") : L("فعّل التنبيهات على جهازك")).font(.title3.bold())
                Text(L("ستصلك تنبيهات اعتماد الجدول وبداية الشفت والفعاليات.")).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button {
                    Task {
                        let ok = await NotificationManager.shared.requestPermission()
                        store.data.settings.notificationsEnabled = ok
                        status = await NotificationManager.shared.status()
                        if ok {
                            await NotificationManager.shared.notifyNow(title: L("مِناوب"), body: L("تم تفعيل التنبيهات بنجاح ✅"))
                            await store.rescheduleNotifications()
                        }
                    }
                } label: { Label(store.data.settings.notificationsEnabled ? L("إعادة الجدولة") : L("تفعيل التنبيهات"), systemImage: "bell") }
                .buttonStyle(PrimaryButtonStyle())
                if status == .denied {
                    Text(L("التنبيهات مرفوضة. فعّلها من الإعدادات ← مِناوب ← الإشعارات.")).font(.caption).foregroundStyle(.orange)
                }
                Text(Session.shared.online ? L("متصل بخادم مِناوب: تصل تنبيهات Push لكل الفريق حتى والتطبيق مغلق.") : L("وضع محلي: التنبيهات من هذا الجهاز فقط. سجّل الدخول لتفعيل تنبيهات Push."))
                    .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .card()
            NotificationTestPanel()
            VStack(alignment: .leading, spacing: 12) {
                Text(L("متى يرسل النظام؟")).font(.title3.bold())
                Label(L("اعتماد الجدول — بعد الاعتماد فقط."), systemImage: "paperplane")
                Label(L("بداية الشفت — قبل البداية بـ %@ دقيقة.", "\(store.data.settings.reminderMinutesBefore)"), systemImage: "alarm")
                Label(L("الدورات والفعاليات — قبلها بساعة."), systemImage: "book.pages")
            }
            .card()
            VStack(alignment: .leading, spacing: 10) {
                Text(L("%@ عملية إرسال", "\(store.data.sendLog.count)")).font(.caption).foregroundStyle(.secondary)
                Text(L("سجل الإرسال")).font(.title3.bold())
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
            VStack(alignment: .leading, spacing: 10) {
                Text(L("اللغة / Language")).font(.title3.bold())
                LanguagePicker()
            }.card()
            if Session.shared.online || Session.shared.demoInfo { HospitalInfoCard() }
            VStack(alignment: .leading, spacing: 12) {
                Text(L("المستشفى")).font(.title3.bold())
                AppTextField(placeholder: L("اسم المستشفى"), text: $store.data.settings.hospital).frame(minHeight: 32)
                    .padding(12).background(Theme.background, in: RoundedRectangle(cornerRadius: 12))
            }.card()
            VStack(alignment: .leading, spacing: 10) {
                Text(L("الأقسام")).font(.title3.bold())
                ForEach(store.data.settings.departments, id: \.self) { d in
                    HStack {
                        Text(Dept.display(d))
                        Spacer()
                        if store.data.settings.departments.count > 1 {
                            Button(role: .destructive) {
                                store.data.settings.departments.removeAll { $0 == d }
                                if store.data.selectedDepartment == d { store.selectDepartment(store.data.settings.departments[0]) }
                            } label: { Image(systemName: "minus.circle") }
                            .accessibilityLabel(L("حذف القسم"))
                        }
                    }
                }
                HStack {
                    AppTextField(placeholder: L("قسم جديد"), text: $newDept).frame(minHeight: 32)
                    Button(L("إضافة")) {
                        let n = newDept.trimmingCharacters(in: .whitespaces)
                        if !n.isEmpty && !store.data.settings.departments.contains(n) { store.data.settings.departments.append(n); Task { try? await Session.shared.addDepartment(n) } }
                        newDept = ""
                    }
                }
                .padding(12).background(Theme.background, in: RoundedRectangle(cornerRadius: 12))
            }.card()
            VStack(alignment: .leading, spacing: 10) {
                Text(L("أوقات الشفتات")).font(.title3.bold())
                Stepper(L("بداية النهاري: %@:00", "\(store.data.settings.dayStartHour)"), value: $store.data.settings.dayStartHour, in: 0...23)
                Stepper(L("بداية الليلي: %@:00", "\(store.data.settings.nightStartHour)"), value: $store.data.settings.nightStartHour, in: 0...23)
                Stepper(L("طول الشفت: %@ ساعة", "\(store.data.settings.shiftLength)"), value: $store.data.settings.shiftLength, in: 4...24)
                Stepper(L("التذكير قبل: %@ دقيقة", "\(store.data.settings.reminderMinutesBefore)"), value: $store.data.settings.reminderMinutesBefore, in: 0...240, step: 15)
                Button(L("تطبيق على التنبيهات")) { Task { await store.rescheduleNotifications(); try? await Session.shared.updateProfile(name: nil, phone: nil, photo: nil, reminder: store.data.settings.reminderMinutesBefore) } }.buttonStyle(.bordered)
            }.card()
            Button(L("إعادة البيانات التجريبية"), role: .destructive) { confirmReset = true }
                .confirmationDialog(L("سيتم حذف كل البيانات"), isPresented: $confirmReset, titleVisibility: .visible) {
                    Button(L("إعادة تعيين"), role: .destructive) { store.data = AppStore.seed(); store.currentMonth = Date() }
                }
            ProfileCard()
            NotificationTestPanel()
            if Session.shared.online { DeleteAccountCard() }
            Button(role: .destructive) { Session.shared.logout() } label: { Label(Session.shared.offlineMode ? L("الخروج من الوضع المحلي") : L("تسجيل الخروج"), systemImage: "rectangle.portrait.and.arrow.right") }
                .buttonStyle(OutlineButtonStyle())
            Text(L("مِناوب 2.2 — %@", "\(Session.shared.online ? L("متزامن مع الخادم") : L("البيانات على هذا الجهاز"))")).font(.caption).foregroundStyle(.secondary)
        }
    }
}
