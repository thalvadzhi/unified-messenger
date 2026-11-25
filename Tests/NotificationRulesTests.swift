import Foundation

func runNotificationRulesTests() {
    let t0 = Date(timeIntervalSince1970: 1000)
    test("looking requires all three") {
        check(NotificationRules.isUserLooking(at: .messenger, appIsActive: true, windowVisible: true, selected: .messenger), "all")
        check(!NotificationRules.isUserLooking(at: .messenger, appIsActive: true, windowVisible: true, selected: .instagram), "other selected")
        check(!NotificationRules.isUserLooking(at: .messenger, appIsActive: false, windowVisible: true, selected: .messenger), "inactive")
        check(!NotificationRules.isUserLooking(at: .messenger, appIsActive: true, windowVisible: false, selected: .messenger), "hidden")
    }
    test("fallback copy") {
        let t = NotificationRules.fallbackText(for: .instagram, unread: 3)
        check(t.title == "New message on Instagram" && t.body == "3 unread", "\(t)")
    }
    test("stable fallback id") { check(NotificationRules.fallbackIdentifier(for: .messenger) == "fallback-messenger", "") }
    test("page id") { check(NotificationRules.pageIdentifier(for: .instagram, notificationID: "42") == "page-instagram-42", "") }
    test("page id without tag uses notification id") {
        check(NotificationRules.pageIdentifier(for: .instagram, notificationID: "42", tag: nil) == "page-instagram-42", "nil")
        check(NotificationRules.pageIdentifier(for: .instagram, notificationID: "42", tag: "") == "page-instagram-42", "empty")
    }
    test("page id with tag uses tag") {
        let a = NotificationRules.pageIdentifier(for: .messenger, notificationID: "1", tag: "thread-9")
        let b = NotificationRules.pageIdentifier(for: .messenger, notificationID: "2", tag: "thread-9")
        check(a == "page-messenger-tag-thread-9", a)
        check(a == b, "same tag replaces")
    }
    test("badge-less read threshold is 15 s") { check(NotificationRules.badgeLessReadThreshold == 15, "") }
    test("first count is baseline") { var g = FallbackGate(); check(g.noteUnread(.messenger, badge: 5, at: t0) == nil, "") }
    test("rise schedules check") {
        var g = FallbackGate(); _ = g.noteUnread(.messenger, badge: 1, at: t0)
        check(g.noteUnread(.messenger, badge: 2, at: t0) == t0.addingTimeInterval(3), "")
    }
    test("drop does not schedule") {
        var g = FallbackGate(); _ = g.noteUnread(.messenger, badge: 3, at: t0)
        check(g.noteUnread(.messenger, badge: 0, at: t0) == nil, "")
    }
    test("page notification before rise suppresses") {
        var g = FallbackGate(); g.notePageNotification(.instagram, at: t0)
        check(!g.shouldPostFallback(.instagram, roseAt: t0.addingTimeInterval(1), now: t0.addingTimeInterval(4)), "")
    }
    test("page notification after rise suppresses") {
        var g = FallbackGate(); g.notePageNotification(.instagram, at: t0.addingTimeInterval(2))
        check(!g.shouldPostFallback(.instagram, roseAt: t0, now: t0.addingTimeInterval(3)), "")
    }
    test("old page notification does not suppress") {
        var g = FallbackGate(); g.notePageNotification(.instagram, at: t0)
        check(g.shouldPostFallback(.instagram, roseAt: t0.addingTimeInterval(10), now: t0.addingTimeInterval(13)), "")
    }
    test("other service does not suppress") {
        var g = FallbackGate(); g.notePageNotification(.messenger, at: t0)
        check(g.shouldPostFallback(.instagram, roseAt: t0, now: t0.addingTimeInterval(3)), "")
    }
    test("reset baseline makes next count a baseline") {
        var g = FallbackGate(); _ = g.noteUnread(.messenger, badge: 0, at: t0)
        g.resetBaseline(.messenger, at: t0)
        let later = t0.addingTimeInterval(NotificationRules.settleWindow + 1)
        check(g.noteUnread(.messenger, badge: 3, at: t0.addingTimeInterval(1)) == nil, "within settle")
        check(g.noteUnread(.messenger, badge: 4, at: later) == later.addingTimeInterval(3), "rise after settle")
    }
    test("reset baseline is per service") {
        var g = FallbackGate(); _ = g.noteUnread(.instagram, badge: 1, at: t0)
        g.resetBaseline(.messenger, at: t0)
        check(g.noteUnread(.instagram, badge: 2, at: t0) != nil, "")
    }
    test("placeholder then badge within settle window does not rise") {
        var g = FallbackGate(); g.resetBaseline(.messenger, at: t0)
        check(g.noteUnread(.messenger, badge: nil, at: t0.addingTimeInterval(0.5)) == nil, "placeholder")
        check(g.noteUnread(.messenger, badge: 3, at: t0.addingTimeInterval(4)) == nil, "(3)")
    }
    test("placeholder lasting past settle window does not rise") {
        var g = FallbackGate(); g.resetBaseline(.messenger, at: t0)
        _ = g.noteUnread(.messenger, badge: nil, at: t0.addingTimeInterval(0.5))
        check(g.noteUnread(.messenger, badge: 3, at: t0.addingTimeInterval(11)) == nil, "")
    }
    test("short title flash does not rise") {
        var g = FallbackGate(); g.resetBaseline(.messenger, at: t0)
        let s = t0.addingTimeInterval(NotificationRules.settleWindow + 1)
        _ = g.noteUnread(.messenger, badge: 3, at: s)
        check(g.noteUnread(.messenger, badge: nil, at: s.addingTimeInterval(5)) == nil, "flash")
        check(g.noteUnread(.messenger, badge: 3, at: s.addingTimeInterval(6)) == nil, "back")
    }
    test("long badge-less period resets baseline to 0") {
        var g = FallbackGate(); g.resetBaseline(.messenger, at: t0)
        let s = t0.addingTimeInterval(NotificationRules.settleWindow + 1)
        _ = g.noteUnread(.messenger, badge: 3, at: s)
        _ = g.noteUnread(.messenger, badge: nil, at: s.addingTimeInterval(1))
        let back = s.addingTimeInterval(1 + NotificationRules.badgeLessReadThreshold)
        check(g.noteUnread(.messenger, badge: 1, at: back) == back.addingTimeInterval(3), "")
    }
    test("badge-less gap shorter than read threshold keeps baseline") {
        var g = FallbackGate(); g.resetBaseline(.messenger, at: t0)
        let s = t0.addingTimeInterval(NotificationRules.settleWindow + 1)
        _ = g.noteUnread(.messenger, badge: 3, at: s)
        _ = g.noteUnread(.messenger, badge: nil, at: s.addingTimeInterval(1))
        check(g.noteUnread(.messenger, badge: 1, at: s.addingTimeInterval(14)) == nil, "14 s gap")
    }
    test("rise after settle") {
        var g = FallbackGate(); g.resetBaseline(.messenger, at: t0)
        let s = t0.addingTimeInterval(NotificationRules.settleWindow + 1)
        _ = g.noteUnread(.messenger, badge: 3, at: s)
        let r = s.addingTimeInterval(1)
        check(g.noteUnread(.messenger, badge: 4, at: r) == r.addingTimeInterval(3), "")
    }
    test("badge-less from launch then first message rises") {
        var g = FallbackGate(); g.resetBaseline(.messenger, at: t0)
        _ = g.noteUnread(.messenger, badge: nil, at: t0.addingTimeInterval(1))
        let r = t0.addingTimeInterval(60)
        check(g.noteUnread(.messenger, badge: 1, at: r) == r.addingTimeInterval(3), "")
    }

    runDisplayedUnreadTests(t0)
    runFallbackDedupTests()
}

