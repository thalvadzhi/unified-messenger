import Foundation

enum NotificationRules {
    static let fallbackDelay: TimeInterval = 3
    /// A badge-less title counts as "everything read" only once it has lasted this long;
    /// shorter gaps are title flashes ("Ann messaged you" alternating with "(1) Messenger").
    static let badgeLessReadThreshold: TimeInterval = 15
    /// After a page load, counts only set the baseline for this long (the page is still settling).
    static let settleWindow: TimeInterval = 10

    static func isUserLooking(at s: ServiceID, appIsActive: Bool, windowVisible: Bool, selected: ServiceID) -> Bool {
        appIsActive && windowVisible && selected == s
    }

    static func fallbackText(for s: ServiceID, unread: Int) -> (title: String, body: String) {
        (title: "New message on \(Service.with(s).name)", body: "\(unread) unread")
    }

    static func fallbackIdentifier(for s: ServiceID) -> String { "fallback-\(s.rawValue)" }

    /// A page notification with a non-empty `tag` replaces an earlier one with the same tag
    /// (as in browsers) instead of stacking, so its identifier derives from the tag.
    static func pageIdentifier(for s: ServiceID, notificationID: String, tag: String? = nil) -> String {
        if let tag, !tag.isEmpty { return "page-\(s.rawValue)-tag-\(tag)" }
        return "page-\(s.rawValue)-\(notificationID)"
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
    /// title lowers the baseline to 0 only once it has lasted `badgeLessReadThreshold` (the user read
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
           at.timeIntervalSince(since) >= NotificationRules.badgeLessReadThreshold {
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

/// The unread count shown in the sidebar and Dock: the last real "(N)" badge, until a badge-less
/// title has lasted `badgeLessReadThreshold`, then 0. Keeps title flashes from flickering badges.
struct DisplayedUnread {
    private var badges: [ServiceID: Int] = [:]
    private var badgelessSince: [ServiceID: Date] = [:]

    /// Records a title's badge (`nil` when it has none). For a badge-less title, returns when the
    /// displayed count would drop to 0, so the caller can recheck then even if no title follows.
    mutating func note(_ s: ServiceID, badge: Int?, at: Date) -> Date? {
        if let badge {
            badges[s] = badge
            badgelessSince[s] = nil
            return nil
        }
        let since = badgelessSince[s] ?? at
        badgelessSince[s] = since
        return since.addingTimeInterval(NotificationRules.badgeLessReadThreshold)
    }

    func count(_ s: ServiceID, at now: Date) -> Int {
        if let since = badgelessSince[s], now.timeIntervalSince(since) >= NotificationRules.badgeLessReadThreshold {
            return 0
        }
        return badges[s] ?? 0
    }

    /// The last real badge, regardless of badge-less titles since.
    func lastBadge(_ s: ServiceID) -> Int { badges[s] ?? 0 }
}

/// Keeps fallback banners from repeating: one is posted only when the count exceeds the last
/// announced count, which resets once the user looks at the service or its count drops to 0.
struct FallbackDedup {
    private var announced: [ServiceID: Int] = [:]

    func shouldAnnounce(_ s: ServiceID, count: Int) -> Bool {
        count > (announced[s] ?? 0)
    }

    mutating func didAnnounce(_ s: ServiceID, count: Int) {
        announced[s] = count
    }

    mutating func update(_ s: ServiceID, displayed: Int, userLooking: Bool) {
        if userLooking || displayed == 0 { announced[s] = 0 }
    }
}
