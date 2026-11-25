import Foundation

enum NotificationRules {
    static let fallbackDelay: TimeInterval = 3
    /// After a page load, counts only set the baseline for this long (the page is still settling).
    static let settleWindow: TimeInterval = 10

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
    private var badgelessSince: [ServiceID: Date] = [:]
    private var settleUntil: [ServiceID: Date] = [:]

    mutating func notePageNotification(_ s: ServiceID, at: Date) {
        lastPageNotification[s] = at
    }

    /// Records the page's title badge (`nil` when the title has none) and returns when to check
    /// for a fallback banner if the count rose. The first badge is the baseline. A badge-less
    /// title lowers the baseline to 0 only once it has lasted `fallbackDelay` (the user read
    /// everything); shorter gaps are title flashes and are ignored.
    mutating func noteUnread(_ s: ServiceID, badge: Int?, at: Date) -> Date? {
        let settling = settleUntil[s].map { at < $0 } ?? false
        guard let badge else {
            if badgelessSince[s] == nil {
                // Time spent settling after a load doesn't count as "read".
                badgelessSince[s] = max(at, settleUntil[s] ?? at)
            }
            return nil
        }
        var previous = lastCount[s]
        if let since = badgelessSince.removeValue(forKey: s),
           at.timeIntervalSince(since) >= NotificationRules.fallbackDelay {
            previous = 0
        }
        lastCount[s] = badge
        guard !settling, let previous, badge > previous else { return nil }
        return at.addingTimeInterval(NotificationRules.fallbackDelay)
    }

    /// Starts over after a page load at `at`: the next badge is a fresh baseline, and badges
    /// during the following `settleWindow` only update the baseline.
    mutating func resetBaseline(_ s: ServiceID, at: Date) {
        lastCount[s] = nil
        badgelessSince[s] = nil
        settleUntil[s] = at.addingTimeInterval(NotificationRules.settleWindow)
    }

    func shouldPostFallback(_ s: ServiceID, roseAt: Date, now: Date) -> Bool {
        guard let last = lastPageNotification[s] else { return true }
        return !(last >= roseAt.addingTimeInterval(-NotificationRules.fallbackDelay) && last <= now)
    }
}