private func runDisplayedUnreadTests(_ t0: Date) {
    let th = NotificationRules.badgeLessReadThreshold
    test("displayed starts at 0") { let d = DisplayedUnread(); check(d.count(.messenger, at: t0) == 0, "") }
    test("displayed shows real badge") {
        var d = DisplayedUnread()
        check(d.note(.messenger, badge: 4, at: t0) == nil, "no recheck for a badge")
        check(d.count(.messenger, at: t0) == 4, "")
        check(d.lastBadge(.messenger) == 4, "")
    }
    test("displayed keeps badge through short badge-less flash") {
        var d = DisplayedUnread(); _ = d.note(.messenger, badge: 4, at: t0)
        let due = d.note(.messenger, badge: nil, at: t0.addingTimeInterval(1))
        check(due == t0.addingTimeInterval(1 + th), "recheck at \(String(describing: due))")
        check(d.count(.messenger, at: t0.addingTimeInterval(1 + th - 0.1)) == 4, "still 4 just before")
        _ = d.note(.messenger, badge: 4, at: t0.addingTimeInterval(2))
        check(d.count(.messenger, at: t0.addingTimeInterval(30)) == 4, "badge back")
    }
    test("displayed drops to 0 after badge-less threshold") {
        var d = DisplayedUnread(); _ = d.note(.messenger, badge: 4, at: t0)
        _ = d.note(.messenger, badge: nil, at: t0)
        check(d.count(.messenger, at: t0.addingTimeInterval(th)) == 0, "")
    }
    test("repeated badge-less titles keep the first start") {
        var d = DisplayedUnread(); _ = d.note(.messenger, badge: 2, at: t0)
        _ = d.note(.messenger, badge: nil, at: t0)
        let due = d.note(.messenger, badge: nil, at: t0.addingTimeInterval(10))
        check(due == t0.addingTimeInterval(th), "\(String(describing: due))")
        check(d.count(.messenger, at: t0.addingTimeInterval(th)) == 0, "")
    }
    test("displayed is per service") {
        var d = DisplayedUnread(); _ = d.note(.messenger, badge: 2, at: t0); _ = d.note(.instagram, badge: 5, at: t0)
        _ = d.note(.messenger, badge: nil, at: t0)
        check(d.count(.messenger, at: t0.addingTimeInterval(th)) == 0, "messenger")
        check(d.count(.instagram, at: t0.addingTimeInterval(th)) == 5, "instagram")
    }
}

