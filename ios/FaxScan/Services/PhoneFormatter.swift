import Foundation

/// The app faxes US and Canada numbers (country code +1).
enum PhoneFormatter {
    /// Keeps at most 10 national digits, dropping a leading country code 1.
    static func nationalDigits(_ input: String) -> String {
        var digits = input.filter(\.isNumber)
        if digits.count == 11, digits.hasPrefix("1") { digits.removeFirst() }
        return String(digits.prefix(10))
    }

    static func e164(_ input: String) -> String? {
        let digits = nationalDigits(input)
        guard digits.count == 10,
              let area = digits.first, let exchange = digits.dropFirst(3).first,
              ("2"..."9").contains(area), ("2"..."9").contains(exchange) else { return nil }
        return "+1" + digits
    }

    /// "(212) 555-0100" while typing or for display.
    static func pretty(_ input: String) -> String {
        let d = Array(nationalDigits(input))
        switch d.count {
        case 0: return ""
        case 1...3: return "(" + String(d)
        case 4...6: return "(" + String(d[0..<3]) + ") " + String(d[3...])
        default: return "(" + String(d[0..<3]) + ") " + String(d[3..<6]) + "-" + String(d[6...])
        }
    }

    static func display(_ e164: String) -> String {
        "+1 " + pretty(e164)
    }
}
