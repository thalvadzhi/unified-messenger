import Foundation

func runLinkRouterTests() {
    let m = Service.messenger, i = Service.instagram
    func u(_ s: String) -> URL { URL(string: s)! }
    func d(_ s: String, _ svc: Service) -> LinkDecision { LinkRouter.decide(u(s), for: svc) }
    test("thread stays") { let r = d("https://www.messenger.com/t/123", m); check(r == .inApp, "\(r)") }
    test("fb checkpoint stays") { let r = d("https://www.facebook.com/checkpoint/1", m); check(r == .inApp, "\(r)") }
    test("accounts center stays") { let r = d("https://accountscenter.facebook.com/x", i); check(r == .inApp, "\(r)") }
    test("auth.meta stays") { let r = d("https://auth.meta.com/login", m); check(r == .inApp, "\(r)") }
    test("ig challenge stays") { let r = d("https://www.instagram.com/challenge/", i); check(r == .inApp, "\(r)") }
    test("lookalike host external") { let r = d("https://evilfacebook.com/", m); check(r == .external(u("https://evilfacebook.com/")), "\(r)") }
    test("instagram not in messenger") { let r = d("https://www.instagram.com/", m); check(r == .external(u("https://www.instagram.com/")), "\(r)") }
    test("link shim unwrapped") {
        let r = d("https://l.facebook.com/l.php?u=https%3A%2F%2Fexample.com%2Fa&h=x", m)
        check(r == .external(u("https://example.com/a")), "\(r)")
    }
    test("ig link shim") { let r = d("https://l.instagram.com/?u=https%3A%2F%2Fexample.com", i); check(r == .external(u("https://example.com")), "\(r)") }
    test("mailto external") { let r = d("mailto:a@b.c", m); check(r == .external(u("mailto:a@b.c")), "\(r)") }
    test("blob in app") { let r = d("blob:https://www.messenger.com/abc", m); check(r == .inApp, "\(r)") }
    test("start URLs pinned") {
        check(m.startURL == u("https://www.messenger.com/"), "\(m.startURL)")
        check(i.startURL == u("https://www.instagram.com/direct/inbox/"), "\(i.startURL)")
    }
    test("uppercase scheme and host") { let r = d("HTTPS://WWW.MESSENGER.COM/t/1", m); check(r == .inApp, "\(r)") }
    test("shim without u does not crash") { _ = d("https://l.facebook.com/l.php", m) }
    test("shim with javascript u not external") {
        let r = d("https://l.facebook.com/l.php?u=javascript%3Aalert(1)", m)
        check(r != .external(u("javascript:alert(1)")), "\(r)")
    }
    test("fbcdn subdomain in instagram") { let r = d("https://scontent.fbcdn.net/x.jpg", i); check(r == .inApp, "\(r)") }
    test("file scheme blocked") { let r = d("file:///etc/passwd", m); check(r == .blocked, "\(r)") }
    test("smb scheme blocked") { let r = d("smb://host/share", i); check(r == .blocked, "\(r)") }
    test("system settings scheme blocked") {
        let r = d("x-apple.systempreferences:com.apple.preference.security?Privacy", m); check(r == .blocked, "\(r)")
    }
    test("custom app scheme blocked") { let r = d("zoommtg://zoom.us/join?confno=1", m); check(r == .blocked, "\(r)") }
    test("javascript scheme blocked") { let r = d("javascript:alert(1)", m); check(r == .blocked, "\(r)") }
    test("tel external") { let r = d("tel:+15551234", i); check(r == .external(u("tel:+15551234")), "\(r)") }
    test("https external") { let r = d("https://example.com/x", i); check(r == .external(u("https://example.com/x")), "\(r)") }
    test("uppercase MAILTO external") { let r = d("MAILTO:a@b.c", m); check(r == .external(u("MAILTO:a@b.c")), "\(r)") }
    test("shim with file u never external") {
        let r = d("https://l.facebook.com/l.php?u=file%3A%2F%2F%2Fetc%2Fpasswd", m)
        check(r != .external(u("file:///etc/passwd")), "\(r)")
    }
    test("shim with smb u never external") {
        let r = d("https://l.instagram.com/?u=smb%3A%2F%2Fhost%2Fshare", i)
        check(r != .external(u("smb://host/share")), "\(r)")
    }
    test("Service.with") { check(Service.with(.instagram) == Service.instagram, "") }
}
