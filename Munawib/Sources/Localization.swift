import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case ar, en
    var id: String { rawValue }
    var nativeName: String { self == .ar ? "العربية" : "English" }
    var locale: Locale { Locale(identifier: self == .ar ? "ar" : "en") }
    var direction: LayoutDirection { self == .ar ? .rightToLeft : .leftToRight }
}

/// In-app language selection. Applies immediately, is remembered, defaults to the device language.
@Observable final class LanguageManager {
    static let shared = LanguageManager()
    private static let key = "appLanguage"
    /// Snapshot readable from any context (formatters, API client, notifications).
    static var current: AppLanguage = resolveInitial()
    static var bundle: Bundle = makeBundle(current)

    var lang: AppLanguage {
        didSet {
            guard oldValue != lang else { return }
            UserDefaults.standard.set(lang.rawValue, forKey: Self.key)
            UserDefaults.standard.set([lang.rawValue], forKey: "AppleLanguages")
            Self.current = lang
            Self.bundle = Self.makeBundle(lang)
        }
    }
    var locale: Locale { lang.locale }
    var direction: LayoutDirection { lang.direction }

    private init() { lang = Self.current }

    private static func resolveInitial() -> AppLanguage {
        if let s = UserDefaults.standard.string(forKey: key), let l = AppLanguage(rawValue: s) { return l }
        let pref = Bundle.main.preferredLocalizations.first ?? Locale.preferredLanguages.first ?? "ar"
        return pref.hasPrefix("en") ? .en : .ar
    }
    private static func makeBundle(_ l: AppLanguage) -> Bundle {
        if let p = Bundle.main.path(forResource: l.rawValue, ofType: "lproj"), let b = Bundle(path: p) { return b }
        return .main
    }
}

/// Localized string lookup that follows the in-app language. Keys are the Arabic source strings.
func L(_ key: String, _ args: CVarArg...) -> String {
    let s = LanguageManager.bundle.localizedString(forKey: key, value: key, table: nil)
    return args.isEmpty ? s : String(format: s, locale: LanguageManager.current.locale, arguments: args)
}

struct LanguagePicker: View {
    @Bindable var lm = LanguageManager.shared
    var compact = false
    var body: some View {
        if compact {
            Menu {
                Picker("", selection: $lm.lang) { ForEach(AppLanguage.allCases) { Text($0.nativeName).tag($0) } }
            } label: {
                Label(lm.lang == .ar ? "English" : "العربية", systemImage: "globe")
                    .font(.subheadline.weight(.semibold))
            }
            .accessibilityIdentifier("languageMenu")
        } else {
            Picker(selection: $lm.lang) {
                ForEach(AppLanguage.allCases) { Text($0.nativeName).tag($0) }
            } label: { Label(L("اللغة / Language"), systemImage: "globe") }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("languagePicker")
        }
    }
}
