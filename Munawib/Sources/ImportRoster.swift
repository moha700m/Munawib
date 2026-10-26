import UIKit
import SwiftUI
import PhotosUI
import Vision
import ImageIO
import PDFKit
import UniformTypeIdentifiers

// MARK: - OCR

/// Vision text recognition (Arabic + English, accurate level). Returns word tokens with boxes for the grid parser
/// and reading-order lines for the date/keyword parser.
enum PhotoOCR {
    struct Reading {
        var tokens: [RosterParser.Token]
        var lines: [String]
    }

    static func read(_ image: UIImage) async -> Reading {
        guard let cg = image.cgImage else { return Reading(tokens: [], lines: []) }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        return await withCheckedContinuation { cont in
            let once = ResumeOnce()
            let req = VNRecognizeTextRequest { req, _ in
                let obs = (req.results as? [VNRecognizedTextObservation]) ?? []
                if once.claim() { cont.resume(returning: Reading(tokens: tokens(from: obs), lines: lines(from: obs))) }
            }
            req.recognitionLevel = .accurate
            req.usesLanguageCorrection = false
            req.recognitionLanguages = ["ar-SA", "en-US"]
            req.automaticallyDetectsLanguage = true
            let handler = VNImageRequestHandler(cgImage: cg, orientation: orientation, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do { try handler.perform([req]) } catch { if once.claim() { cont.resume(returning: Reading(tokens: [], lines: [])) } }
            }
        }
    }

    /// Vision may report a failed `perform` both through the thrown error and the completion handler.
    private final class ResumeOnce {
        private let lock = NSLock()
        private var done = false
        func claim() -> Bool { lock.lock(); defer { lock.unlock() }; if done { return false }; done = true; return true }
    }

    /// Splits multi-word observations into words with approximate boxes (columns of a table).
    private static func tokens(from obs: [VNRecognizedTextObservation]) -> [RosterParser.Token] {
        var out: [RosterParser.Token] = []
        for o in obs {
            guard let cand = o.topCandidates(1).first else { continue }
            let words = cand.string.split(separator: " ")
            if words.count <= 1 { out.append(RosterParser.Token(text: cand.string, box: o.boundingBox)); continue }
            let w = o.boundingBox.width / CGFloat(words.count)
            for (i, word) in words.enumerated() {
                out.append(RosterParser.Token(text: String(word), box: CGRect(x: o.boundingBox.minX + CGFloat(i) * w, y: o.boundingBox.minY, width: w, height: o.boundingBox.height)))
            }
        }
        return out
    }

    /// Groups observations that share a baseline into one line (top to bottom, right to left), so a date and the
    /// shift printed beside it end up in the same string even when Vision returns them as separate boxes.
    private static func lines(from obs: [VNRecognizedTextObservation]) -> [String] {
        let sorted = obs.sorted { $0.boundingBox.midY > $1.boundingBox.midY }
        var rows: [[VNRecognizedTextObservation]] = []
        for o in sorted {
            if var last = rows.last, let ref = last.first, abs(ref.boundingBox.midY - o.boundingBox.midY) < max(ref.boundingBox.height, o.boundingBox.height) * 0.6 {
                last.append(o); rows[rows.count - 1] = last
            } else {
                rows.append([o])
            }
        }
        return rows.map { row in
            row.sorted { $0.boundingBox.midX > $1.boundingBox.midX }
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: " ")
        }
    }
}

