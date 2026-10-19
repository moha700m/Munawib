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
