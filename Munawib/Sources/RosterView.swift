import UIKit
import SwiftUI

struct RosterView: View {
    @Environment(AppStore.self) private var store
    @State private var pdfURL: URL?
    @State private var approving = false
    @State private var syncMsg: String?

    var body: some View {
        let emps = store.departmentEmployees
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button { store.shiftMonth(-1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                    .accessibilityLabel(L("الشهر السابق"))
                Spacer()
                VStack {
                    Text(L("المصدر: %@", "\(store.roster.source ?? L("لم يُرفع جدول بعد"))")).font(.caption).foregroundStyle(.secondary)
                    Text(L("جدول %1$@ — %2$@", "\(store.monthTitle)", "\(store.data.selectedDepartment)")).font(.headline).multilineTextAlignment(.center)
                }
                Spacer()
                Button { store.shiftMonth(1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                    .accessibilityLabel(L("الشهر التالي"))
            }
            HStack {
                StatusBadge(status: store.roster.status)
                Spacer()
                Button(L("حفظ المراجعة")) {
                    store.markReviewed()
                    Task { do { _ = try await Session.shared.pushRoster(store.roster, status: "review"); syncMsg = Session.shared.online ? L("تم الحفظ على الخادم") : nil } catch { syncMsg = (error as? LocalizedError)?.errorDescription } }
                }.buttonStyle(.bordered).disabled(!Session.shared.isManager)
                Button {
                    Task {
                        approving = true; await store.approve()
                        do { let n = try await Session.shared.pushRoster(store.roster, status: "approved"); if Session.shared.online { syncMsg = L("تم الاعتماد وإرسال %@ تنبيه Push", "\(n)") } } catch { syncMsg = (error as? LocalizedError)?.errorDescription }
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        approving = false
                    }
                } label: { Label(L("اعتماد وإرسال"), systemImage: "paperplane") }
                .buttonStyle(.borderedProminent)
                .disabled(approving || store.roster.status == .approved || !Session.shared.isManager)
            }
            if let syncMsg { Text(syncMsg).font(.caption).foregroundStyle(Theme.primary) }
            Label(L("اضغط على أي خانة لتغيير الرمز. أي تعديل بعد الاعتماد يعيد الجدول مسودة."), systemImage: "sparkles")
                .font(.footnote).foregroundStyle(Theme.primary)
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

            if emps.isEmpty {
                ContentUnavailableView(L("لا يوجد موظفون"), systemImage: "person.2.slash", description: Text(L("أضف موظفين لهذا القسم أولاً.")))
            } else {
                ScrollView(.horizontal) {
                    Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                        GridRow {
                            Text(L("الموظف")).frame(width: 150, alignment: .leading)
                            Text(L("الرقم")).frame(width: 50)
                            ForEach(1...store.daysInMonth, id: \.self) { d in
                                VStack(spacing: 0) {
                                    Text(weekday(d)).font(.caption2)
                                    Text("\(d)").font(.caption.bold())
                                }.frame(width: 40)
                            }
                            Text(L("ساعات")).frame(width: 50)
                        }
                        .font(.caption).foregroundStyle(.secondary)
                        ForEach(emps) { e in
                            GridRow {
                                Text(e.name).font(.footnote.bold()).lineLimit(1).frame(width: 150, alignment: .leading)
                                Text(e.employeeNumber).font(.footnote).frame(width: 50)
                                ForEach(1...store.daysInMonth, id: \.self) { d in
                                    CodeCell(emp: e.id, day: d)
                                }
                                Text("\(store.rosterHours(for: e.id))").font(.footnote.bold()).frame(width: 50)
                            }
                        }
                    }
                    .padding(12)
                }
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(.quaternary))
                legend
                Button {
                    pdfURL = RosterPDF.make(store: store)
                } label: { Label(L("تصدير PDF"), systemImage: "doc.richtext") }
                .buttonStyle(OutlineButtonStyle())
                if let pdfURL {
                    ShareLink(item: pdfURL) { Label(L("مشاركة ملف الجدول"), systemImage: "square.and.arrow.up") }
                        .buttonStyle(PrimaryButtonStyle())
                }
            }
        }
        .card()
    }