private func runFallbackDedupTests() {
    test("dedup announces first nonzero count") {
        let d = FallbackDedup(); check(d.shouldAnnounce(.messenger, count: 1), "")
        check(!d.shouldAnnounce(.messenger, count: 0), "zero")
    }
    test("dedup suppresses same or lower count") {
        var d = FallbackDedup(); d.didAnnounce(.messenger, count: 3)
        check(!d.shouldAnnounce(.messenger, count: 3), "same")
        check(!d.shouldAnnounce(.messenger, count: 2), "lower")
        check(d.shouldAnnounce(.messenger, count: 4), "higher")
    }
    test("dedup is per service") {
        var d = FallbackDedup(); d.didAnnounce(.messenger, count: 3)
        check(d.shouldAnnounce(.instagram, count: 1), "")
    }
    test("dedup resets when user is looking") {
        var d = FallbackDedup(); d.didAnnounce(.messenger, count: 3)
        d.update(.messenger, displayed: 3, userLooking: true)
        check(d.shouldAnnounce(.messenger, count: 1), "")
    }
    test("dedup resets when displayed count drops to 0") {
        var d = FallbackDedup(); d.didAnnounce(.messenger, count: 3)
        d.update(.messenger, displayed: 0, userLooking: false)
        check(d.shouldAnnounce(.messenger, count: 1), "")
    }
    test("dedup keeps announced count otherwise") {
        var d = FallbackDedup(); d.didAnnounce(.messenger, count: 3)
        d.update(.messenger, displayed: 2, userLooking: false)
        check(!d.shouldAnnounce(.messenger, count: 3), "")
    }
}
