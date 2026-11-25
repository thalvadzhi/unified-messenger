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
}