    private var legend: some View {
        ViewThatFits {
            HStack { legendItems }
            VStack(alignment: .leading) { legendItems }
        }
        .font(.caption).foregroundStyle(.secondary)
    }

    @ViewBuilder private var legendItems: some View {
        ForEach(ShiftCode.allCases) { c in
            Label("\(c.label) \(c.title)", systemImage: "square.fill").foregroundStyle(c.color)
        }
    }

    private func weekday(_ d: Int) -> String {
        guard let date = Calendar.current.date(from: DateComponents(year: store.year, month: store.month, day: d)) else { return "" }
        return Fmt.date(date, "EEEEE")
    }
}

struct CodeCell: View {
    @Environment(AppStore.self) private var store
    let emp: UUID
    let day: Int
    var body: some View {
        let c = store.code(for: emp, day: day)
        Menu {
            ForEach(ShiftCode.allCases) { opt in
                Button("\(opt.label) — \(opt.title)") { store.setCode(opt, emp: emp, day: day) }
            }
        } label: {
            Text(c.label).font(.footnote.bold())
                .frame(width: 40, height: 40)
                .foregroundStyle(c.color)
                .background(c.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        } primaryAction: {
            store.cycle(emp: emp, day: day)
            UISelectionFeedbackGenerator().selectionChanged()
        }
        .disabled(!Session.shared.isManager)
        .accessibilityLabel(L("يوم %1$@: %2$@", "\(day)", "\(c.title)"))
    }
}

enum RosterPDF {
    @MainActor
    static func make(store: AppStore) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Munawib-\(store.year)-\(store.month).pdf")
        let days = store.daysInMonth
        let emps = store.departmentEmployees
        let page = CGRect(x: 0, y: 0, width: 842, height: 595)
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        do {
            try renderer.writePDF(to: url) { ctx in
                ctx.beginPage()
                let title = L("%1$@ — جدول %2$@ — %3$@ (%4$@)", "\(store.data.settings.hospital)", "\(store.monthTitle)", "\(store.data.selectedDepartment)", "\(store.roster.status.title)")
                let para = NSMutableParagraphStyle(); para.alignment = .right; para.baseWritingDirection = .rightToLeft
                (title as NSString).draw(in: CGRect(x: 20, y: 20, width: 802, height: 30), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 15), .paragraphStyle: para])
                let nameW: CGFloat = 130
                let cellW = (802 - nameW) / CGFloat(days)
                let rowH: CGFloat = 24
                let center = NSMutableParagraphStyle(); center.alignment = .center
                let small: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 8), .paragraphStyle: center]
                var y: CGFloat = 60
                for d in 1...days {
                    let x = 822 - nameW - CGFloat(d) * cellW
                    ("\(d)" as NSString).draw(in: CGRect(x: x, y: y + 6, width: cellW, height: rowH), withAttributes: small)
                }
                y += rowH
                for e in emps {
                    UIColor.lightGray.setStroke()
                    UIBezierPath(rect: CGRect(x: 20, y: y, width: 802, height: rowH)).stroke()
                    (e.name as NSString).draw(in: CGRect(x: 822 - nameW, y: y + 6, width: nameW - 4, height: rowH), withAttributes: [.font: UIFont.systemFont(ofSize: 9), .paragraphStyle: para])
                    for d in 1...days {
                        let x = 822 - nameW - CGFloat(d) * cellW
                        (store.code(for: e.id, day: d).label as NSString).draw(in: CGRect(x: x, y: y + 6, width: cellW, height: rowH), withAttributes: small)
                    }
                    y += rowH
                }
            }
            return url
        } catch { return nil }
    }
}
