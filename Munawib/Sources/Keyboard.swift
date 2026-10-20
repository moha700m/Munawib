import SwiftUI
import UIKit

extension String {
    /// Converts Arabic-Indic / Eastern Arabic digits to ASCII and trims spaces.
    var asciiDigits: String {
        var out = ""
        for ch in self {
            if ch.isNumber, let v = ch.wholeNumberValue, (0...9).contains(v) { out += String(v) } else { out.append(ch) }
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum KeyboardHelper {
    static func dismiss() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

struct KeyboardDoneModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(L("تم")) { KeyboardHelper.dismiss() }.bold()
                }
            }
    }
}

extension View {
    /// Adds a "تم" button above every keyboard and interactive dismissal.
    func keyboardDone() -> some View { modifier(KeyboardDoneModifier()) }

    /// Field with ASCII digit normalization (fixes Arabic-Indic number pad input).
    func digitsOnly(_ text: Binding<String>) -> some View {
        onChange(of: text.wrappedValue) { _, new in
            let n = new.asciiDigits.filter(\.isNumber)
            if n != new { text.wrappedValue = n }
        }
    }
}

struct FieldBox: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(12).frame(minHeight: 48)
            .background(Theme.background, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
    }
}
extension View { func fieldBox() -> some View { modifier(FieldBox()) } }

/// UIKit-backed text field used for every input in the app.
/// - Renders live while editing (binding updated on every `.editingChanged`, never only on end editing).
/// - Normalizes Arabic-Indic (٠-٩) and Extended Arabic-Indic (۰-۹) digits to Latin; never silently drops input
///   except non-digits in `digitsOnly` fields.
/// - Explicit label text colour so it can't be invisible on the focused background.
struct AppTextField: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var secure: Bool = false
    var digitsOnly: Bool = false
    var uppercase: Bool = false
    var ltr: Bool = false
    var contentType: UITextContentType? = nil
    var returnKey: UIReturnKeyType = .default
    var identifier: String? = nil
    var focusOnAppear = false
    var onReturn: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UITextField {
        let f = UITextField()
        f.placeholder = placeholder
        f.font = .preferredFont(forTextStyle: .body)
        f.adjustsFontForContentSizeCategory = true
        f.textColor = .label
        f.tintColor = UIColor(Theme.primary)
        f.borderStyle = .none
        f.backgroundColor = .clear
        f.delegate = context.coordinator
        f.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        f.setContentHuggingPriority(.defaultLow, for: .horizontal)
        f.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let bar = UIToolbar(); bar.sizeToFit()
        bar.items = [UIBarButtonItem(systemItem: .flexibleSpace), UIBarButtonItem(title: L("تم"), style: .done, target: f, action: #selector(UIResponder.resignFirstResponder))]
        f.inputAccessoryView = bar
        apply(f)
        f.text = text
        if focusOnAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { f.becomeFirstResponder() } }
        return f
    }
    private func apply(_ f: UITextField) {
        f.keyboardType = digitsOnly ? .asciiCapableNumberPad : keyboard
        f.isSecureTextEntry = secure
        f.textContentType = contentType
        f.autocapitalizationType = uppercase ? .allCharacters : .none
        f.autocorrectionType = .no
        f.spellCheckingType = .no
        f.returnKeyType = returnKey
        f.accessibilityIdentifier = identifier
        f.textAlignment = .natural
        if ltr { f.semanticContentAttribute = .unspecified }
    }
    func updateUIView(_ f: UITextField, context: Context) {
        context.coordinator.parent = self
        if f.isSecureTextEntry != secure { f.isSecureTextEntry = secure }
        // Only push external changes; never fight the user while they're typing.
        if f.text != text && !(f.isFirstResponder && f.markedTextRange != nil) { f.text = text }
    }
    static func normalize(_ s: String, digitsOnly: Bool, uppercase: Bool) -> String {
        var out = ""
        for ch in s {
            if let v = ch.wholeNumberValue, ch.isNumber, (0...9).contains(v) { out += String(v) }
            else if !digitsOnly { out.append(ch) }
        }
        return uppercase ? out.uppercased() : out
    }
    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: AppTextField
        init(_ p: AppTextField) { parent = p }
        @objc func changed(_ f: UITextField) {
            guard f.markedTextRange == nil else { return }
            let raw = f.text ?? ""
            let n = AppTextField.normalize(raw, digitsOnly: parent.digitsOnly, uppercase: parent.uppercase)
            if n != raw {
                let sel = f.selectedTextRange
                f.text = n
                if let sel { f.selectedTextRange = sel }
            }
            if parent.text != n { parent.text = n }
        }
        func textFieldShouldReturn(_ f: UITextField) -> Bool {
            if let r = parent.onReturn { r() } else { f.resignFirstResponder() }
            return true
        }
        func textFieldDidEndEditing(_ f: UITextField) { changed(f) }
    }
}

/// Back-compat wrapper.
struct NumericField: View {
    let placeholder: String
    @Binding var text: String
    var focusOnAppear = false
    var identifier: String? = nil
    var body: some View { AppTextField(placeholder: placeholder, text: $text, digitsOnly: true, ltr: true, identifier: identifier, focusOnAppear: focusOnAppear).frame(minHeight: 44) }
}
