import Foundation

/// One shift read from a photo, before the user confirms it.
struct ParsedShift: Identifiable, Hashable {
    var id = UUID()
    var date: Date
    var code: ShiftCode
    /// 0…1, how sure the parser is about the date (explicit dates score highest).
    var confidence: Double
    /// The OCR line the shift came from, shown in the review screen.
    var source: String
}

/// Turns OCR text lines from a paper roster into dated shifts.
///
/// Understands Arabic and English dates (`12/3`, `2026-03-12`, `12 مارس`, `الأحد 12`, `Mar 12`), Arabic-Indic digits,
/// shift keywords in both languages (`D / N / E`, `نهاري / ليلي / مسائي`, `صباح / مساء / ليل`, `AM / PM`, `OFF / راحة`)
/// and time ranges (`7-7`, `19:00-07:00`) which are classified by their start hour. Pure Foundation, no UI.
enum ShiftTextParser {
    struct Context {
        var year: Int
        var month: Int
        var today: Date = Date()
        var calendar: Calendar = .current
        var dayStart: Int = 5
        var eveningStart: Int = 13
        var nightStart: Int = 17
    }

    // MARK: Normalisation

    static func normalizeDigits(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s {
            if let v = ch.unicodeScalars.first?.value {
                if (0x0660...0x0669).contains(v) { out.append(Character(UnicodeScalar(v - 0x0660 + 0x30)!)); continue }
                if (0x06F0...0x06F9).contains(v) { out.append(Character(UnicodeScalar(v - 0x06F0 + 0x30)!)); continue }
            }
            out.append(ch)
        }
        return out
    }

    /// Strips diacritics/tatweel and folds alef / ta-marbuta / alef-maqsura variants so keyword matching is forgiving.
    static func normalizeArabic(_ s: String) -> String {
        var out = ""
        for u in s.unicodeScalars {
            switch u.value {
            case 0x064B...0x0652, 0x0640, 0x0670: continue
            case 0x0622, 0x0623, 0x0625: out.unicodeScalars.append(UnicodeScalar(0x0627)!)
            case 0x0629: out.unicodeScalars.append(UnicodeScalar(0x0647)!)
            case 0x0649: out.unicodeScalars.append(UnicodeScalar(0x064A)!)
            default: out.unicodeScalars.append(u)
            }
        }
        return out
    }

