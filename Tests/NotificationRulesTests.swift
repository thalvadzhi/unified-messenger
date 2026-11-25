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
        let back = s.addingTimeInterval(6)
        check(g.noteUnread(.messenger, badge: 1, at: back) == back.addingTimeInterval(3), "")
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
}
