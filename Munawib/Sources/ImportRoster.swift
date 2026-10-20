import UIKit
import SwiftUI
import PhotosUI
import Vision
import PDFKit
import UniformTypeIdentifiers

struct ImportRosterSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var photo: PhotosPickerItem?
    @State private var showFiles = false
    @State private var working = false
    @State private var result: RosterParser.Result?
    @State private var sourceName = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PhotosPicker(selection: $photo, matching: .images) { Label(L("اختيار صورة من الصور"), systemImage: "photo") }
                    Button { showFiles = true } label: { Label(L("اختيار PDF أو صورة من الملفات"), systemImage: "doc") }
                } footer: {
                    Text(L("ارفع صورة واضحة أو PDF. يحوّل النظام الصفحات إلى صور ثم يقرأ الجدول (أرقام وظيفية ورموز D/N/R) للمراجعة."))
                }
                if working { HStack { ProgressView(); Text(L("جاري قراءة الجدول…")) } }
                if let error { Text(error).foregroundStyle(.red) }
                if let result {
                    Section(L("النتيجة")) {
                        Text(L("تم التعرف على %1$@ موظف و%2$@ خانة.", "\(result.grid.count)", "\(result.cells)"))
                        ForEach(result.grid.keys.sorted(), id: \.self) { k in
                            let row = result.grid[k] ?? [:]
                            Text("\(k): " + row.keys.sorted().prefix(10).map { "\($0)\(row[$0]!.rawValue)" }.joined(separator: " "))
                                .font(.caption.monospaced())
                        }
                        Button(L("تطبيق على جدول %@", "\(store.monthTitle)")) {
                            store.applyImported(result.grid, source: sourceName)
                            dismiss()
                        }
                        .disabled(result.grid.isEmpty)
                    }
                }
            }
            .navigationTitle(L("رفع جدول"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L("إغلاق")) { dismiss() } } }
            .fileImporter(isPresented: $showFiles, allowedContentTypes: [.pdf, .image]) { r in
                if case .success(let url) = r { Task { await loadFile(url) } }
            }
            .onChange(of: photo) { _, item in
                guard let item else { return }
                Task {
                    working = true
                    if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                        sourceName = L("صورة من الصور")
                        await process([img])
                    } else { error = L("تعذّر فتح الصورة") }
                    working = false
                }
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.direction)
    }

    private func loadFile(_ url: URL) async {
        working = true; defer { working = false }
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

    private func process(_ images: [UIImage]) async {
        error = nil
        var all: [RosterParser.Token] = []
        for img in images { all += await RosterParser.recognize(img) }
        let known = store.departmentEmployees.map(\.employeeNumber)
        let r = RosterParser.parse(all, knownNumbers: known)
        result = r
        if r.grid.isEmpty { error = L("لم يتم التعرف على صفوف موظفين. تأكد أن الأرقام الوظيفية ظاهرة.") }
    }
}

enum RosterParser {
    struct Token { let text: String; let box: CGRect }
    struct Result { var grid: [String: [Int: ShiftCode]]; var cells: Int }

    static func recognize(_ image: UIImage) async -> [Token] {
        guard let cg = image.cgImage else { return [] }
        return await withCheckedContinuation { cont in
            let req = VNRecognizeTextRequest { req, _ in
                let obs = (req.results as? [VNRecognizedTextObservation]) ?? []
                var out: [Token] = []
                for o in obs {
                    guard let cand = o.topCandidates(1).first else { continue }
                    // split multi-word observations into words with approximate boxes
                    let words = cand.string.split(separator: " ")
                    if words.count <= 1 { out.append(Token(text: cand.string, box: o.boundingBox)); continue }
                    let w = o.boundingBox.width / CGFloat(words.count)
                    for (i, word) in words.enumerated() {
                        out.append(Token(text: String(word), box: CGRect(x: o.boundingBox.minX + CGFloat(i) * w, y: o.boundingBox.minY, width: w, height: o.boundingBox.height)))
                    }
                }
                cont.resume(returning: out)
            }
            req.recognitionLevel = .accurate
            req.usesLanguageCorrection = false
            req.recognitionLanguages = ["en-US", "ar-SA"]
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do { try handler.perform([req]) } catch { cont.resume(returning: []) }
            }
        }
    }

    /// Best-effort: rows anchored by employee numbers; columns anchored by header day numbers 1..31.
    static func parse(_ tokens: [Token], knownNumbers: [String]) -> Result {
        let codes: [String: ShiftCode] = ["D": .day, "N": .night, "R": .rest, "L": .leave, "C": .course, "O": .rest]
        let rowAnchors = tokens.filter { t in
            let s = t.text.trimmingCharacters(in: .punctuationCharacters)
            return knownNumbers.contains(s) || (s.count >= 4 && s.allSatisfy(\.isNumber))
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
        for a in rowAnchors {
            let num = a.text.trimmingCharacters(in: .punctuationCharacters)
            let tol = max(a.box.height * 0.7, 0.008)
            let rowTokens = tokens.filter { abs($0.box.midY - a.box.midY) < tol }
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
            if !row.isEmpty { grid[num] = row; cells += row.count }
        }
        return Result(grid: grid, cells: cells)
    }
}