    static func clean(_ line: String) -> String {
        normalizeArabic(normalizeDigits(line))
            .replacingOccurrences(of: "\u{200F}", with: "").replacingOccurrences(of: "\u{200E}", with: "")
            .replacingOccurrences(of: "[\\s|،,;]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: Vocabulary

    static let arabicMonths: [(String, Int)] = [
        ("يناير", 1), ("فبراير", 2), ("مارس", 3), ("ابريل", 4), ("مايو", 5), ("يونيو", 6), ("يوليو", 7), ("اغسطس", 8), ("سبتمبر", 9), ("اكتوبر", 10), ("نوفمبر", 11), ("ديسمبر", 12),
        ("كانون الثاني", 1), ("شباط", 2), ("اذار", 3), ("نيسان", 4), ("ايار", 5), ("حزيران", 6), ("تموز", 7), ("ايلول", 9), ("تشرين الاول", 10), ("تشرين الثاني", 11), ("كانون الاول", 12),
    ]
    static let englishMonths = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
    static let weekdays = ["الاحد", "احد", "الاثنين", "اثنين", "الثلاثاء", "ثلاثاء", "الاربعاء", "اربعاء", "الخميس", "خميس", "الجمعه", "جمعه", "السبت", "سبت",
                           "sun", "mon", "tue", "wed", "thu", "fri", "sat"]

    private static let latinCodes: [String: ShiftCode] = [
        "D": .day, "DAY": .day, "AM": .day, "M": .day, "MORNING": .day, "MORN": .day, "DS": .day,
        "E": .evening, "EVE": .evening, "EVENING": .evening, "PM": .evening, "A": .evening, "AFTERNOON": .evening, "AFT": .evening, "ES": .evening,
        "N": .night, "NIGHT": .night, "NT": .night, "NS": .night,
        "R": .rest, "O": .rest, "X": .rest, "OFF": .rest, "DO": .rest, "DAYOFF": .rest, "REST": .rest,
        "L": .leave, "V": .leave, "VAC": .leave, "AL": .leave, "LEAVE": .leave, "VACATION": .leave, "SL": .leave, "EL": .leave,
        "C": .course, "T": .course, "TR": .course, "TRN": .course, "TRAINING": .course, "COURSE": .course, "CME": .course, "ED": .course,
    ]
    private static let arabicCodes: [String: ShiftCode] = [
        "نهاري": .day, "نهار": .day, "صباحي": .day, "صباح": .day, "صباحيه": .day, "ص": .day,
        "مسائي": .evening, "مساء": .evening, "مسائيه": .evening, "عصر": .evening, "عصري": .evening, "عصريه": .evening, "م": .evening,
        "ليلي": .night, "ليل": .night, "ليليه": .night, "ل": .night,
        "راحه": .rest, "اوف": .rest, "عطله": .rest, "استراحه": .rest, "ر": .rest,
        "اجازه": .leave, "اجازة": .leave, "سنويه": .leave, "مرضيه": .leave, "ج": .leave,
        "دوره": .course, "تدريب": .course, "محاضره": .course, "دورة": .course,
    ]

    // MARK: Month context

    /// Month (and year when printed) mentioned anywhere in the text, e.g. "جدول شهر مارس 2026" or "03/2026".
    static func detectMonth(in lines: [String]) -> (month: Int, year: Int?)? {
        for raw in lines {
            let line = clean(raw)
            let lower = line.lowercased()
            for (name, m) in arabicMonths where lower.contains(name) {
                return (m, year(in: lower))
            }
            for (i, name) in englishMonths.enumerated() where lower.range(of: "\\b\(name)[a-z]*\\b", options: .regularExpression) != nil {
                return (i + 1, year(in: lower))
            }
            if let r = lower.range(of: "\\b(0?[1-9]|1[0-2])\\s*/\\s*(20\\d{2})\\b", options: .regularExpression) {
                let parts = lower[r].split(separator: "/").map { Int($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
                if parts.count == 2 { return (parts[0], parts[1]) }
            }
            if let r = lower.range(of: "\\b(20\\d{2})\\s*[-/]\\s*(0?[1-9]|1[0-2])\\b(?![-/]\\d)", options: .regularExpression) {
                let parts = lower[r].split(whereSeparator: { "-/".contains($0) }).map { Int($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
                if parts.count == 2 { return (parts[1], parts[0]) }
            }
        }
        return nil
    }

    private static func year(in s: String) -> Int? {
        guard let r = s.range(of: "\\b(20\\d{2})\\b", options: .regularExpression) else { return nil }
        return Int(s[r])
    }

    // MARK: Parsing

    static func parse(lines rawLines: [String], context: Context) -> [ParsedShift] {
        let cal = context.calendar
        var ctxMonth = context.month, ctxYear = context.year
        if let m = detectMonth(in: rawLines) {
            ctxMonth = m.month
            if let y = m.year { ctxYear = y }
            else {
                // A month more than one month in the past most likely belongs to next year's roster.
                let cur = cal.component(.month, from: context.today)
                if ctxYear == cal.component(.year, from: context.today), m.month < cur - 1 { ctxYear += 1 }
            }
        }

        var found: [Int: ParsedShift] = [:]   // keyed by yyyymmdd so later weaker reads don't overwrite stronger ones
        var dangling: (y: Int, m: Int, d: Int, conf: Double, src: String)?

        func key(_ y: Int, _ m: Int, _ d: Int) -> Int { y * 10000 + m * 100 + d }
        func emit(_ y: Int, _ m: Int, _ d: Int, _ code: ShiftCode, _ conf: Double, _ src: String) {
            guard (1...12).contains(m), d >= 1,
                  let first = cal.date(from: DateComponents(year: y, month: m, day: 1)),
                  let range = cal.range(of: .day, in: .month, for: first), range.contains(d),
                  let date = cal.date(from: DateComponents(year: y, month: m, day: d)) else { return }
            let k = key(y, m, d)
            if let old = found[k], old.confidence >= conf { return }
            found[k] = ParsedShift(date: date, code: code, confidence: conf, source: src)
        }

        for raw in rawLines {
            let line = clean(raw)
            guard !line.isEmpty else { continue }
            var rest = line
            var dates: [(y: Int, m: Int, d: Int, conf: Double)] = []

            // ISO yyyy-mm-dd
            for m in matches("\\b(20\\d{2})[-/.](\\d{1,2})[-/.](\\d{1,2})\\b", in: line) {
                if let y = Int(m[1]), let mo = Int(m[2]), let d = Int(m[3]) { dates.append((y, mo, d, 0.95)) }
                rest = rest.replacingOccurrences(of: m[0], with: " ")
            }
            // d/m or d/m/y (m/d when the first number cannot be a month, e.g. 3/14). Dashes and dots need a year so
            // that "7-7" style time ranges are not mistaken for dates.
            if dates.isEmpty {
                let hits = matches("(?<![\\d:])(\\d{1,2})/(\\d{1,2})(?:/(\\d{2,4}))?(?![\\d:])", in: line)
                    + matches("(?<![\\d:])(\\d{1,2})[.\\-](\\d{1,2})[.\\-](\\d{2,4})(?![\\d:])", in: line)
                for m in hits {
                    guard var a = Int(m[1]), var b = Int(m[2]) else { continue }
                    if a <= 12, b > 12, b <= 31 { swap(&a, &b) }
                    guard (1...31).contains(a), (1...12).contains(b) else { continue }
                    var y = ctxYear
                    if m.count > 3, let yy = Int(m[3]) { y = yy < 100 ? 2000 + yy : yy }
                    dates.append((y, b, a, 0.9))
                    rest = rest.replacingOccurrences(of: m[0], with: " ")
                }
            }
            // "12 مارس" / "مارس 12" / "Mar 12" / "12 Mar"
            if dates.isEmpty {
                let lower = line.lowercased()
                var monthHit: (name: String, month: Int)?
                for (name, mo) in arabicMonths where lower.contains(name) { monthHit = (name, mo); break }
                if monthHit == nil {
                    for (i, name) in englishMonths.enumerated() {
                        if let r = lower.range(of: "\\b\(name)[a-z]*\\b", options: .regularExpression) { monthHit = (String(lower[r]), i + 1); break }
                    }
                }
                if let hit = monthHit {
                    let stripped = line.replacingOccurrences(of: hit.name, with: " ", options: .caseInsensitive)
                    if let d = firstDayNumber(in: stripped) {
                        dates.append((ctxYear, hit.month, d, 0.9))
                        rest = stripped.replacingOccurrences(of: "\\b\(d)\\b", with: " ", options: .regularExpression)
                    }
                }
            }
            // weekday + bare day number ("الأحد 12", "Sun 12")
            if dates.isEmpty {
                let lower = line.lowercased()
                if weekdays.contains(where: { lower.range(of: "\\b\($0)\\b", options: .regularExpression) != nil }) || weekdays.contains(where: { $0.count > 3 && lower.contains($0) }) {
                    var stripped = line.replacingOccurrences(of: "\\b(sun|mon|tue|wed|thu|fri|sat)[a-z]*\\b", with: " ", options: [.regularExpression, .caseInsensitive])
                    for w in weekdays where w.unicodeScalars.first.map({ $0.value > 0x7F }) == true { stripped = stripped.replacingOccurrences(of: w, with: " ") }
                    if let d = firstDayNumber(in: stripped) {
                        dates.append((ctxYear, ctxMonth, d, 0.8))
                        rest = stripped.replacingOccurrences(of: "\\b\(d)\\b", with: " ", options: .regularExpression)
                    }
                }
            }

            let tokens = rest.split(separator: " ").map(String.init)
            let codes = tokens.compactMap { code(for: $0, shortLine: tokens.count <= 6, ctx: context) }

            if let date = dates.first {
                if let c = codes.first {
                    emit(date.y, date.m, date.d, c, date.conf, raw)
                    dangling = nil
                } else {
                    dangling = (date.y, date.m, date.d, date.conf - 0.3, raw)
                }
                continue
            }

            // "1 D 2 N 3 R" style runs: a day number followed by a code
            var pending: Int?
            var pairs = 0
            for t in tokens {
                if let n = Int(t), (1...31).contains(n) { pending = n; continue }
                if let c = code(for: t, shortLine: true, ctx: context), let d = pending {
                    emit(ctxYear, ctxMonth, d, c, 0.7, raw); pairs += 1; pending = nil
                } else if !t.allSatisfy(\.isNumber) { pending = nil }
            }
            if pairs > 0 { dangling = nil; continue }

            // a code on its own line right after a date-only line (OCR split the columns)
            if let c = codes.first, let d = dangling {
                emit(d.y, d.m, d.d, c, d.conf, d.src + " " + raw)
                dangling = nil
            }
        }
        return found.values.sorted { $0.date < $1.date }
    }

    // MARK: Helpers

    /// Shift code for one token. Single letters are only trusted on short, code-like lines (and Latin ones must be upper-case).
    static func code(for token: String, shortLine: Bool, ctx: Context) -> ShiftCode? {
        let t = token.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.symbols))
        guard !t.isEmpty else { return nil }
        if let r = timeRange(t) { return classify(startHour: r, ctx: ctx) }
        if let m = t.range(of: "^(\\d{1,2})(AM|PM|am|pm|ص|م)$", options: .regularExpression) {
            let s = String(t[m]); let h = Int(s.prefix { $0.isNumber }) ?? 0
            let pm = s.lowercased().hasSuffix("pm") || s.hasSuffix("م")
            return classify(startHour: (h % 12) + (pm ? 12 : 0), ctx: ctx)
        }
        let upper = t.uppercased()
        if let c = latinCodes[upper] {
            if t.count == 1 && (!shortLine || t != upper) { return nil }
            if t.count == 2 && !shortLine && t != upper { return nil }
            return c
        }
        let ar = normalizeArabic(t)
        if let c = arabicCodes[ar] {
            if ar.count == 1 && !shortLine { return nil }
            return c
        }
        return nil
    }

    /// Start hour of a "7-7", "7:00-19:00", "19 الى 7" range, if the token is one.
    static func timeRange(_ t: String) -> Int? {
        guard let m = matches("^(\\d{1,2})(?::\\d{2})?\\s*(?:-|–|—|to|الى|إلى)\\s*(\\d{1,2})(?::\\d{2})?$", in: t.lowercased()).first,
              let a = Int(m[1]), let b = Int(m[2]), a <= 24, b <= 24 else { return nil }
        return a % 24
    }

    /// The shift window a start hour falls in: each window runs from its start until the next window's start,
    /// wrapping past midnight (with the defaults 5/13/17: 23:00 and 01:00 are night, 12:00 is day).
    static func classify(startHour h: Int, ctx: Context) -> ShiftCode {
        let windows: [(ShiftCode, Int)] = [(.day, ctx.dayStart), (.evening, ctx.eveningStart), (.night, ctx.nightStart)].sorted { $0.1 < $1.1 }
        let hour = ((h % 24) + 24) % 24
        var current = windows.last!.0
        for w in windows where hour >= w.1 { current = w.0 }
        return current
    }

    private static func firstDayNumber(in s: String) -> Int? {
        for m in matches("\\b(\\d{1,2})\\b", in: s) { if let n = Int(m[1]), (1...31).contains(n) { return n } }
        return nil
    }

    /// Regex helper: each match as [whole, group1, group2, …] (missing optional groups are dropped from the tail).
    static func matches(_ pattern: String, in s: String) -> [[String]] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { m in
            var groups: [String] = []
            for i in 0..<m.numberOfRanges {
                let r = m.range(at: i)
                if r.location == NSNotFound { break }
                groups.append(ns.substring(with: r))
            }
            return groups
        }
    }
}
