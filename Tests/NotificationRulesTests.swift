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
    test("first count is baseline") { var g = FallbackGate(); check(g.noteUnread(.messenger, count: 5, at: t0) == nil, "") }
    test("rise schedules check") {
        var g = FallbackGate(); _ = g.noteUnread(.messenger, count: 1, at: t0)
        check(g.noteUnread(.messenger, count: 2, at: t0) == t0.addingTimeInterval(3), "")
    }
    test("drop does not schedule") {
        var g = FallbackGate(); _ = g.noteUnread(.messenger, count: 3, at: t0)
        check(g.noteUnread(.messenger, count: 0, at: t0) == nil, "")
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
}
