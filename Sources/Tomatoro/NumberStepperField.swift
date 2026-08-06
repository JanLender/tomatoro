import SwiftUI

/// An integer input that can be typed directly or nudged with a stepper
/// (step 1, so every value in the range is reachable from the keyboard).
///
/// While typing, an in-range whole number commits immediately; anything
/// else (non-numeric, out of range, empty) turns the field red and is
/// *not* committed — `value` simply keeps its last good number. The
/// standard companion to that: whenever the field loses focus (click
/// away, tab out, or the containing window closes) while still invalid,
/// it snaps back to that last valid value, so bad input can never linger
/// — including across closing and reopening a Settings-style window,
/// which doesn't necessarily recreate this view's `@State`.
struct NumberStepperField: View {
    /// Leading label shown before the field, e.g. "Hours". Pass `nil` when
    /// the field already sits next to a label elsewhere (e.g. a settings row).
    let label: String?
    /// Trailing suffix shown after the field, e.g. "min".
    let suffix: String?
    @Binding var value: Int
    let range: ClosedRange<Int>
    @Binding var isValid: Bool

    @State private var text: String
    @FocusState private var isFocused: Bool

    init(label: String? = nil, suffix: String? = nil, value: Binding<Int>, range: ClosedRange<Int>, isValid: Binding<Bool>) {
        self.label = label
        self.suffix = suffix
        self._value = value
        self.range = range
        self._isValid = isValid
        self._text = State(initialValue: String(value.wrappedValue))
    }

    private var accessibilityLabel: String { label ?? suffix ?? "Value" }

    var body: some View {
        HStack(spacing: 6) {
            if let label {
                Text("\(label):")
            }
            TextField(accessibilityLabel, text: $text)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 48)
                .labelsHidden()
                .focused($isFocused)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(isValid ? Color.clear : Color.red, lineWidth: 1)
                )
                .onChange(of: text) { _, newText in
                    validate(newText)
                }
                .onChange(of: isFocused) { _, focused in
                    if !focused { revertIfInvalid() }
                }
                .onSubmit {
                    revertIfInvalid()
                }
            if let suffix {
                Text(suffix)
                    .foregroundStyle(.secondary)
            }
            Stepper(accessibilityLabel, value: $value, in: range)
                .labelsHidden()
                .onChange(of: value) { _, newValue in
                    let synced = String(newValue)
                    if synced != text {
                        text = synced
                        isValid = true
                    }
                }
        }
        .onAppear {
            validate(text)
        }
    }

    private func validate(_ input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        if let parsed = Int(trimmed), range.contains(parsed) {
            value = parsed
            isValid = true
        } else {
            isValid = false
        }
    }

    private func revertIfInvalid() {
        guard !isValid else { return }
        text = String(value)
        isValid = true
    }
}