extension CGImagePropertyOrientation {
    init(_ o: UIImage.Orientation) {
        switch o {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

// MARK: - Grid parser (department tables)

enum RosterParser {
    struct Token { let text: String; let box: CGRect }
    struct Result { var grid: [String: [Int: ShiftCode]]; var cells: Int }

    static func recognize(_ image: UIImage) async -> [Token] { await PhotoOCR.read(image).tokens }

    /// Best-effort: rows anchored by employee numbers (or known names); columns anchored by header day numbers 1..31.
    static func parse(_ tokens: [Token], knownNumbers: [String], knownNames: [String] = []) -> Result {
        let codes: [String: ShiftCode] = ["D": .day, "E": .evening, "N": .night, "R": .rest, "L": .leave, "C": .course, "O": .rest, "X": .rest]
        var anchors: [(key: String, token: Token)] = []
        for t in tokens {
            let s = t.text.trimmingCharacters(in: .punctuationCharacters)
            if knownNumbers.contains(s) || (s.count >= 4 && s.allSatisfy(\.isNumber)) { anchors.append((s, t)) }
        }
        // Name anchors: first word of a known name whose last word sits on the same line.
        for name in knownNames {
            let parts = name.split(separator: " ").map(String.init)
            guard let first = parts.first, first.count >= 3 else { continue }
            for t in tokens where ShiftTextParser.normalizeArabic(t.text) == ShiftTextParser.normalizeArabic(first) {
                let tol = max(t.box.height * 0.7, 0.008)
                let sameLine = tokens.filter { abs($0.box.midY - t.box.midY) < tol }
                if parts.count == 1 || sameLine.contains(where: { ShiftTextParser.normalizeArabic($0.text) == ShiftTextParser.normalizeArabic(parts.last!) }) {
                    anchors.append((name.uppercased(), t)); break
                }
            }
        }
        // header: the horizontal line with the most 1..31 numbers
        let dayTokens = tokens.filter { if let n = Int($0.text), (1...31).contains(n) { return true }; return false }
        var bestLine: [Token] = []
        for t in dayTokens {
            let line = dayTokens.filter { abs($0.box.midY - t.box.midY) < 0.012 }
            if line.count > bestLine.count { bestLine = line }
        }
        let columns: [(Int, CGFloat)] = bestLine.compactMap { t in Int(t.text).map { ($0, t.box.midX) } }
        var grid: [String: [Int: ShiftCode]] = [:]
        var cells = 0
        for a in anchors {
            let tol = max(a.token.box.height * 0.7, 0.008)
            let rowTokens = tokens.filter { abs($0.box.midY - a.token.box.midY) < tol }
            var row: [Int: ShiftCode] = [:]
            let codeTokens = rowTokens.compactMap { t -> (ShiftCode, CGFloat)? in
                let s = t.text.uppercased().trimmingCharacters(in: .whitespaces)
                if let c = codes[s] { return (c, t.box.midX) }
                return nil
            }
            if columns.count >= 5 {
                for (c, x) in codeTokens {
                    if let col = columns.min(by: { abs($0.1 - x) < abs($1.1 - x) }) { row[col.0] = c }
                }
            } else {
                // no header: order codes by reading direction (left→right), number days sequentially
                for (i, ct) in codeTokens.sorted(by: { $0.1 < $1.1 }).enumerated() { row[i + 1] = ct.0 }
            }
            if !row.isEmpty, grid[a.key] == nil { grid[a.key] = row; cells += row.count }
        }
        return Result(grid: grid, cells: cells)
    }
}

// MARK: - Camera

struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage?) -> Void
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = .camera
        p.cameraCaptureMode = .photo
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onImage: onImage) }
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImage: (UIImage?) -> Void
        init(onImage: @escaping (UIImage?) -> Void) { self.onImage = onImage }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onImage(info[.originalImage] as? UIImage)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onImage(nil) }
    }
    static var available: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }
}

// MARK: - Import flow

