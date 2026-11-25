import Foundation

enum UnreadCount {
    /// Parses a leading "(N)" or "(N+)" badge from a page title; 0 if absent.
    static func parse(title: String) -> Int {
        badge(title: title) ?? 0
    }

    /// The leading "(N)" or "(N+)" badge of a page title, or nil when the title has none
    /// (a placeholder like "Messenger" or a flashing "Ann messaged you").
    static func badge(title: String) -> Int? {
        let trimmed = title.drop(while: { $0.isWhitespace })
        guard trimmed.first == "(" else { return nil }
        let rest = trimmed.dropFirst()
        let digits = rest.prefix(while: { $0.isASCII && $0.isNumber })
        guard !digits.isEmpty else { return nil }
        var tail = rest.dropFirst(digits.count)
        if tail.first == "+" { tail = tail.dropFirst() }
        guard tail.first == ")" else { return nil }
        return Int(digits)
    }
}
