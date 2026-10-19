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
                    Button("تم") { KeyboardHelper.dismiss() }.bold()
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

/// UIKit-backed digits field: reliable display/input while focused, normalizes Arabic-Indic digits, includes a "تم" accessory.
struct NumericField: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String
    var focusOnAppear = false
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UITextField {
        let f = UITextField()
        f.placeholder = placeholder
        f.keyboardType = .asciiCapableNumberPad
        f.textAlignment = .natural
        f.font = .preferredFont(forTextStyle: .body)
        f.adjustsFontForContentSizeCategory = true
        f.delegate = context.coordinator
        f.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        f.setContentHuggingPriority(.defaultLow, for: .horizontal)
        f.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let bar = UIToolbar(); bar.sizeToFit()
        bar.items = [UIBarButtonItem(systemItem: .flexibleSpace), UIBarButtonItem(title: "تم", style: .done, target: f, action: #selector(UIResponder.resignFirstResponder))]
        f.inputAccessoryView = bar
        f.text = text
        if focusOnAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { f.becomeFirstResponder() } }
        return f
    }
    func updateUIView(_ f: UITextField, context: Context) { if f.text != text { f.text = text } }
    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: NumericField
        init(_ p: NumericField) { parent = p }
        @objc func changed(_ f: UITextField) {
            let n = (f.text ?? "").asciiDigits.filter(\.isNumber)
            if f.text != n { f.text = n }
            parent.text = n
        }
    }
}
