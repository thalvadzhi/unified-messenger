import Foundation

enum UnreadCount {
    /// Parses a leading "(N)" or "(N+)" badge from a page title; 0 if absent.
    static func parse(title: String) -> Int {
        let trimmed = title.drop(while: { $0.isWhitespace })
        guard trimmed.first == "(" else { return 0 }
        let rest = trimmed.dropFirst()
        let digits = rest.prefix(while: { $0.isASCII && $0.isNumber })
        guard !digits.isEmpty else { return 0 }
        var tail = rest.dropFirst(digits.count)
        if tail.first == "+" { tail = tail.dropFirst() }
        guard tail.first == ")" else { return 0 }
        return Int(digits) ?? 0
    }
}
