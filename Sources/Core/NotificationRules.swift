import Foundation

enum NotificationRules {
    static let fallbackDelay: TimeInterval = 3

    static func isUserLooking(at s: ServiceID, appIsActive: Bool, windowVisible: Bool, selected: ServiceID) -> Bool {
        appIsActive && windowVisible && selected == s
    }

    static func fallbackText(for s: ServiceID, unread: Int) -> (title: String, body: String) {
        (title: "New message on \(Service.with(s).name)", body: "\(unread) unread")
    }

    static func fallbackIdentifier(for s: ServiceID) -> String { "fallback-\(s.rawValue)" }

    static func pageIdentifier(for s: ServiceID, notificationID: String) -> String {
        "page-\(s.rawValue)-\(notificationID)"
    }
}

struct FallbackGate {
    private var lastCount: [ServiceID: Int] = [:]
    private var lastPageNotification: [ServiceID: Date] = [:]

    mutating func notePageNotification(_ s: ServiceID, at: Date) {
        lastPageNotification[s] = at
    }

    mutating func noteUnread(_ s: ServiceID, count: Int, at: Date) -> Date? {
        let previous = lastCount[s]
        lastCount[s] = count
        guard let previous, count > previous else { return nil }
        return at.addingTimeInterval(NotificationRules.fallbackDelay)
    }

    /// Forgets the last count so the next one is a fresh baseline (e.g. after a page load).
    mutating func resetBaseline(_ s: ServiceID) {
        lastCount[s] = nil
    }

    func shouldPostFallback(_ s: ServiceID, roseAt: Date, now: Date) -> Bool {
        guard let last = lastPageNotification[s] else { return true }
        return !(last >= roseAt.addingTimeInterval(-NotificationRules.fallbackDelay) && last <= now)
    }
}