/// «صوّر الجدول الورقي»: capture or pick a roster photo, read it with Vision, review the shifts, then save.
struct PhotoImportSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduce

    enum Step: Equatable { case pick, scanning, review }
    @State private var step: Step = .pick
    @State private var photo: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showFiles = false
    @State private var preview: UIImage?
    @State private var readings: [PhotoOCR.Reading] = []
    @State private var shifts: [ParsedShift] = []
    @State private var grid = RosterParser.Result(grid: [:], cells: 0)
    @State private var monthShift = 0
    @State private var sourceName = ""
    @State private var error: String?
    @State private var saving = false

    private var me: Employee? { store.myEmployee }
    private var session: Session { Session.shared }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .pick: pickStep
                case .scanning: scanningStep
                case .review: reviewStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(L("صوّر الجدول الورقي"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("إغلاق")) { dismiss() } }
                if step == .review {
                    ToolbarItem(placement: .primaryAction) {
                        Button { reset() } label: { Label(L("صورة أخرى"), systemImage: "camera.rotate") }
                    }
                }
            }
            .animation(Motion.entry(reduce), value: step)
            .fileImporter(isPresented: $showFiles, allowedContentTypes: [.pdf, .image]) { r in
                if case .success(let url) = r { Task { await loadFile(url) } }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { img in
                    showCamera = false
                    if let img { sourceName = L("صورة من الكاميرا"); Task { await process([img]) } }
                }
                .ignoresSafeArea()
            }
            .onChange(of: photo) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                        sourceName = L("صورة من الصور")
                        await process([img])
                    } else { error = L("تعذّر فتح الصورة") }
                    photo = nil
                }
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.direction)
        .preferredColorScheme(.dark)
    }

    // MARK: Steps

    private var pickStep: some View {
        ScrollView {
            VStack(spacing: 14) {
                VStack(spacing: 10) {
                    ZStack {
                        Circle().fill(Theme.primary.opacity(0.12)).frame(width: 96, height: 96)
                        Image(systemName: "doc.viewfinder").font(.system(size: 40, weight: .semibold)).foregroundStyle(Theme.primary)
                    }
                    .accessibilityHidden(true)
                    Text(L("حوّل الورقة إلى مناوبات")).font(.title3.weight(.heavy)).foregroundStyle(Theme.ink)
                    Text(L("نقرأ التواريخ وأنواع المناوبات من الصورة (عربي وإنجليزي) ونعرضها لك للمراجعة قبل الحفظ. لا تُرسل الصورة خارج جهازك."))
                        .font(.footnote).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .card()
                .entry(0)

                if CameraPicker.available {
                    Button { showCamera = true } label: { Label(L("التقاط صورة الآن"), systemImage: "camera.fill") }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("import.camera")
                        .entry(1)
                }
                PhotosPicker(selection: $photo, matching: .images) { Label(L("اختيار من الصور"), systemImage: "photo.on.rectangle") }
                    .buttonStyle(OutlineButtonStyle())
                    .entry(2)
                Button { showFiles = true } label: { Label(L("ملف PDF أو صورة من الملفات"), systemImage: "folder") }
                    .buttonStyle(OutlineButtonStyle())
                    .entry(3)

                VStack(alignment: .leading, spacing: 8) {
                    Text(L("للحصول على أفضل قراءة")).font(.subheadline.weight(.bold)).foregroundStyle(Theme.ink)
                    tip("sun.max", L("إضاءة جيدة وبدون ظلال على الورقة."))
                    tip("rectangle.dashed", L("اجعل الجدول يملأ الصورة وبشكل مستقيم."))
                    tip("textformat", L("الرموز المفهومة: D / E / N / R / L / C، نهاري، مسائي، ليلي، راحة، إجازة، والأوقات مثل 7-7."))
                }
                .card()
                .entry(4)

                if let error { Label(error, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(Theme.coral) }
            }
            .padding(16)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
    }

    private func tip(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(Theme.primary).frame(width: 22).accessibilityHidden(true)
            Text(text).font(.footnote).foregroundStyle(Theme.muted)
        }
    }

    private var scanningStep: some View {
        VStack(spacing: 18) {
            if let preview {
                Image(uiImage: preview).resizable().scaledToFit()
                    .frame(maxHeight: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.borderStrong, lineWidth: 1))
                    .overlay(ScanLine())
            }
            ProgressView().tint(Theme.primary)
            Text(L("نقرأ الصورة…")).font(.headline).foregroundStyle(Theme.ink)
            Text(L("التعرف على النص يتم على جهازك")).font(.caption).foregroundStyle(Theme.muted)
        }
        .padding(24)
    }

    private var reviewStep: some View {
        let total = shifts.count
        let hours = store.data.settings.shiftLength
        return VStack(spacing: 0) {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 12) {
                            if let preview {
                                Image(uiImage: preview).resizable().scaledToFill()
                                    .frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .accessibilityHidden(true)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(total == 0 ? L("لم نقرأ مناوبات من الصورة") : L("قرأنا %@ مناوبة من الصورة – راجعها", "\(total)"))
                                    .font(.headline).foregroundStyle(Theme.ink)
                                Text(total == 0 ? L("جرّب صورة أوضح، أو تأكد أن التواريخ والرموز ظاهرة.") : L("اضغط على مناوبة لتغيير نوعها، أو اسحبها لحذفها."))
                                    .font(.caption).foregroundStyle(Theme.muted)
                            }
                        }
                        if !shifts.isEmpty {
                            HStack(spacing: 8) {
                                ForEach([ShiftCode.day, .evening, .night], id: \.self) { c in
                                    let n = shifts.filter { $0.code == c }.count
                                    if n > 0 {
                                        Text("\(n) \(c.title)").font(.caption.weight(.semibold)).foregroundStyle(c.chipForeground)
                                            .padding(.horizontal, 8).padding(.vertical, 4).background(c.chipBackground, in: Capsule())
                                    }
                                }
                                let off = shifts.filter { !$0.code.isWorking }.count
                                if off > 0 { Text(L("%@ راحة/إجازة", "\(off)")).font(.caption).foregroundStyle(Theme.muted) }
                            }
                        }
                        monthAdjuster
                    }
                    .listRowBackground(Theme.card)
                }

                if !shifts.isEmpty {
                    Section {
                        ForEach(shifts) { s in
                            Menu {
                                ForEach(ShiftCode.allCases.filter { $0 != .empty }) { c in
                                    Button { change(s, to: c) } label: { Label(c.title, systemImage: c.symbol) }
                                }
                            } label: {
                                ShiftRow(date: s.date, code: s.code, hours: hours, detail: s.confidence < 0.75 ? L("تحقّق من التاريخ") : nil)
                            }
                            .listRowBackground(Theme.card)
                        }
                        .onDelete { idx in shifts.remove(atOffsets: idx) }
                    } header: {
                        Text(L("المناوبات المقروءة")).foregroundStyle(Theme.muted)
                    }
                }

                if session.isManager, grid.grid.count >= 2 {
                    Section {
                        Text(L("تم التعرف على %1$@ موظف و%2$@ خانة.", "\(grid.grid.count)", "\(grid.cells)")).font(.subheadline).foregroundStyle(Theme.ink)
                        Button {
                            store.applyImported(grid.grid, source: sourceName)
                            Haptics.success(); dismiss()
                        } label: { Label(L("تطبيق على جدول %@", "\(store.monthTitle)"), systemImage: "tablecells") }
                            .foregroundStyle(Theme.primary)
                    } header: {
                        Text(L("جدول القسم")).foregroundStyle(Theme.muted)
                    }
                    .listRowBackground(Theme.card)
                }

                if me == nil {
                    Section {
                        Label(L("لم يتم ربط حسابك بموظف، لذلك لا يمكن حفظ المناوبات لك."), systemImage: "person.crop.circle.badge.exclamationmark")
                            .font(.footnote).foregroundStyle(Theme.coral)
                    }
                    .listRowBackground(Theme.card)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)

            VStack(spacing: 8) {
                Button { Task { await save() } } label: {
                    HStack(spacing: 8) {
                        if saving { ProgressView().tint(Theme.onPrimary) }
                        Text(total == 1 ? L("حفظ مناوبة واحدة") : L("حفظ %@ مناوبة", "\(total)"))
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(total == 0 || me == nil || saving)
                .accessibilityIdentifier("import.save")
                Text(L("تُحفظ على هذا الجهاز وتظهر في «مناوباتي» ومدار يومك."))
                    .font(.caption2).foregroundStyle(Theme.muted)
            }
            .padding(16)
            .background(Theme.background)
        }
    }

    /// Shifts whose month the parser had to guess can be nudged to the previous / next month before saving.
    private var monthAdjuster: some View {
        HStack(spacing: 10) {
            Text(L("الشهر")).font(.caption).foregroundStyle(Theme.muted)
            Spacer()
            Button { monthShift -= 1; reparse() } label: { Image(systemName: "chevron.forward").frame(width: 36, height: 36) }
                .accessibilityLabel(L("الشهر السابق"))
            Text(Fmt.date(contextDate, "MMMM yyyy")).font(.subheadline.weight(.bold)).foregroundStyle(Theme.ink).monospacedDigit()
                .frame(minWidth: 120)
                .contentTransition(reduce ? ContentTransition.identity : ContentTransition.numericText())
            Button { monthShift += 1; reparse() } label: { Image(systemName: "chevron.backward").frame(width: 36, height: 36) }
                .accessibilityLabel(L("الشهر التالي"))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.ink)
    }

    private var contextDate: Date {
        Calendar.current.date(byAdding: .month, value: monthShift, to: store.currentMonth) ?? store.currentMonth
    }

    // MARK: Logic

    private func reset() {
        step = .pick; preview = nil; readings = []; shifts = []; grid = RosterParser.Result(grid: [:], cells: 0); monthShift = 0; error = nil
    }

    @MainActor private func loadFile(_ url: URL) async {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        sourceName = url.lastPathComponent
        var images: [UIImage] = []
        if url.pathExtension.lowercased() == "pdf", let doc = PDFDocument(url: url) {
            for i in 0..<min(doc.pageCount, 5) {
                guard let page = doc.page(at: i) else { continue }
                let b = page.bounds(for: .mediaBox)
                images.append(page.thumbnail(of: CGSize(width: b.width * 2.5, height: b.height * 2.5), for: .mediaBox))
            }
        } else if let d = try? Data(contentsOf: url), let img = UIImage(data: d) {
            images = [img]
        }
        if images.isEmpty { error = L("الملف غير مدعوم"); return }
        await process(images)
    }

    @MainActor private func process(_ images: [UIImage]) async {
        error = nil
        preview = images.first
        step = .scanning
        var rs: [PhotoOCR.Reading] = []
        for img in images { rs.append(await PhotoOCR.read(img)) }
        readings = rs
        reparse()
        if shifts.isEmpty && grid.grid.isEmpty { Haptics.error() } else { Haptics.success() }
        step = .review
    }

    /// Re-runs both parsers over the stored OCR output (cheap, so the month adjuster can call it freely).
    private func reparse() {
        let cal = Calendar.current
        let s = store.data.settings
        let ctx = ShiftTextParser.Context(year: cal.component(.year, from: contextDate), month: cal.component(.month, from: contextDate),
                                          dayStart: s.dayStartHour, eveningStart: s.eveningStart, nightStart: s.nightStartHour)
        let tokens = readings.flatMap(\.tokens)
        let lines = readings.flatMap(\.lines)
        let known = store.departmentEmployees.map(\.employeeNumber) + (me.map { [$0.employeeNumber] } ?? [])
        let names = store.departmentEmployees.map(\.name) + (me.map { [$0.name] } ?? [])
        grid = RosterParser.parse(tokens, knownNumbers: known, knownNames: names)

        var out: [ParsedShift] = []
        if let me, let row = grid.grid[me.employeeNumber] ?? grid.grid[me.name.uppercased()] {
            for (day, code) in row {
                if let d = cal.date(from: DateComponents(year: ctx.year, month: ctx.month, day: day)) {
                    out.append(ParsedShift(date: d, code: code, confidence: 0.85, source: L("صفك في الجدول")))
                }
            }
        }
        let days = Set(out.map { cal.startOfDay(for: $0.date) })
        out += ShiftTextParser.parse(lines: lines, context: ctx).filter { !days.contains(cal.startOfDay(for: $0.date)) }
        shifts = out.sorted { $0.date < $1.date }
    }

    private func change(_ s: ParsedShift, to code: ShiftCode) {
        guard let i = shifts.firstIndex(where: { $0.id == s.id }) else { return }
        withAnimation(Motion.quick(reduce)) { shifts[i].code = code }
        Haptics.tap()
    }

    @MainActor private func save() async {
        guard let me, !shifts.isEmpty else { return }
        saving = true
        let n = store.applyShifts(shifts, for: me.id, source: sourceName.isEmpty ? L("صورة الجدول") : sourceName)
        await store.rescheduleNotifications()
        saving = false
        if n > 0 { Haptics.success() }
        dismiss()
    }
}

/// Thin amber line that sweeps over the preview while Vision is working (static under Reduce Motion).
struct ScanLine: View {
    @State private var y: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        GeometryReader { g in
            Rectangle()
                .fill(LinearGradient(colors: [.clear, Theme.primary.opacity(0.9), .clear], startPoint: .leading, endPoint: .trailing))
                .frame(height: 2)
                .offset(y: reduce ? g.size.height / 2 : y)
                .onAppear {
                    guard !reduce else { return }
                    y = 0
                    withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { y = g.size.height - 2 }
                }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// One shift line: coloured side bar, weekday + date, shift name + time range, hours on the trailing edge.
struct ShiftRow: View {
    let date: Date
    let code: ShiftCode
    let hours: Int
    var detail: String? = nil
    @Environment(AppStore.self) private var store

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(code.isWorking ? code.color : code.color.opacity(0.5))
                .frame(width: 4, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(Fmt.date(date, "EEEE d MMMM")).font(.subheadline.weight(.bold)).foregroundStyle(Theme.ink)
                HStack(spacing: 6) {
                    Text(code.title).font(.caption.weight(.semibold)).foregroundStyle(code.isWorking ? code.color : Theme.muted)
                    if let h = store.data.settings.startHour(code) {
                        Text(Fmt.range(start: h, length: hours)).font(.caption).foregroundStyle(Theme.muted)
                    }
                    if let detail { Text("· \(detail)").font(.caption).foregroundStyle(Theme.amber) }
                }
                .lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 4)
            if code.isWorking {
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(hours)").font(.system(size: 20, weight: .heavy, design: .rounded)).monospacedDigit().foregroundStyle(Theme.ink)
                    Text(L("ساعة")).font(.caption2).foregroundStyle(Theme.muted)
                }
            } else {
                Image(systemName: code.symbol).foregroundStyle(Theme.muted)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(Fmt.date(date, "EEEE d MMMM"))، \(code.title)\(code.isWorking ? L("، %@ ساعة", "\(hours)") : "")")
    }
}
